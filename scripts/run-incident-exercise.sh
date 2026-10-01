#!/usr/bin/env bash

set -euo pipefail

MODE="${1:-}"

case "$MODE" in
  availability|latency)
    ;;
  *)
    echo "Usage: $0 availability|latency"
    exit 2
    ;;
esac

PROM_IMAGE="prom/prometheus@sha256:6976aa8a60fec930796ce5772b8d12da7a318a5daa8d40d69c5c7819a05eeed7"
AM_IMAGE="prom/alertmanager@sha256:e9733bafb1bdef9b00e25a21f8f99dc26a22224bf16641ad754d1649f4c3357a"

PREFIX="sre-incident-${MODE}-$$"

NETWORK="${PREFIX}-network"
API_CONTAINER="${PREFIX}-api"
PROM_CONTAINER="${PREFIX}-prometheus"
AM_CONTAINER="${PREFIX}-alertmanager"

API_IMAGE="${PREFIX}-api:local"

TRAFFIC_PID=""

declare -A PRIMARY_BEFORE

N8N_BEFORE=""
PRIMARY_API_PRESENT="false"
RUNTIME_REMOVED="false"

cleanup() {
  RC=$?

  set +e

  if [[ -n "${TRAFFIC_PID:-}" ]]; then
    kill \
      "$TRAFFIC_PID" \
      >/dev/null 2>&1 \
      || true

    wait \
      "$TRAFFIC_PID" \
      >/dev/null 2>&1 \
      || true
  fi

  if [[ "$RUNTIME_REMOVED" != "true" ]]; then
    docker rm \
      -f \
      "$PROM_CONTAINER" \
      "$AM_CONTAINER" \
      "$API_CONTAINER" \
      >/dev/null 2>&1 \
      || true

    docker network rm \
      "$NETWORK" \
      >/dev/null 2>&1 \
      || true
  fi

  docker image rm \
    "$API_IMAGE" \
    >/dev/null 2>&1 \
    || true

  exit "$RC"
}

trap cleanup EXIT INT TERM

mapped_port() {
  CONTAINER="$1"
  CONTAINER_PORT="$2"

  docker port \
    "$CONTAINER" \
    "${CONTAINER_PORT}/tcp" \
    | head -n 1 \
    | awk -F: '{print $NF}'
}

wait_http() {
  URL="$1"
  NAME="$2"

  READY="false"

  for _ in $(seq 1 60); do
    if curl \
      --silent \
      --fail \
      --max-time 3 \
      "$URL" \
      >/dev/null 2>&1
    then
      READY="true"
      break
    fi

    sleep 1
  done

  if [[ "$READY" != "true" ]]; then
    echo "FAIL: $NAME did not become ready"
    exit 1
  fi
}

echo "=================================================="
echo "INCIDENT EXERCISE: $MODE"
echo "=================================================="

echo
echo "===== CAPTURE OPTIONAL EXISTING RUNTIME ====="

for SERVICE in \
  api \
  prometheus \
  alertmanager \
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

  echo "PASS: primary API remains fault-disabled"
fi

if docker inspect \
  n8n \
  >/dev/null 2>&1
then
  N8N_BEFORE="$(
    docker inspect \
      -f '{{.Id}}' \
      n8n
  )"

  echo "external_n8n=$N8N_BEFORE"
fi

echo
echo "===== VERIFY TEMPORARY NAMESPACE ====="

for CONTAINER in \
  "$API_CONTAINER" \
  "$PROM_CONTAINER" \
  "$AM_CONTAINER"
do
  if docker inspect \
    "$CONTAINER" \
    >/dev/null 2>&1
  then
    echo "FAIL: temporary container already exists: $CONTAINER"
    exit 1
  fi
done

if docker network inspect \
  "$NETWORK" \
  >/dev/null 2>&1
then
  echo "FAIL: temporary network already exists"
  exit 1
fi

echo "PASS: temporary namespace available"

echo
echo "===== BUILD EXERCISE API IMAGE ====="

docker build \
  --tag "$API_IMAGE" \
  ./app

echo "PASS: API image built"

echo
echo "===== CREATE ISOLATED NETWORK ====="

docker network create \
  "$NETWORK" \
  >/dev/null

echo "PASS: isolated network created"

echo
echo "===== START FAULT-ENABLED API ====="

