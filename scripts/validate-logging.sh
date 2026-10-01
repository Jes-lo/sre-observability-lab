#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1
  pwd
)"

LOKI_IMAGE="grafana/loki@sha256:1107dd5274e0ada47e42472b7a7e71f3b2a2fe878878108f3e2f9e51528f0193"
ALLOY_IMAGE="grafana/alloy@sha256:2aa2099af76c0098d4af7a4d6e48f86cb66dc1a000222ad927a1c67c6542d13f"

cd "$ROOT_DIR"

echo "===== REQUIRED FILES ====="

REQUIRED_FILES=(
  "loki/config.yaml"
  "alloy/config.alloy"
  "compose.yaml"
  "grafana/provisioning/datasources/prometheus.yml"
)

for FILE in "${REQUIRED_FILES[@]}"; do
  if [[ ! -f "$FILE" ]]; then
    echo "FAIL: missing required file: $FILE"
    exit 1
  fi

  echo "PASS: $FILE"
done

echo
echo "===== DOCKER COMPOSE ====="

docker compose config --quiet

echo "PASS: Docker Compose configuration valid"

echo
echo "===== LOKI CONFIGURATION ====="

docker run \
  --rm \
  --user 10001:10001 \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --mount \
    type=bind,source="$ROOT_DIR/loki/config.yaml",target=/etc/loki/config.yaml,readonly \
  "$LOKI_IMAGE" \
  -config.file=/etc/loki/config.yaml \
  -verify-config

echo "PASS: Loki configuration valid"

echo
echo "===== ALLOY CONFIGURATION ====="

docker run \
  --rm \
  --user 473:473 \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --mount \
    type=bind,source="$ROOT_DIR/alloy/config.alloy",target=/etc/alloy/config.alloy,readonly \
  --entrypoint /bin/alloy \
  "$ALLOY_IMAGE" \
  validate \
  /etc/alloy/config.alloy

echo "PASS: Alloy configuration valid"

echo
echo "===== NO DOCKER SOCKET ACCESS ====="

SOCKET_MATCHES="$(
  grep -RIn \
    '/var/run/docker.sock' \
    compose.yaml \
    alloy \
    loki \
    || true
)"

if [[ -n "$SOCKET_MATCHES" ]]; then
  echo "FAIL: Docker socket reference detected"
  printf '%s\n' "$SOCKET_MATCHES"
  exit 1
fi

echo "PASS: logging stack does not use Docker socket"

echo
echo "===== PINNED IMAGES ====="

grep -Fq \
  "grafana/loki@sha256:1107dd5274e0ada47e42472b7a7e71f3b2a2fe878878108f3e2f9e51528f0193" \
  compose.yaml || {
    echo "FAIL: pinned Loki image missing"
    exit 1
  }

grep -Fq \
  "grafana/alloy@sha256:2aa2099af76c0098d4af7a4d6e48f86cb66dc1a000222ad927a1c67c6542d13f" \
  compose.yaml || {
    echo "FAIL: pinned Alloy image missing"
    exit 1
  }

echo "PASS: Loki and Alloy images pinned by digest"

echo
echo "===== ALLOY PRIVACY ====="

grep -Fq \
  -- '--disable-reporting' \
  compose.yaml || {
    echo "FAIL: Alloy anonymous usage reporting is not disabled"
    exit 1
  }

grep -Fq \
  -- '--storage.path=/var/lib/alloy/data' \
  compose.yaml || {
    echo "FAIL: Alloy persistent storage path missing"
    exit 1
  }

DISABLE_REPORTING_COUNT="$(
  grep \
    --fixed-strings \
    --count \
    -- '--disable-reporting' \
    compose.yaml
)"

if [[ "$DISABLE_REPORTING_COUNT" -ne 1 ]]; then
  echo "FAIL: expected exactly one Alloy --disable-reporting flag"
  exit 1
fi

echo "PASS: Alloy privacy settings explicit"

echo
echo "===== ALLOY PIPELINE STRUCTURE ====="

python3 - <<'PY'
from pathlib import Path

text = Path("alloy/config.alloy").read_text()

