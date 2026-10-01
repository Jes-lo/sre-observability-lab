#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(
  cd "$(dirname "${BASH_SOURCE[0]}")/.." >/dev/null 2>&1
  pwd
)"

TEMPO_IMAGE="grafana/tempo@sha256:0296560ac66f8a3600d7fb3014a52c189d4d9c3549ad6ff441bf2409855d68d5"
ALLOY_IMAGE="grafana/alloy@sha256:2aa2099af76c0098d4af7a4d6e48f86cb66dc1a000222ad927a1c67c6542d13f"

cd "$ROOT_DIR"

echo "===== REQUIRED FILES ====="

REQUIRED_FILES=(
  "app/src/telemetry.js"
  "app/test/telemetry.test.js"
  "tempo/config.yaml"
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
echo "===== TEMPO CONFIGURATION ====="

docker run \
  --rm \
  --user 10001:10001 \
  --read-only \
  --cap-drop ALL \
  --security-opt no-new-privileges:true \
  --mount \
    type=bind,source="$ROOT_DIR/tempo/config.yaml",target=/etc/tempo/config.yaml,readonly \
  "$TEMPO_IMAGE" \
  --config.file=/etc/tempo/config.yaml \
  --config.verify=true

echo "PASS: Tempo configuration valid"

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
echo "===== OPENTELEMETRY DEPENDENCIES ====="

python3 - <<'PY'
import json
from pathlib import Path

package = json.loads(
    Path(
        "app/package.json"
    ).read_text()
)

dependencies = package.get(
    "dependencies",
    {},
)

required = {
    "@opentelemetry/api",
    "@opentelemetry/auto-instrumentations-node",
    "@opentelemetry/exporter-trace-otlp-proto",
    "@opentelemetry/sdk-node",
}

missing = sorted(
    required
    - set(dependencies)
)

if missing:
    raise SystemExit(
        "FAIL: missing OpenTelemetry dependencies: "
        + repr(missing)
    )

for dependency in sorted(required):
    print(
        dependency
        + "="
        + str(
            dependencies[dependency]
        )
    )

print(
    "PASS: required OpenTelemetry dependencies declared"
)
PY

echo
echo "===== APPLICATION TELEMETRY DESIGN ====="

python3 - <<'PY'
from pathlib import Path

telemetry = Path(
    "app/src/telemetry.js"
).read_text()

server = Path(
    "app/src/server.js"
).read_text()

required_telemetry = [
    'DEFAULT_SERVICE_NAME = "sre-observability-lab-api"',
    'env.OTEL_TRACES_ENABLED === "true"',
    'OTEL_EXPORTER_OTLP_TRACES_ENDPOINT',
    'new OTLPTraceExporter',
    'new NodeSDK',
    'getNodeAutoInstrumentations',
    '"@opentelemetry/instrumentation-fs"',
    'enabled: false',
    '"@opentelemetry/instrumentation-http"',
    'ignoreIncomingRequestHook',
    'sdk.start()',
    'await activeSdk.shutdown()',
]

for value in required_telemetry:
    if value not in telemetry:
        raise SystemExit(
            "FAIL: telemetry implementation value missing: "
            + value
        )

for path in (
    "/healthz",
    "/readyz",
    "/metrics",
):
    quoted = '"' + path + '"'

    if quoted not in telemetry:
        raise SystemExit(
            "FAIL: ignored telemetry path missing: "
            + path
        )

if 'require("./telemetry")' not in server:
    raise SystemExit(
        "FAIL: server does not load telemetry module"
    )

if "startTelemetry();" not in server:
    raise SystemExit(
        "FAIL: server does not start telemetry"
    )

if "shutdownTelemetry()" not in server:
    raise SystemExit(
        "FAIL: graceful telemetry shutdown missing"
    )

telemetry_require = server.index(
    'require("./telemetry")'
)

app_require = server.index(
    'require("./app")'
)

if telemetry_require > app_require:
    raise SystemExit(
        "FAIL: telemetry must load before application instrumentation targets"
    )

print(
    "PASS: application tracing lifecycle and ignored paths valid"
)
PY

echo
echo "===== TEMPO LOCAL STORAGE AND PRIVACY ====="

python3 - <<'PY'
from pathlib import Path

text = Path(
    "tempo/config.yaml"
).read_text()

required = [
    "http_listen_port: 3200",
    "otlp:",
    "grpc:",
    'endpoint: "0.0.0.0:4317"',
    "backend: local",
    "path: /var/tempo/wal",
    "path: /var/tempo/blocks",
    "reporting_enabled: false",
]

for value in required:
    if value not in text:
        raise SystemExit(
            "FAIL: Tempo configuration value missing: "
            + value
        )

print(
    "PASS: Tempo local storage and reporting configuration valid"
)
PY

echo
echo "===== COMPOSE TRACING CONFIGURATION ====="

python3 - <<'PY'
from pathlib import Path
import re

text = Path(
    "compose.yaml"
).read_text()

required_global = [
    'OTEL_TRACES_ENABLED: "true"',
    "OTEL_SERVICE_NAME: sre-observability-lab-api",
    'OTEL_EXPORTER_OTLP_TRACES_ENDPOINT: "http://alloy:4318/v1/traces"',
    "OTEL_TRACES_SAMPLER: always_on",
    "OTEL_METRICS_EXPORTER: none",
    "OTEL_LOGS_EXPORTER: none",
    "grafana/tempo@sha256:0296560ac66f8a3600d7fb3014a52c189d4d9c3549ad6ff441bf2409855d68d5",
    "./tempo/config.yaml:/etc/tempo/config.yaml:ro",
    "tempo_data:/var/tempo",
    '"127.0.0.1:3200:3200"',
]

for value in required_global:
    if value not in text:
        raise SystemExit(
            "FAIL: Compose tracing value missing: "
            + value
        )

match = re.search(
    r"(?ms)^  tempo:\n(.*?)(?=^  [A-Za-z0-9_-]+:\n|\Z)",
    text,
)

if not match:
    raise SystemExit(
        "FAIL: Tempo Compose service block not found"
    )

tempo = match.group(1)

required_tempo = [
    'user: "10001:10001"',
    "read_only: true",
    "cap_drop:",
    "- ALL",
    "no-new-privileges:true",
    "mem_limit: 512m",
    "cpus: 0.5",
    "pids_limit: 150",
]

for value in required_tempo:
    if value not in tempo:
        raise SystemExit(
            "FAIL: Tempo hardening value missing: "
            + value
        )

restart_values = {
    line.strip()
    for line in tempo.splitlines()
    if line.strip().startswith("restart:")
}

allowed_restart_values = {
    "restart: no",
    'restart: "no"',
    "restart: 'no'",
}

print(
    "tempo_restart_values="
    + repr(
        sorted(restart_values)
    )
)

if restart_values != (
    restart_values
    & allowed_restart_values
):
    raise SystemExit(
        "FAIL: unexpected Tempo restart policy"
    )

if not restart_values:
    raise SystemExit(
        "FAIL: Tempo restart policy missing"
    )

print(
    "PASS: Compose tracing environment and Tempo hardening valid"
)
PY

echo
echo "===== ALLOY TRACE PIPELINE ====="

python3 - <<'PY'
from pathlib import Path

text = Path(
    "alloy/config.alloy"
).read_text()

required = [
    'otelcol.receiver.otlp "api_traces"',
    'endpoint = "0.0.0.0:4318"',
    'otelcol.processor.batch.api_traces.input',
    'otelcol.processor.batch "api_traces"',
    'otelcol.exporter.otlp.tempo.input',
    'otelcol.exporter.otlp "tempo"',
    'endpoint = "tempo:4317"',
    "insecure = true",
]

for value in required:
    if value not in text:
        raise SystemExit(
            "FAIL: Alloy tracing value missing: "
            + value
        )

if text.count(
    'otelcol.receiver.otlp "api_traces"'
) != 1:
    raise SystemExit(
        "FAIL: expected one OTLP trace receiver"
    )

if text.count(
    'otelcol.processor.batch "api_traces"'
) != 1:
    raise SystemExit(
        "FAIL: expected one trace batch processor"
    )

if text.count(
    'otelcol.exporter.otlp "tempo"'
) != 1:
    raise SystemExit(
        "FAIL: expected one Tempo OTLP exporter"
    )

print(
    "PASS: Alloy OTLP trace pipeline structure valid"
)
PY

echo
echo "===== LOG AND TRACE CORRELATION ====="

python3 - <<'PY'
from pathlib import Path

text = Path(
    "alloy/config.alloy"
).read_text()

process_start = text.index(
    'loki.process "api"'
)

process_end = text.index(
    'loki.write "local"',
    process_start,
)

process = text[
    process_start:
    process_end
]

structured_start = process.index(
    "stage.structured_metadata"
)

structured_end = process.index(
    "forward_to",
    structured_start,
)

structured = process[
    structured_start:
    structured_end
]

def assignment_exists(
    block,
    expected_key,
    expected_value,
):
    for raw_line in block.splitlines():
        line = raw_line.strip()

        if not line:
            continue

        line = line.rstrip(",")

        if "=" not in line:
            continue

        key, value = line.split(
            "=",
            1,
        )

        key = key.strip()
        value = value.strip()

        if (
            key == expected_key
            and value == expected_value
        ):
            return True

    return False


for field in (
    "trace_id",
    "span_id",
    "trace_flags",
):
    expected_value = (
        '"'
        + field
        + '"'
    )

    if not assignment_exists(
        process,
        field,
        expected_value,
    ):
        raise SystemExit(
            "FAIL: trace extraction missing: "
            + field
        )

    if not assignment_exists(
        structured,
        field,
        expected_value,
    ):
        raise SystemExit(
            "FAIL: trace structured metadata missing: "
            + field
        )

source_start = text.index(
    'loki.source.file "api"'
)

source_end = text.index(
    'loki.process "api"',
    source_start,
)

source = text[
    source_start:
    source_end
]

for field in (
    "trace_id",
    "span_id",
    "trace_flags",
):
    if (
        '"' + field + '"'
        in source
    ):
        raise SystemExit(
            "FAIL: high-cardinality trace field used as Loki source label: "
            + field
        )

print(
    "PASS: trace identifiers retained as structured metadata"
)
print(
    "PASS: trace identifiers kept out of indexed source labels"
)
PY

echo
echo "===== GRAFANA LOKI TO TEMPO CORRELATION ====="

python3 - <<'PY'
from pathlib import Path

text = Path(
    "grafana/provisioning/datasources/prometheus.yml"
).read_text()

required = [
    "- name: Loki",
    "uid: loki",
    "url: http://loki:3100",
    "derivedFields:",
    "- name: TraceID",
    "datasourceUid: tempo",
    "matcherRegex: '\"trace_id\":\"([0-9a-f]{32})\"'",
    "url: '$${__value.raw}'",
    "urlDisplayLabel: View Trace",
    "- name: Tempo",
    "uid: tempo",
    "type: tempo",
    "url: http://tempo:3200",
]

for value in required:
    if value not in text:
        raise SystemExit(
            "FAIL: Grafana log-to-trace value missing: "
            + value
        )

if text.count(
    "datasourceUid: tempo"
) != 1:
    raise SystemExit(
        "FAIL: expected exactly one Loki-to-Tempo datasource reference"
    )

print(
    "PASS: Grafana Loki -> Tempo correlation configuration valid"
)
PY

echo
echo "===== GRAFANA TEMPO TO LOKI CORRELATION ====="

python3 - <<'PY'
from pathlib import Path

text = Path(
    "grafana/provisioning/datasources/prometheus.yml"
).read_text()

required = [
    "tracesToLogsV2:",
    "datasourceUid: loki",
    "spanStartTimeShift: '-5m'",
    "spanEndTimeShift: '5m'",
    "filterByTraceID: false",
    "filterBySpanID: false",
    "customQuery: true",
    "query: '{service=\"sre-api\"} | trace_id=`$${__trace.traceId}`'",
]

for value in required:
    if value not in text:
        raise SystemExit(
            "FAIL: Grafana trace-to-log value missing: "
            + value
        )

print(
    "PASS: Grafana Tempo -> Loki correlation configuration valid"
)
PY

echo
echo "===== NO DOCKER SOCKET ACCESS ====="

SOCKET_MATCHES="$(
  grep -RIn \
    '/var/run/docker.sock' \
    compose.yaml \
    alloy \
    tempo \
    || true
)"

if [[ -n "$SOCKET_MATCHES" ]]; then
  echo "FAIL: Docker socket reference detected"
  printf '%s\n' "$SOCKET_MATCHES"
  exit 1
fi

echo "PASS: tracing stack does not use Docker socket"

echo
echo "===== VALIDATION COMPLETE ====="

echo "PASS: distributed tracing configuration validation succeeded"