docker run \
  --detach \
  --name "$API_CONTAINER" \
  --network "$NETWORK" \
  --network-alias api \
  --publish 127.0.0.1::3000 \
  --env NODE_ENV=production \
  --env HOST=0.0.0.0 \
  --env PORT=3000 \
  --env LAB_FAULTS_ENABLED=true \
  --env LOG_FILE_PATH=/tmp/sre-api.log \
  --env OTEL_TRACES_ENABLED=false \
  --env OTEL_METRICS_EXPORTER=none \
  --env OTEL_LOGS_EXPORTER=none \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=16m,mode=1777 \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --memory 256m \
  --cpus 0.50 \
  --pids-limit 100 \
  --init \
  "$API_IMAGE" \
  >/dev/null

API_PORT="$(
  mapped_port \
    "$API_CONTAINER" \
    3000
)"

if [[ -z "$API_PORT" ]]; then
  echo "FAIL: API host port not resolved"
  exit 1
fi

echo "api_port=$API_PORT"

wait_http \
  "http://127.0.0.1:${API_PORT}/healthz" \
  "temporary API"

echo "PASS: fault-enabled API ready"

echo
echo "===== VERIFY API FAULT STATE ====="

FAULT_STATUS="$(
  curl \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    --max-time 3 \
    "http://127.0.0.1:${API_PORT}/api/error"
)"

if [[ "$FAULT_STATUS" != "500" ]]; then
  echo "FAIL: temporary API faults not enabled"
  exit 1
fi

echo "PASS: temporary API faults enabled"

echo
echo "===== START ALERTMANAGER ====="

docker run \
  --detach \
  --name "$AM_CONTAINER" \
  --network "$NETWORK" \
  --network-alias alertmanager \
  --publish 127.0.0.1::9093 \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=16m,mode=1777 \
  --tmpfs /alertmanager:rw,noexec,nosuid,size=32m,mode=1777 \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --memory 128m \
  --cpus 0.25 \
  --pids-limit 100 \
  --init \
  --volume \
    "$PWD/observability/alertmanager/alertmanager.yml:/etc/alertmanager/alertmanager.yml:ro" \
  "$AM_IMAGE" \
  --config.file=/etc/alertmanager/alertmanager.yml \
  --storage.path=/alertmanager \
  --web.listen-address=0.0.0.0:9093 \
  --cluster.listen-address= \
  >/dev/null

AM_PORT="$(
  mapped_port \
    "$AM_CONTAINER" \
    9093
)"

if [[ -z "$AM_PORT" ]]; then
  echo "FAIL: Alertmanager host port not resolved"
  exit 1
fi

echo "alertmanager_port=$AM_PORT"

wait_http \
  "http://127.0.0.1:${AM_PORT}/-/ready" \
  "Alertmanager"

echo "PASS: Alertmanager ready"

echo
echo "===== START PROMETHEUS ====="

docker run \
  --detach \
  --name "$PROM_CONTAINER" \
  --network "$NETWORK" \
  --network-alias prometheus \
  --publish 127.0.0.1::9090 \
  --read-only \
  --tmpfs /tmp:rw,noexec,nosuid,size=16m,mode=1777 \
  --tmpfs /prometheus:rw,noexec,nosuid,size=128m,mode=1777 \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --memory 512m \
  --cpus 0.50 \
  --pids-limit 150 \
  --init \
  --volume \
    "$PWD/observability/prometheus:/etc/prometheus:ro" \
  "$PROM_IMAGE" \
  --config.file=/etc/prometheus/prometheus.yml \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=1h \
  --web.listen-address=0.0.0.0:9090 \
  >/dev/null

PROM_PORT="$(
  mapped_port \
    "$PROM_CONTAINER" \
    9090
)"

if [[ -z "$PROM_PORT" ]]; then
  echo "FAIL: Prometheus host port not resolved"
  exit 1
fi

echo "prometheus_port=$PROM_PORT"

wait_http \
  "http://127.0.0.1:${PROM_PORT}/-/ready" \
  "Prometheus"

echo "PASS: Prometheus ready"

echo
echo "===== ESTABLISH HEALTHY BASELINE ====="

for _ in $(seq 1 20); do
  curl \
    --silent \
    --fail \
    --max-time 3 \
    "http://127.0.0.1:${API_PORT}/api/work" \
    >/dev/null
done

python3 - "$PROM_PORT" <<'PY'
import json
import sys
import time
import urllib.parse
import urllib.request

port = sys.argv[1]

base = (
    f"http://127.0.0.1:{port}"
    "/api/v1/query"
)

