#!/usr/bin/env bash

set -euo pipefail

K6_IMAGE="grafana/k6@sha256:9c2dee7f8ed74d317e4027c06a10f169b625638189de8d4555d0b3486a5aeb34"

echo "===== REQUIRED FILES ====="

for FILE in \
  compose.yaml \
  load/k6/scenarios.js \
  scripts/validate-load-runtime.sh \
  docs/controlled-load-and-failures.md
do
  if [[ ! -f "$FILE" ]]; then
    echo "FAIL: missing $FILE"
    exit 1
  fi

  echo "PASS: $FILE"
done

echo
echo "===== DEFAULT COMPOSE CONFIGURATION ====="

docker compose \
  config \
  --quiet

echo "PASS: default Docker Compose configuration valid"

echo
echo "===== LOAD-TEST PROFILE CONFIGURATION ====="

docker compose \
  --profile load-test \
  config \
  --quiet

echo "PASS: load-test profile parses successfully"

echo
echo "===== LOAD-TEST COMPOSE SEMANTICS ====="

COMPOSE_JSON="$(mktemp)"

cleanup_compose_json() {
  rm -f "$COMPOSE_JSON"
}

trap cleanup_compose_json EXIT

docker compose \
  --profile load-test \
  config \
  --format json \
  > "$COMPOSE_JSON"

python3 - "$K6_IMAGE" "$COMPOSE_JSON" <<'PY'
import json
import sys

expected_k6_image = sys.argv[1]
compose_path = sys.argv[2]

with open(
    compose_path,
    encoding="utf-8",
) as handle:
    compose = json.load(handle)

services = compose.get(
    "services",
    {},
)

for name in (
    "api",
    "api-load-target",
    "k6",
):
    if name not in services:
        raise SystemExit(
            f"FAIL: missing Compose service: {name}"
        )

primary = services["api"]
target = services["api-load-target"]
k6 = services["k6"]

primary_env = primary.get(
    "environment",
    {},
)

target_env = target.get(
    "environment",
    {},
)

k6_env = k6.get(
    "environment",
    {},
)

if str(
    primary_env.get(
        "LAB_FAULTS_ENABLED",
        "",
    )
).lower() != "false":
    raise SystemExit(
        "FAIL: primary API faults must remain disabled"
    )

if str(
    target_env.get(
        "LAB_FAULTS_ENABLED",
        "",
    )
).lower() != "true":
    raise SystemExit(
        "FAIL: load target faults must be enabled"
    )

if (
    target_env.get("LOG_FILE_PATH")
    != "/tmp/sre-api.log"
):
    raise SystemExit(
        "FAIL: load target must use ephemeral log path"
    )

if str(
    target_env.get(
        "OTEL_TRACES_ENABLED",
        "",
    )
).lower() != "false":
    raise SystemExit(
        "FAIL: load target tracing must be disabled"
    )

if k6.get("image") != expected_k6_image:
    raise SystemExit(
        "FAIL: k6 image digest mismatch"
    )

if str(k6.get("user")) != "65534:65534":
    raise SystemExit(
        "FAIL: k6 non-root UID/GID mismatch"
    )

if str(
    k6_env.get(
        "K6_NO_USAGE_REPORT",
        "",
    )
).lower() != "true":
    raise SystemExit(
        "FAIL: k6 usage reporting is not disabled"
    )

if (
    k6_env.get("K6_TARGET_URL")
    != "http://api-load-target:3000"
):
    raise SystemExit(
        "FAIL: k6 target URL mismatch"
    )

for name, service in (
    (
        "api-load-target",
        target,
    ),
    (
        "k6",
        k6,
    ),
):
    if service.get("read_only") is not True:
        raise SystemExit(
            f"FAIL: {name} filesystem is not read-only"
        )

    if service.get("cap_drop") != ["ALL"]:
        raise SystemExit(
            f"FAIL: {name} capabilities are not dropped"
        )

    if (
        "no-new-privileges:true"
        not in service.get(
            "security_opt",
            [],
        )
    ):
        raise SystemExit(
            f"FAIL: {name} no-new-privileges missing"
        )

    if service.get("ports"):
        raise SystemExit(
            f"FAIL: {name} must not publish host ports"
        )

    networks = service.get(
        "networks",
        {},
    )

    if set(networks) != {"load_test"}:
        raise SystemExit(
            f"FAIL: {name} is not isolated on load_test"
        )

