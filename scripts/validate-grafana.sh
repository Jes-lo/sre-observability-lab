#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1
  pwd
)"

cd "$ROOT_DIR"

STARTED_STACK=0

cleanup() {
  if [[ "$STARTED_STACK" -eq 1 ]]; then
    docker compose down >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT

echo "===== COMPOSE CONFIGURATION ====="

docker compose config --quiet

echo "PASS: Docker Compose configuration valid"

echo
echo "===== DETERMINISTIC PLUGIN SETTINGS ====="

COMPOSE_CONFIG="$(docker compose config)"

REQUIRED_SETTINGS=(
  'GF_PLUGINS_PREINSTALL_AUTO_UPDATE: "false"'
  'GF_PLUGINS_PLUGIN_ADMIN_ENABLED: "false"'
  'GF_ANALYTICS_CHECK_FOR_UPDATES: "false"'
  'GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES: "false"'
  'GF_ANALYTICS_REPORTING_ENABLED: "false"'
)

for SETTING in "${REQUIRED_SETTINGS[@]}"; do
  if grep -Fq "$SETTING" <<< "$COMPOSE_CONFIG"; then
    echo "PASS: $SETTING"
  else
    echo "FAIL: missing deterministic Grafana setting: $SETTING"
    exit 1
  fi
done

echo "PASS: Grafana runtime plugin updates disabled"

echo
echo "===== DASHBOARD STATIC VALIDATION ====="

python3 - <<'PY'
import json
from pathlib import Path

dashboard_path = Path(
    "grafana/dashboards/sre-red-overview.json"
)

with dashboard_path.open() as handle:
    dashboard = json.load(handle)

if dashboard.get("uid") != "sre-red-overview":
    raise SystemExit("FAIL: unexpected dashboard UID")

if dashboard.get("title") != "SRE Lab - RED Overview":
    raise SystemExit("FAIL: unexpected dashboard title")

panels = dashboard.get("panels", [])

if len(panels) != 4:
    raise SystemExit("FAIL: expected exactly 4 dashboard panels")

expected_queries = {
    "sre_api:http_requests:rate1m",
    "sre_api:http_5xx:rate1m",
    "sre_api:http_error_ratio:rate1m",
    "sre_api:http_request_duration_seconds:p95_1m",
}

actual_queries = {
    target.get("expr")
    for panel in panels
    for target in panel.get("targets", [])
}

if actual_queries != expected_queries:
    raise SystemExit("FAIL: unexpected Grafana PromQL query set")

for panel in panels:
    datasource = panel.get("datasource", {})

    if datasource.get("uid") != "prometheus":
        raise SystemExit(
            "FAIL: dashboard panel does not use Prometheus"
        )

print("dashboard_uid=sre-red-overview")
print("panels=4")

for query in sorted(actual_queries):
    print("query=" + query)

print("PASS: dashboard structure valid")
PY

echo
echo "===== PROVISIONING FILES ====="

test -f grafana/provisioning/datasources/prometheus.yml
test -f grafana/provisioning/dashboards/dashboards.yml

grep -Fxq \
  "    uid: prometheus" \
  grafana/provisioning/datasources/prometheus.yml

grep -Fxq \
  "    url: http://prometheus:9090" \
  grafana/provisioning/datasources/prometheus.yml

grep -Fxq \
  "      path: /etc/grafana/dashboards" \
  grafana/provisioning/dashboards/dashboards.yml

echo "PASS: provisioning files contain expected configuration"

echo
echo "===== START OR REUSE STACK ====="

if [[ -z "$(docker compose ps -q grafana)" ]]; then
  STARTED_STACK=1

  docker compose up \
    --detach \
    grafana
else
  echo "INFO: existing Grafana stack detected"
fi

echo
echo "===== GRAFANA HTTP HEALTH ====="

HTTP_READY=0

for i in $(seq 1 40); do
  if curl \
    --silent \
    --fail \
    http://127.0.0.1:3001/api/health \
    >/dev/null 2>&1; then

    HTTP_READY=1
    break
  fi

  sleep 2
done

if [[ "$HTTP_READY" -ne 1 ]]; then
  echo "FAIL: Grafana HTTP endpoint unavailable"
  docker compose logs grafana
  exit 1
fi

curl \
  --silent \
  --fail \
  http://127.0.0.1:3001/api/health \
  | python3 -c '
import json
import sys

data = json.load(sys.stdin)

print("version=" + str(data.get("version")))
print("database=" + str(data.get("database")))

if data.get("version") != "13.2.3":
    print("FAIL: unexpected Grafana version")
    sys.exit(1)

if data.get("database") != "ok":
    print("FAIL: Grafana database unhealthy")
    sys.exit(1)

print("PASS: Grafana HTTP health verified")
'

echo
echo "===== DOCKER HEALTH ====="

GRAFANA_ID="$(docker compose ps -q grafana)"
DOCKER_HEALTH=""

for i in $(seq 1 30); do
  DOCKER_HEALTH="$(
    docker inspect \
      "$GRAFANA_ID" \
      --format '{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}'
  )"

  if [[ "$DOCKER_HEALTH" == "healthy" ]]; then
    break
  fi

  if [[ "$DOCKER_HEALTH" == "unhealthy" ]]; then
    echo "FAIL: Grafana Docker healthcheck failed"
    exit 1
  fi

  sleep 2
done

echo "docker_health=$DOCKER_HEALTH"

if [[ "$DOCKER_HEALTH" != "healthy" ]]; then
  echo "FAIL: Grafana did not reach healthy state"
  exit 1
fi

echo "PASS: Grafana Docker health verified"