query = (
    'sre_lab_http_requests_total'
    '{route="/api/work",status_code="200"}'
)

deadline = time.time() + 60

while True:
    url = (
        base
        + "?"
        + urllib.parse.urlencode(
            {
                "query": query,
            }
        )
    )

    with urllib.request.urlopen(
        url,
        timeout=5,
    ) as response:
        payload = json.load(response)

    result = payload[
        "data"
    ][
        "result"
    ]

    if result:
        print(
            "PASS: healthy baseline scraped"
        )
        break

    if time.time() >= deadline:
        raise SystemExit(
            "FAIL: healthy baseline not scraped"
        )

    time.sleep(2)
PY

echo
echo "===== START CONTROLLED INCIDENT TRAFFIC ====="

if [[ "$MODE" == "availability" ]]; then
  (
    set -euo pipefail

    while true; do
      curl \
        --silent \
        --fail \
        --max-time 3 \
        "http://127.0.0.1:${API_PORT}/api/work" \
        >/dev/null

      STATUS="$(
        curl \
          --silent \
          --output /dev/null \
          --write-out '%{http_code}' \
          --max-time 3 \
          "http://127.0.0.1:${API_PORT}/api/error"
      )"

      if [[ "$STATUS" != "500" ]]; then
        exit 1
      fi

      sleep 0.05
    done
  ) &
else
  (
    set -euo pipefail

    while true; do
      curl \
        --silent \
        --fail \
        --max-time 3 \
        "http://127.0.0.1:${API_PORT}/api/work" \
        >/dev/null

      curl \
        --silent \
        --fail \
        --max-time 3 \
        "http://127.0.0.1:${API_PORT}/api/slow?ms=500" \
        >/dev/null
    done
  ) &
fi

TRAFFIC_PID=$!

echo "traffic_pid=$TRAFFIC_PID"
echo "PASS: controlled $MODE incident traffic running"

echo
echo "===== WAIT FOR EXPECTED ALERTS ====="

python3 - "$PROM_PORT" "$MODE" <<'PY'
import json
import sys
import time
import urllib.request

port = sys.argv[1]
mode = sys.argv[2]

if mode == "availability":
    expected = {
        "SreApiHigh5xxRatio",
        "SreApiAvailabilityBurnRateFast",
        "SreApiAvailabilityBurnRateSlow",
    }
else:
    expected = {
        "SreApiHighLatencyRatio",
        "SreApiLatencyBurnRateFast",
        "SreApiLatencyBurnRateSlow",
    }

url = (
    f"http://127.0.0.1:{port}"
    "/api/v1/rules?type=alert"
)

deadline = time.time() + 180

while True:
    with urllib.request.urlopen(
        url,
        timeout=5,
    ) as response:
        payload = json.load(response)

    states = {}

    for group in payload[
        "data"
    ][
        "groups"
    ]:
        for rule in group.get(
            "rules",
            [],
        ):
            name = rule.get(
                "name"
            )

            if name in expected:
                states[name] = rule.get(
                    "state"
                )

    print(
        "alert_states="
        + repr(states)
    )

    if (
        set(states) == expected
        and all(
            state == "firing"
            for state in states.values()
        )
    ):
        print(
            "PASS: expected incident alerts reached firing"
        )
        break

    if time.time() >= deadline:
        raise SystemExit(
            "FAIL: expected alerts did not all reach firing: "
            + repr(states)
        )

    time.sleep(5)
PY

if ! kill -0 \
  "$TRAFFIC_PID" \
  >/dev/null 2>&1
then
  echo "FAIL: incident traffic process ended unexpectedly"
  exit 1
fi

echo
echo "===== VERIFY INCIDENT METRICS ====="

BEFORE_RATIO="$(
  python3 - "$PROM_PORT" "$MODE" <<'PY'
import json
import sys
import urllib.parse
import urllib.request

port = sys.argv[1]
mode = sys.argv[2]

if mode == "availability":
    query = (
        "sre_api:"
        "slo_availability_bad_ratio:"
        "rate1m"
    )
else:
    query = (
        "sre_api:"
        "slo_latency_bad_ratio:"
        "rate1m"
    )

url = (
    f"http://127.0.0.1:{port}"
    "/api/v1/query?"
    + urllib.parse.urlencode(
        {
            "query": query,
        }
    )
)

with urllib.request.urlopen(
    url,
    timeout=5,
) as response:
    payload = json.load(response)

result = payload[
    "data"
][
    "result"
]

