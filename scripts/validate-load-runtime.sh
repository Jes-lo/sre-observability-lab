#!/usr/bin/env bash

set -euo pipefail

PROJECT="sre-observability-load-validation-$$"
PROFILE="load-test"

TARGET_ID=""
METRICS="$(mktemp)"

declare -A PRIMARY_BEFORE

N8N_BEFORE=""
PRIMARY_API_PRESENT="false"

cleanup() {
  RC=$?

  set +e

  echo
  echo "===== LOAD VALIDATION CLEANUP ====="

  docker compose \
    -p "$PROJECT" \
    --profile "$PROFILE" \
    down \
    --volumes \
    --remove-orphans \
    >/dev/null 2>&1 \
    || true

  rm -f "$METRICS"

  exit "$RC"
}

trap cleanup EXIT

echo "===== CAPTURE EXISTING LOCAL RUNTIME ====="

for SERVICE in \
  api \
  alertmanager \
  prometheus \
  loki \
  tempo \
  alloy \
  grafana
do
  ID="$(
    docker compose \
      ps \
      -q \
      "$SERVICE" \
      2>/dev/null \
      || true
  )"

  if [[ -n "$ID" ]]; then
    PRIMARY_BEFORE["$SERVICE"]="$ID"

    echo "$SERVICE=$ID"
  fi
done

if [[ -n "${PRIMARY_BEFORE[api]-}" ]]; then
  PRIMARY_API_PRESENT="true"

  STATUS="$(
    curl \
      --silent \
      --output /dev/null \
      --write-out '%{http_code}' \
      --max-time 3 \
      http://127.0.0.1:3000/api/error
  )"

  if [[ "$STATUS" != "403" ]]; then
    echo "FAIL: primary API faults are not disabled"
    exit 1
  fi

  echo "PASS: primary API faults disabled"
fi

if docker inspect n8n >/dev/null 2>&1; then
  N8N_BEFORE="$(
    docker inspect \
      -f '{{.Id}}' \
      n8n
  )"

  echo "external_n8n=$N8N_BEFORE"
fi

echo
echo "===== START ISOLATED LOAD TARGET ====="

docker compose \
  -p "$PROJECT" \
  --profile "$PROFILE" \
  up \
  -d \
  --build \
  --no-deps \
  api-load-target

TARGET_ID="$(
  docker compose \
    -p "$PROJECT" \
    --profile "$PROFILE" \
    ps \
    -q \
    api-load-target
)"

if [[ -z "$TARGET_ID" ]]; then
  echo "FAIL: load target missing"
  exit 1
fi

echo "target=$TARGET_ID"
echo "project=$PROJECT"

echo
echo "===== WAIT FOR LOAD TARGET ====="

READY="false"

for _ in $(seq 1 45); do
  HEALTH="$(
    docker inspect \
      --format \
      '{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' \
      "$TARGET_ID"
  )"

  echo "health=$HEALTH"

  if [[ "$HEALTH" == "healthy" ]]; then
    READY="true"
    break
  fi

  if [[ "$HEALTH" == "dead" || "$HEALTH" == "exited" ]]; then
    docker logs "$TARGET_ID"
    exit 1
  fi

  sleep 1
done

if [[ "$READY" != "true" ]]; then
  docker logs "$TARGET_ID"
  echo "FAIL: load target did not become healthy"
  exit 1
fi

echo "PASS: isolated load target healthy"

echo
echo "===== VERIFY TARGET ISOLATION ====="

python3 - "$TARGET_ID" <<'PY'
import json
import subprocess
import sys

container_id = sys.argv[1]

raw = subprocess.check_output(
    [
        "docker",
        "inspect",
        container_id,
    ],
    text=True,
)

container = json.loads(raw)[0]

host = container["HostConfig"]
config = container["Config"]

environment = {}

for value in config.get("Env", []):
    key, _, item = value.partition("=")
    environment[key] = item

if environment.get("LAB_FAULTS_ENABLED") != "true":
    raise SystemExit(
        "FAIL: target faults not enabled"
    )

if environment.get("OTEL_TRACES_ENABLED") != "false":
    raise SystemExit(
        "FAIL: target tracing not disabled"
    )

if environment.get("LOG_FILE_PATH") != "/tmp/sre-api.log":
    raise SystemExit(
        "FAIL: target log path mismatch"
    )

if host.get("ReadonlyRootfs") is not True:
    raise SystemExit(
        "FAIL: target filesystem not read-only"
    )

if host.get("CapDrop") != ["ALL"]:
    raise SystemExit(
        "FAIL: target capabilities not dropped"
    )

if (
    "no-new-privileges:true"
    not in host.get(
        "SecurityOpt",
        [],
    )
):
    raise SystemExit(
        "FAIL: no-new-privileges missing"
    )