required = [
    'loki.source.file "api"',
    '"/var/log/sre-api/api.log"',
    '"service"     = "sre-api"',
    '"environment" = "local"',
    'loki.process "api"',
    'stage.json',
    'timestamp        = "time"',
    'stage.timestamp',
    'format            = "UnixMs"',
    'stage.structured_metadata',
    'loki.write "local"',
    'url = "http://loki:3100/loki/api/v1/push"',
]

for value in required:
    if value not in text:
        raise SystemExit(
            f"FAIL: Alloy pipeline value missing: {value}"
        )

if text.count('loki.source.file "api"') != 1:
    raise SystemExit(
        "FAIL: expected one API file source"
    )

if text.count("stage.timestamp") != 1:
    raise SystemExit(
        "FAIL: expected one timestamp stage"
    )

if text.count('loki.write "local"') != 1:
    raise SystemExit(
        "FAIL: expected one Loki writer"
    )

print("PASS: Alloy logging pipeline structure valid")
PY

echo
echo "===== LABEL CARDINALITY GUARDRAILS ====="

python3 - <<'PY'
from pathlib import Path

text = Path("alloy/config.alloy").read_text()

source_start = text.index('loki.source.file "api"')
source_end = text.index(
    'loki.process "api"',
    source_start,
)

source = text[source_start:source_end]

allowed_labels = {
    "service",
    "environment",
}

for prohibited in (
    "request_id",
    "url",
    "method",
    "status_code",
    "response_time_ms",
):
    if f'"{prohibited}"' in source:
        raise SystemExit(
            "FAIL: high-cardinality field used as source label: "
            + prohibited
        )

for label in allowed_labels:
    if f'"{label}"' not in source:
        raise SystemExit(
            "FAIL: expected low-cardinality label missing: "
            + label
        )

structured_start = text.index(
    "stage.structured_metadata"
)

structured_end = text.index(
    "forward_to",
    structured_start,
)

structured = text[
    structured_start:structured_end
]

required_metadata = {
    "level",
    "event",
    "request_id",
    "method",
    "url",
    "status_code",
    "response_time_ms",
}

for field in required_metadata:
    if f'"{field}"' not in structured:
        raise SystemExit(
            "FAIL: structured metadata field missing: "
            + field
        )

print(
    "PASS: high-cardinality data kept out of Loki labels"
)
print(
    "PASS: correlation fields retained as structured metadata"
)
PY

echo
echo "===== LOKI STORAGE CONFIGURATION ====="

python3 - <<'PY'
from pathlib import Path

text = Path("loki/config.yaml").read_text()

required = [
    "auth_enabled: false",
    "http_listen_port: 3100",
    "path_prefix: /loki",
    "replication_factor: 1",
    "store: inmemory",
    "store: tsdb",
    "object_store: filesystem",
    "schema: v13",
    "directory: /loki/chunks",
    "allow_structured_metadata: true",
    "reporting_enabled: false",
]

for value in required:
    if value not in text:
        raise SystemExit(
            f"FAIL: Loki configuration value missing: {value}"
        )

print("PASS: Loki local storage configuration valid")
print("PASS: Loki analytics reporting disabled")
PY

echo
echo "===== COMPOSE LOGGING HARDENING ====="

COMPOSE_CONFIG="$(
  docker compose config
)"

LOKI_BLOCK="$(
  printf '%s\n' "$COMPOSE_CONFIG" \
    | sed -n \
      '/^  loki:/,/^  [a-zA-Z0-9_-]\+:/p'
)"

ALLOY_BLOCK="$(
  printf '%s\n' "$COMPOSE_CONFIG" \
    | sed -n \
      '/^  alloy:/,/^  [a-zA-Z0-9_-]\+:/p'
)"

LOKI_REQUIRED=(
  'user: 10001:10001'
  'read_only: true'
  'mem_limit: "268435456"'
  'cpus: 0.5'
  'pids_limit: 150'
  'target: /etc/loki/config.yaml'
  'read_only: true'
  'target: /loki'
)

for VALUE in "${LOKI_REQUIRED[@]}"; do
  if ! grep -Fq "$VALUE" <<< "$LOKI_BLOCK"; then
    echo "FAIL: Loki Compose hardening value missing: $VALUE"
    exit 1
  fi
done

grep -Fq \
  'host_ip: 127.0.0.1' \
  <<< "$LOKI_BLOCK" || {
    echo "FAIL: Loki port is not loopback-only"
    exit 1
  }