if not result:
    raise SystemExit(
        "FAIL: missing incident bad-event ratio"
    )

value = float(
    result[0][
        "value"
    ][1]
)

if value <= 0.05:
    raise SystemExit(
        "FAIL: incident symptom threshold not exceeded"
    )

print(value)
PY
)"

echo "bad_ratio_before_mitigation=$BEFORE_RATIO"

python3 - "$PROM_PORT" "$MODE" <<'PY'
import json
import sys
import urllib.parse
import urllib.request

port = sys.argv[1]
mode = sys.argv[2]

if mode == "availability":
    queries = {
        "bad_ratio":
            "sre_api:slo_availability_bad_ratio:rate1m",

        "burn_1m":
            "sre_api:slo_availability_burn_rate:ratio1m",

        "burn_5m":
            "sre_api:slo_availability_burn_rate:ratio5m",

        "burn_15m":
            "sre_api:slo_availability_burn_rate:ratio15m",
    }
else:
    queries = {
        "bad_ratio":
            "sre_api:slo_latency_bad_ratio:rate1m",

        "burn_1m":
            "sre_api:slo_latency_burn_rate:ratio1m",

        "burn_5m":
            "sre_api:slo_latency_burn_rate:ratio5m",

        "burn_15m":
            "sre_api:slo_latency_burn_rate:ratio15m",
    }

base = (
    f"http://127.0.0.1:{port}"
    "/api/v1/query"
)

values = {}

for name, query in queries.items():
    url = (
        base
        + "?"
        + urllib.parse.urlencode(
            {
                "query": query,
            }
        )
    )

    with urllib.request.urlopen(
        url,
        timeout=5,
    ) as response:
        payload = json.load(response)

    result = payload[
        "data"
    ][
        "result"
    ]

    if not result:
        raise SystemExit(
            "FAIL: missing metric: "
            + query
        )

    value = float(
        result[0][
            "value"
        ][1]
    )

    values[name] = value

    print(
        f"{name}={value}"
    )

if values["bad_ratio"] <= 0.05:
    raise SystemExit(
        "FAIL: symptom threshold not exceeded"
    )

if values["burn_1m"] <= 10:
    raise SystemExit(
        "FAIL: 1m fast-burn threshold not exceeded"
    )

if values["burn_5m"] <= 10:
    raise SystemExit(
        "FAIL: 5m fast-burn threshold not exceeded"
    )

if values["burn_15m"] <= 2:
    raise SystemExit(
        "FAIL: sustained-burn threshold not exceeded"
    )

print(
    "PASS: incident metrics exceeded alert thresholds"
)
PY

echo
echo "===== VERIFY ALERTMANAGER ROUTING ====="

python3 - "$AM_PORT" "$MODE" <<'PY'
import json
import sys
import time
import urllib.request

port = sys.argv[1]
mode = sys.argv[2]

if mode == "availability":
    expected = {
        "SreApiHigh5xxRatio":
            "local-warning",

        "SreApiAvailabilityBurnRateFast":
            "local-critical",

        "SreApiAvailabilityBurnRateSlow":
            "local-warning",
    }
else:
    expected = {
        "SreApiHighLatencyRatio":
            "local-warning",

        "SreApiLatencyBurnRateFast":
            "local-critical",

        "SreApiLatencyBurnRateSlow":
            "local-warning",
    }

url = (
    f"http://127.0.0.1:{port}"
    "/api/v2/alerts/groups"
)

deadline = time.time() + 30

while True:
    with urllib.request.urlopen(
        url,
        timeout=5,
    ) as response:
        groups = json.load(response)

    observed = {}

    for group in groups:
        receiver = (
            group.get(
                "receiver",
                {},
            ).get(
                "name"
            )
        )

        for alert in group.get(
            "alerts",
            [],
        ):
            name = (
                alert.get(
                    "labels",
                    {},
                ).get(
                    "alertname"
                )
            )

            if name in expected:
                observed[
                    name
                ] = receiver

    print(
        "alertmanager_routes="
        + repr(observed)
    )

    if observed == expected:
        print(
            "PASS: incident alerts reached expected receivers"
        )
        break

    if time.time() >= deadline:
        raise SystemExit(
            "FAIL: Alertmanager routing mismatch: "
            + repr(observed)
        )

    time.sleep(2)
PY

echo
echo "===== MITIGATE INCIDENT ====="

kill \
  "$TRAFFIC_PID" \
  >/dev/null 2>&1 \
  || true