if host.get("PortBindings"):
    raise SystemExit(
        "FAIL: load target publishes host ports"
    )

networks = container[
    "NetworkSettings"
][
    "Networks"
]

if len(networks) != 1:
    raise SystemExit(
        "FAIL: target must have exactly one network"
    )

network_name = next(iter(networks))

raw = subprocess.check_output(
    [
        "docker",
        "network",
        "inspect",
        network_name,
    ],
    text=True,
)

network = json.loads(raw)[0]

if network.get("Internal") is not True:
    raise SystemExit(
        "FAIL: load-test network is not internal"
    )

print("faults_enabled=true")
print("host_ports=0")
print("network_internal=true")
print("PASS: isolated target runtime valid")
PY

run_scenario() {
  SCENARIO="$1"

  echo
  echo "===== RUN SCENARIO: $SCENARIO ====="

  docker compose \
    -p "$PROJECT" \
    --profile "$PROFILE" \
    run \
    --rm \
    --no-deps \
    -e "K6_SCENARIO=$SCENARIO" \
    -e K6_NO_COLOR=true \
    k6

  echo "PASS: $SCENARIO"
}

run_scenario healthy
run_scenario latency
run_scenario http500

echo
echo "===== VERIFY REAL APPLICATION METRICS ====="

docker exec \
  -i \
  "$TARGET_ID" \
  node - \
  > "$METRICS" <<'NODE'
fetch(
  "http://127.0.0.1:3000/metrics"
)
  .then((response) => {
    if (!response.ok) {
      throw new Error(
        `metrics HTTP ${response.status}`
      );
    }

    return response.text();
  })
  .then((text) => {
    process.stdout.write(text);
  })
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
NODE

python3 - "$METRICS" <<'PY'
from pathlib import Path
import sys

text = Path(
    sys.argv[1]
).read_text()

expected = {
    ("/api/work", "200"): None,
    ("/api/slow", "200"): None,
    ("/api/error", "500"): None,
}

for line in text.splitlines():
    if not line.startswith(
        "sre_lab_http_requests_total{"
    ):
        continue

    for route, status in expected:
        if (
            f'route="{route}"' in line
            and f'status_code="{status}"' in line
        ):
            value = float(
                line.rsplit(
                    " ",
                    1,
                )[1]
            )

            expected[
                (
                    route,
                    status,
                )
            ] = value

for (
    route,
    status,
), value in expected.items():
    print(
        f"route={route} "
        f"status={status} "
        f"count={value}"
    )

    if value is None or value <= 0:
        raise SystemExit(
            "FAIL: missing scenario metrics: "
            f"{route} {status}"
        )

print(
    "PASS: all expected real traffic series present"
)
PY

echo
echo "===== VERIFY K6 CONTAINERS ARE EPHEMERAL ====="

LEFTOVERS="$(
  docker ps \
    -aq \
    --filter \
    "label=com.docker.compose.project=$PROJECT" \
    --filter \
    label=com.docker.compose.service=k6
)"

if [[ -n "$LEFTOVERS" ]]; then
  echo "FAIL: k6 container remains after scenario"
  exit 1
fi

echo "PASS: k6 containers removed"

echo
echo "===== VERIFY EXISTING RUNTIME UNCHANGED ====="

for SERVICE in "${!PRIMARY_BEFORE[@]}"; do
  CURRENT="$(
    docker compose \
      ps \
      -q \
      "$SERVICE"
  )"

  if [[ "$CURRENT" != "${PRIMARY_BEFORE[$SERVICE]}" ]]; then
    echo "FAIL: existing $SERVICE changed"
    exit 1
  fi
done

if [[ "$PRIMARY_API_PRESENT" == "true" ]]; then
  STATUS="$(
    curl \
      --silent \
      --output /dev/null \
      --write-out '%{http_code}' \
      --max-time 3 \
      http://127.0.0.1:3000/api/error
  )"

  if [[ "$STATUS" != "403" ]]; then
    echo "FAIL: primary API fault state changed"
    exit 1
  fi
fi

if [[ -n "$N8N_BEFORE" ]]; then
  N8N_AFTER="$(
    docker inspect \
      -f '{{.Id}}' \
      n8n
  )"

  if [[ "$N8N_AFTER" != "$N8N_BEFORE" ]]; then
    echo "FAIL: external n8n changed"
    exit 1
  fi
fi

echo "PASS: existing runtime unchanged"

echo
echo "===== RUNTIME VALIDATION COMPLETE ====="

echo "PASS: healthy scenario"
echo "PASS: latency scenario"
echo "PASS: controlled HTTP 500 scenario"
echo "PASS: isolated runtime"
echo "PASS: controlled-load runtime validation succeeded"