grep -Fq \
  'no-new-privileges:true' \
  <<< "$LOKI_BLOCK" || {
    echo "FAIL: Loki no-new-privileges missing"
    exit 1
  }

grep -Fq \
  -- '- ALL' \
  <<< "$LOKI_BLOCK" || {
    echo "FAIL: Loki cap_drop ALL missing"
    exit 1
  }

echo "PASS: Loki Compose hardening valid"

ALLOY_REQUIRED=(
  'user: 473:473'
  'read_only: true'
  'mem_limit: "268435456"'
  'cpus: 0.5'
  'pids_limit: 150'
  'target: /etc/alloy/config.alloy'
  'target: /var/log/sre-api'
  'target: /var/lib/alloy/data'
)

for VALUE in "${ALLOY_REQUIRED[@]}"; do
  if ! grep -Fq "$VALUE" <<< "$ALLOY_BLOCK"; then
    echo "FAIL: Alloy Compose hardening value missing: $VALUE"
    exit 1
  fi
done

grep -Fq \
  'no-new-privileges:true' \
  <<< "$ALLOY_BLOCK" || {
    echo "FAIL: Alloy no-new-privileges missing"
    exit 1
  }

grep -Fq \
  -- '- ALL' \
  <<< "$ALLOY_BLOCK" || {
    echo "FAIL: Alloy cap_drop ALL missing"
    exit 1
  }

if grep -Eq \
  'published:|host_ip:' \
  <<< "$ALLOY_BLOCK"; then
  echo "FAIL: Alloy unexpectedly publishes a host port"
  exit 1
fi

echo "PASS: Alloy Compose hardening valid"

echo
echo "===== LOGGING MOUNT ACCESS ====="

python3 - <<'PYINNER'
from pathlib import Path

text = Path("compose.yaml").read_text()

required = [
    "./loki/config.yaml:/etc/loki/config.yaml:ro",
    "loki_data:/loki",
    "./alloy/config.alloy:/etc/alloy/config.alloy:ro",
    "api_logs:/var/log/sre-api:ro",
    "alloy_data:/var/lib/alloy/data",
]

for value in required:
    if value not in text:
        raise SystemExit(
            f"FAIL: logging mount missing: {value}"
        )

if "loki_data:/loki:ro" in text:
    raise SystemExit(
        "FAIL: Loki data volume must be writable"
    )

if "alloy_data:/var/lib/alloy/data:ro" in text:
    raise SystemExit(
        "FAIL: Alloy state volume must be writable"
    )

print("PASS: Loki config mount is read-only")
print("PASS: Loki data volume is writable")
print("PASS: Alloy config mount is read-only")
print("PASS: Alloy API log access is read-only")
print("PASS: Alloy state volume is writable")
PYINNER

echo
echo "===== GRAFANA LOKI DATASOURCE ====="

python3 - <<'PY'
from pathlib import Path

text = Path(
    "grafana/provisioning/datasources/prometheus.yml"
).read_text()

required = [
    "prune: true",
    "name: Prometheus",
    "uid: prometheus",
    "url: http://prometheus:9090",
    "name: Loki",
    "uid: loki",
    "type: loki",
    "url: http://loki:3100",
]

for value in required:
    if value not in text:
        raise SystemExit(
            f"FAIL: datasource provisioning value missing: {value}"
        )

if text.count("uid: prometheus") != 1:
    raise SystemExit(
        "FAIL: expected one Prometheus datasource UID"
    )

if text.count("uid: loki") != 1:
    raise SystemExit(
        "FAIL: expected one Loki datasource UID"
    )

print("PASS: Grafana Loki datasource provisioning valid")
PY

echo
echo "===== REQUIRED VOLUMES ====="

VOLUMES="$(
  docker compose config --volumes
)"

for VOLUME in \
  api_logs \
  loki_data \
  alloy_data
do
  if ! grep -Fxq "$VOLUME" <<< "$VOLUMES"; then
    echo "FAIL: required Compose volume missing: $VOLUME"
    exit 1
  fi

  echo "PASS: volume $VOLUME"
done

echo
echo "===== VALIDATION COMPLETE ====="
echo "PASS: centralized logging validation succeeded"