networks = compose.get(
    "networks",
    {},
)

load_network = networks.get(
    "load_test",
    {},
)

if load_network.get("internal") is not True:
    raise SystemExit(
        "FAIL: load_test network must be internal"
    )

depends = k6.get(
    "depends_on",
    {},
)

if "api-load-target" not in depends:
    raise SystemExit(
        "FAIL: k6 does not depend on api-load-target"
    )

print("primary_faults_enabled=false")
print("load_target_faults_enabled=true")
print("load_test_network_internal=true")
print("k6_non_root=true")
print("k6_host_ports=0")
print("load_target_host_ports=0")
print(
    "PASS: load-test Compose semantics valid"
)
PY

echo
echo "===== K6 SCENARIO SEMANTICS ====="

python3 - <<'PY'
from pathlib import Path

text = Path(
    "load/k6/scenarios.js"
).read_text()

required = [
    'const scenarioName = __ENV.K6_SCENARIO || "healthy";',
    '"http://api-load-target:3000"',
    "healthy:",
    "latency:",
    "http500:",
    'executor: "constant-vus"',
    'duration: "10s"',
    "/api/work",
    "/api/slow?ms=500",
    "/api/error",
    "res.status === 200",
    "res.status === 500",
    "res.timings.duration >= 450",
    "res.timings.duration < 2000",
    '"rate>0.99"',
]

for value in required:
    if value not in text:
        raise SystemExit(
            "FAIL: missing k6 scenario semantic: "
            + value
        )

if "https://" in text:
    raise SystemExit(
        "FAIL: external HTTPS target detected"
    )

if (
    "http://"
    in text.replace(
        "http://api-load-target:3000",
        "",
    )
):
    raise SystemExit(
        "FAIL: unexpected HTTP target detected"
    )

print("scenarios=3")
print("healthy_vus=2")
print("latency_vus=2")
print("http500_vus=2")
print("duration=10s")
print(
    "PASS: k6 scenario semantics valid"
)
PY

echo
echo "===== K6 IMAGE ====="

VERSION="$(
  docker run \
    --rm \
    --network none \
    --user 65534:65534 \
    --read-only \
    --tmpfs /tmp:rw,noexec,nosuid,size=16m,mode=1777 \
    --cap-drop ALL \
    --security-opt no-new-privileges:true \
    --env K6_NO_USAGE_REPORT=true \
    "$K6_IMAGE" \
    version
)"

printf '%s\n' \
  "$VERSION"

if ! grep -Eq \
  '(^|[[:space:]])v?2\.3\.0([[:space:]]|$|\()' \
  <<< "$VERSION"
then
  echo "FAIL: unexpected k6 version"
  exit 1
fi

echo "PASS: digest-pinned k6 image valid"

echo
echo "===== NO DOCKER SOCKET ====="

if grep \
  -RIn \
  '/var/run/docker.sock' \
  compose.yaml \
  load/k6 \
  >/tmp/sre-load-docker-socket-scan
then
  cat /tmp/sre-load-docker-socket-scan
  rm -f /tmp/sre-load-docker-socket-scan

  echo "FAIL: Docker socket reference detected"
  exit 1
fi

rm -f \
  /tmp/sre-load-docker-socket-scan

echo "PASS: load-test stack has no Docker socket access"

echo
echo "===== CONTROLLED-LOAD DOCUMENTATION ====="

python3 - <<'PYDOC'
from pathlib import Path

text = Path(
    "docs/controlled-load-and-failures.md"
).read_text()

required = [
    "Feature #8",
    "api-load-target",
    "K6_NO_USAGE_REPORT=true",
    "healthy",
    "latency",
    "http500",
    "internal Docker network",
    "not a production capacity benchmark",
    "scripts/validate-load-runtime.sh",
    "Load Scenario Validation",
]

for value in required:
    if value not in text:
        raise SystemExit(
            "FAIL: controlled-load documentation missing: "
            + value
        )

print(
    "PASS: controlled-load documentation valid"
)
PYDOC

echo
echo "===== VALIDATION COMPLETE ====="

echo "PASS: controlled-load configuration validation succeeded"