wait \
  "$TRAFFIC_PID" \
  >/dev/null 2>&1 \
  || true

TRAFFIC_PID=""

echo "PASS: controlled fault source stopped"

echo
echo "===== GENERATE RECOVERY TRAFFIC ====="

for _ in $(seq 1 400); do
  curl \
    --silent \
    --fail \
    --max-time 3 \
    "http://127.0.0.1:${API_PORT}/api/work" \
    >/dev/null
done

sleep 15

AFTER_RATIO="$(
  python3 - "$PROM_PORT" "$MODE" <<'PY'
import json
import sys
import urllib.parse
import urllib.request

port = sys.argv[1]
mode = sys.argv[2]

if mode == "availability":
    query = (
        "sre_api:"
        "slo_availability_bad_ratio:"
        "rate1m"
    )
else:
    query = (
        "sre_api:"
        "slo_latency_bad_ratio:"
        "rate1m"
    )

url = (
    f"http://127.0.0.1:{port}"
    "/api/v1/query?"
    + urllib.parse.urlencode(
        {
            "query": query,
        }
    )
)

with urllib.request.urlopen(
    url,
    timeout=5,
) as response:
    payload = json.load(response)

result = payload[
    "data"
][
    "result"
]

if not result:
    raise SystemExit(
        "FAIL: missing recovery bad-event ratio"
    )

print(
    float(
        result[0][
            "value"
        ][1]
    )
)
PY
)"

echo "bad_ratio_after_mitigation=$AFTER_RATIO"

python3 - \
  "$BEFORE_RATIO" \
  "$AFTER_RATIO" <<'PY'
import sys

before = float(
    sys.argv[1]
)

after = float(
    sys.argv[2]
)

print(
    f"before={before}"
)

print(
    f"after={after}"
)

if after >= before:
    raise SystemExit(
        "FAIL: bad-event ratio did not decrease after mitigation"
    )

print(
    "PASS: bad-event ratio decreased after mitigation"
)
PY

HEALTH_STATUS="$(
  curl \
    --silent \
    --output /dev/null \
    --write-out '%{http_code}' \
    --max-time 3 \
    "http://127.0.0.1:${API_PORT}/api/work"
)"

if [[ "$HEALTH_STATUS" != "200" ]]; then
  echo "FAIL: healthy endpoint did not recover"
  exit 1
fi

echo "PASS: healthy service response verified"

echo
echo "===== REMOVE INCIDENT RUNTIME ====="

docker rm \
  -f \
  "$PROM_CONTAINER" \
  "$AM_CONTAINER" \
  "$API_CONTAINER" \
  >/dev/null

docker network rm \
  "$NETWORK" \
  >/dev/null

RUNTIME_REMOVED="true"

echo "PASS: temporary incident runtime removed"

echo
echo "===== VERIFY NO INCIDENT RESIDUE ====="

for CONTAINER in \
  "$API_CONTAINER" \
  "$PROM_CONTAINER" \
  "$AM_CONTAINER"
do
  if docker inspect \
    "$CONTAINER" \
    >/dev/null 2>&1
  then
    echo "FAIL: temporary container remains: $CONTAINER"
    exit 1
  fi
done

if docker network inspect \
  "$NETWORK" \
  >/dev/null 2>&1
then
  echo "FAIL: temporary network remains"
  exit 1
fi

echo "PASS: no temporary containers or network remain"

echo
echo "===== VERIFY EXISTING RUNTIME UNCHANGED ====="

for SERVICE in "${!PRIMARY_BEFORE[@]}"; do
  CURRENT="$(
    docker compose \
      ps \
      -q \
      "$SERVICE"
  )"

  echo \
    "$SERVICE before=${PRIMARY_BEFORE[$SERVICE]} current=$CURRENT"

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

  echo "PASS: primary API remains fault-disabled"
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

  echo "PASS: external n8n unchanged"
fi

echo
echo "===== INCIDENT EVIDENCE SUMMARY ====="

echo "scenario=$MODE"
echo "alerts_expected=3"
echo "alerts_firing=true"
echo "alertmanager_routing_valid=true"
echo "bad_ratio_before=$BEFORE_RATIO"
echo "bad_ratio_after=$AFTER_RATIO"
echo "mitigation=controlled_fault_source_stopped"
echo "healthy_response=200"
echo "temporary_runtime_removed=true"
echo "primary_runtime_changed=false"

echo
echo "=================================================="
echo "INCIDENT EXERCISE PASSED: $MODE"
echo "=================================================="