echo
echo "===== DATASOURCE PROVISIONING ====="

curl \
  --silent \
  --fail \
  http://127.0.0.1:3001/api/datasources/uid/prometheus \
  | python3 -c '
import json
import sys

data = json.load(sys.stdin)

expected = {
    "name": "Prometheus",
    "uid": "prometheus",
    "type": "prometheus",
    "url": "http://prometheus:9090",
}

for key, expected_value in expected.items():
    actual = data.get(key)

    print(f"{key}={actual}")

    if actual != expected_value:
        print(f"FAIL: unexpected datasource {key}")
        sys.exit(1)

if data.get("isDefault") is not True:
    print("FAIL: Prometheus datasource is not default")
    sys.exit(1)

print("PASS: Prometheus datasource provisioned")
'

echo
echo "===== DASHBOARD PROVISIONING ====="

curl \
  --silent \
  --fail \
  http://127.0.0.1:3001/api/dashboards/uid/sre-red-overview \
  | python3 -c '
import json
import sys

data = json.load(sys.stdin)
dashboard = data.get("dashboard", {})
meta = data.get("meta", {})

print("uid=" + str(dashboard.get("uid")))
print("title=" + str(dashboard.get("title")))
print("panels=" + str(len(dashboard.get("panels", []))))
print("folder=" + str(meta.get("folderTitle")))

if dashboard.get("uid") != "sre-red-overview":
    print("FAIL: dashboard UID mismatch")
    sys.exit(1)

if dashboard.get("title") != "SRE Lab - RED Overview":
    print("FAIL: dashboard title mismatch")
    sys.exit(1)

if len(dashboard.get("panels", [])) != 4:
    print("FAIL: dashboard panel count mismatch")
    sys.exit(1)

if meta.get("folderTitle") != "SRE Lab":
    print("FAIL: dashboard folder mismatch")
    sys.exit(1)

print("PASS: dashboard provisioned")
'

echo
echo "===== GENERATE APPLICATION TRAFFIC ====="

for i in $(seq 1 20); do
  curl \
    --silent \
    --fail \
    http://127.0.0.1:3000/api/work \
    >/dev/null
done

echo "PASS: application traffic generated"

echo
echo "===== GRAFANA TO PROMETHEUS QUERY ====="

METRIC_READY=0

for i in $(seq 1 24); do

  RESPONSE="$(
    curl \
      --silent \
      --fail \
      --get \
      --data-urlencode \
      'query=sre_api:http_requests:rate1m' \
      http://127.0.0.1:3001/api/datasources/proxy/uid/prometheus/api/v1/query
  )"

  RESULT_COUNT="$(
    python3 -c '
import json
import sys

data = json.load(sys.stdin)

print(
    len(
        data.get("data", {}).get("result", [])
    )
)
' <<< "$RESPONSE"
  )"

  if [[ "$RESULT_COUNT" -gt 0 ]]; then
    METRIC_READY=1

    python3 -c '
import json
import sys

data = json.load(sys.stdin)
results = data["data"]["result"]

print("series=" + str(len(results)))

for result in results:
    print("value=" + result["value"][1])
' <<< "$RESPONSE"

    break
  fi

  sleep 5
done

if [[ "$METRIC_READY" -ne 1 ]]; then
  echo "FAIL: Grafana could not retrieve Prometheus RED metric"
  exit 1
fi

echo "PASS: Grafana can query Prometheus"

echo
echo "===== RUNTIME SECURITY ====="

GRAFANA_UID="$(
  docker exec \
    "$GRAFANA_ID" \
    id -u
)"

echo "uid=$GRAFANA_UID"

if [[ "$GRAFANA_UID" == "0" ]]; then
  echo "FAIL: Grafana is running as root"
  exit 1
fi

RUNTIME="$(
  docker inspect \
    "$GRAFANA_ID" \
    --format '{{.HostConfig.ReadonlyRootfs}}|{{json .HostConfig.CapDrop}}|{{json .HostConfig.SecurityOpt}}|{{.HostConfig.Memory}}|{{.HostConfig.NanoCpus}}|{{.HostConfig.PidsLimit}}'
)"

echo "runtime=$RUNTIME"

EXPECTED='true|["ALL"]|["no-new-privileges:true"]|402653184|500000000|150'

if [[ "$RUNTIME" != "$EXPECTED" ]]; then
  echo "FAIL: unexpected Grafana runtime security configuration"
  exit 1
fi

echo "PASS: Grafana runtime security verified"

echo
echo "===== LOCALHOST EXPOSURE ====="

PORT="$(
  docker port \
    "$GRAFANA_ID" \
    3000/tcp
)"

echo "grafana_port=$PORT"

if [[ "$PORT" != "127.0.0.1:3001" ]]; then
  echo "FAIL: Grafana is not bound exclusively to localhost"
  exit 1
fi

echo "PASS: Grafana localhost exposure verified"

echo
echo "===== PLUGIN UPDATE BEHAVIOR ====="

PLUGIN_FAILURES="$(
  docker compose logs grafana 2>&1 \
    | grep -E \
        'Failed to install plugin.*(prometheus|postgresql|opentsdb|mssql|loki|influxdb|zipkin|jaeger|mysql)' \
    || true
)"

if [[ -n "$PLUGIN_FAILURES" ]]; then
  echo "FAIL: Grafana attempted bundled datasource updates"
  printf '%s\n' "$PLUGIN_FAILURES"
  exit 1
fi

echo "PASS: no bundled datasource update failures detected"

echo
echo "===== VALIDATION COMPLETE ====="

echo "PASS: Grafana dashboard validation succeeded"
