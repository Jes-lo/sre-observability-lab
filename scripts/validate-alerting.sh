#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(
  cd "$(
    dirname "${BASH_SOURCE[0]}"
  )/.."
  pwd
)"

cd "$ROOT_DIR"

PROM_IMAGE="prom/prometheus@sha256:6976aa8a60fec930796ce5772b8d12da7a318a5daa8d40d69c5c7819a05eeed7"
ALERTMANAGER_IMAGE="prom/alertmanager@sha256:e9733bafb1bdef9b00e25a21f8f99dc26a22224bf16641ad754d1649f4c3357a"

echo "===== REQUIRED FILES ====="

for FILE in \
  observability/alertmanager/alertmanager.yml \
  observability/prometheus/prometheus.yml \
  observability/prometheus/alerting-recording-rules.yml \
  observability/prometheus/alerting-rules.yml \
  observability/prometheus/alerting-rules.test.yml \
  docs/alerting-and-alertmanager.md
do
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
echo "===== ALERTMANAGER CONFIGURATION ====="

docker run \
  --rm \
  --entrypoint /bin/amtool \
  --volume \
    "$ROOT_DIR/observability/alertmanager:/etc/alertmanager:ro" \
  "$ALERTMANAGER_IMAGE" \
  check-config \
  /etc/alertmanager/alertmanager.yml

echo "PASS: Alertmanager configuration valid"

echo
echo "===== PROMETHEUS CONFIGURATION ====="

docker run \
  --rm \
  --entrypoint /bin/promtool \
  --volume \
    "$ROOT_DIR/observability/prometheus:/etc/prometheus:ro" \
  "$PROM_IMAGE" \
  check config \
  /etc/prometheus/prometheus.yml

echo "PASS: Prometheus alerting configuration valid"

echo
echo "===== ALERTING RULE FILES ====="

for RULE_FILE in \
  alerting-recording-rules.yml \
  alerting-rules.yml
do
  docker run \
    --rm \
    --entrypoint /bin/promtool \
    --volume \
      "$ROOT_DIR/observability/prometheus:/etc/prometheus:ro" \
    "$PROM_IMAGE" \
    check rules \
    "/etc/prometheus/$RULE_FILE"
done

echo "PASS: alerting rule files valid"

echo
echo "===== DETERMINISTIC RULE TESTS ====="

docker run \
  --rm \
  --entrypoint /bin/promtool \
  --volume \
    "$ROOT_DIR/observability/prometheus:/etc/prometheus:ro" \
  "$PROM_IMAGE" \
  test rules \
  /etc/prometheus/alerting-rules.test.yml

echo "PASS: deterministic alerting rule tests"

echo
echo "===== ALERTING SEMANTICS ====="

python3 - <<'PY'
from pathlib import Path
import yaml

recording = yaml.safe_load(
    Path(
        "observability/prometheus/alerting-recording-rules.yml"
    ).read_text()
)

records = [
    rule["record"]
    for group in recording["groups"]
    for rule in group["rules"]
]

expected_records = {
    f"sre_api:slo_{sli}_{kind}:{prefix}{window}"
    for sli in (
        "availability",
        "latency",
    )
    for kind, prefix in (
        ("bad_ratio", "rate"),
        ("burn_rate", "ratio"),
    )
    for window in (
        "1m",
        "5m",
        "15m",
    )
}

if len(records) != 12:
    raise SystemExit(
        f"FAIL: expected 12 recording rules; "
        f"found {len(records)}"
    )

if set(records) != expected_records:
    raise SystemExit(
        "FAIL: alerting recording-rule set mismatch"
    )

alerts = yaml.safe_load(
    Path(
        "observability/prometheus/alerting-rules.yml"
    ).read_text()
)

alert_rules = [
    rule
    for group in alerts["groups"]
    for rule in group["rules"]
]

expected_alerts = {
    "SreApiHigh5xxRatio",
    "SreApiHighLatencyRatio",
    "SreApiAvailabilityBurnRateFast",
    "SreApiAvailabilityBurnRateSlow",
    "SreApiLatencyBurnRateFast",
    "SreApiLatencyBurnRateSlow",
}

if len(alert_rules) != 6:
    raise SystemExit(
        f"FAIL: expected six alert rules; "
        f"found {len(alert_rules)}"
    )

if {
    rule["alert"]
    for rule in alert_rules
} != expected_alerts:
    raise SystemExit(
        "FAIL: alert-rule set mismatch"
    )

print("alerting_recording_rules=12")
print("alert_rules=6")
print("PASS: alerting rule semantics valid")
PY

echo
echo "===== ALERTMANAGER ROUTING ====="

python3 - <<'PY'
from pathlib import Path
import yaml

config = yaml.safe_load(
    Path(
        "observability/alertmanager/alertmanager.yml"
    ).read_text()
)

receivers = config.get(
    "receivers",
    [],
)

actual = {
    receiver.get("name")
    for receiver in receivers
}

expected = {
    "local-default",
    "local-critical",
    "local-warning",
}

if actual != expected:
    raise SystemExit(
        "FAIL: unexpected receiver set"
    )

for receiver in receivers:
    if set(receiver) != {"name"}:
        raise SystemExit(
            "FAIL: external receiver integration detected"
        )

routes = config[
    "route"
].get(
    "routes",
    [],
)

actual_routes = {
    (
        route.get("receiver"),
        tuple(
            route.get(
                "matchers",
                [],
            )
        ),
    )
    for route in routes
}

expected_routes = {
    (
        "local-critical",
        ('severity="critical"',),
    ),
    (
        "local-warning",
        ('severity="warning"',),
    ),
}

if actual_routes != expected_routes:
    raise SystemExit(
        "FAIL: severity routing mismatch"
    )

print("receivers=3")
print("routes=2")
print("PASS: local severity routing valid")
PY

echo
echo "===== COMPOSE HARDENING ====="

python3 - <<'PY'
from pathlib import Path
import yaml

compose = yaml.safe_load(
    Path("compose.yaml").read_text()
)

service = compose[
    "services"
].get(
    "alertmanager"
)

if not service:
    raise SystemExit(
        "FAIL: Alertmanager service missing"
    )

expected_image = (
    "prom/alertmanager@sha256:"
    "e9733bafb1bdef9b00e25a21f8f99dc"
    "26a22224bf16641ad754d1649f4c3357a"
)

checks = [
    (
        service.get("image")
        == expected_image,
        "Alertmanager image mismatch",
    ),
    (
        service.get("read_only") is True,
        "root filesystem not read-only",
    ),
    (
        service.get("cap_drop") == ["ALL"],
        "capabilities not dropped",
    ),
    (
        "no-new-privileges:true"
        in service.get(
            "security_opt",
            [],
        ),
        "no-new-privileges missing",
    ),
    (
        "127.0.0.1:9093:9093"
        in service.get(
            "ports",
            [],
        ),
        "localhost-only exposure missing",
    ),
    (
        "--cluster.listen-address="
        in service.get(
            "command",
            [],
        ),
        "cluster listener not disabled",
    ),
]

for passed, message in checks:
    if not passed:
        raise SystemExit(
            "FAIL: " + message
        )

print(
    "PASS: Alertmanager Compose hardening valid"
)
PY

echo
echo "===== PROMETHEUS TO ALERTMANAGER WIRING ====="

python3 - <<'PY'
from pathlib import Path
import yaml

config = yaml.safe_load(
    Path(
        "observability/prometheus/prometheus.yml"
    ).read_text()
)

expected_rules = {
    "/etc/prometheus/recording-rules.yml",
    "/etc/prometheus/alerting-recording-rules.yml",
    "/etc/prometheus/alerting-rules.yml",
}

if set(
    config.get(
        "rule_files",
        [],
    )
) != expected_rules:
    raise SystemExit(
        "FAIL: Prometheus rule_files mismatch"
    )

alertmanagers = (
    config.get(
        "alerting",
        {},
    )
    .get(
        "alertmanagers",
        [],
    )
)

if len(alertmanagers) != 1:
    raise SystemExit(
        "FAIL: expected one Alertmanager config"
    )

targets = (
    alertmanagers[0]
    .get(
        "static_configs",
        [{}],
    )[0]
    .get(
        "targets",
        [],
    )
)

if targets != ["alertmanager:9093"]:
    raise SystemExit(
        "FAIL: Prometheus Alertmanager target mismatch"
    )

print(
    "PASS: Prometheus alert delivery wiring valid"
)
PY

echo
echo "===== TEST COVERAGE ====="

python3 - <<'PY'
from pathlib import Path
import yaml

data = yaml.safe_load(
    Path(
        "observability/prometheus/alerting-rules.test.yml"
    ).read_text()
)

tests = data.get(
    "tests",
    [],
)

if len(tests) != 2:
    raise SystemExit(
        "FAIL: expected two test scenarios"
    )

names = {
    test.get("name")
    for test in tests
}

expected_names = {
    "no eligible traffic produces no alerting ratios",
    "twelve percent bad events produce twelve-x burn rates",
}

if names != expected_names:
    raise SystemExit(
        "FAIL: deterministic scenario set mismatch"
    )

high = next(
    test
    for test in tests
    if test.get("name")
    ==
    "twelve percent bad events produce twelve-x burn rates"
)

if len(
    high.get(
        "promql_expr_test",
        [],
    )
) != 12:
    raise SystemExit(
        "FAIL: expected 12 PromQL assertions"
    )

if len(
    high.get(
        "alert_rule_test",
        [],
    )
) != 6:
    raise SystemExit(
        "FAIL: expected six alert assertions"
    )

print("scenarios=2")
print("promql_assertions=12")
print("alert_assertions=6")
print("PASS: deterministic test coverage valid")
PY

echo
echo "===== ALERTING DOCUMENTATION ====="

python3 - <<'PYDOC'
from pathlib import Path

text = Path(
    "docs/alerting-and-alertmanager.md"
).read_text()

required = [
    "SreApiHigh5xxRatio",
    "SreApiHighLatencyRatio",
    "SreApiAvailabilityBurnRateFast",
    "SreApiAvailabilityBurnRateSlow",
    "SreApiLatencyBurnRateFast",
    "SreApiLatencyBurnRateSlow",
    "local-critical",
    "local-warning",
    "10x",
    "2x",
    "promtool test rules",
    "No external notification service is configured.",
]

for value in required:
    if value not in text:
        raise SystemExit(
            "FAIL: alerting documentation missing: "
            + value
        )

print(
    "PASS: alerting documentation contains "
    "required design decisions"
)
PYDOC

echo
echo "===== VALIDATION COMPLETE ====="

echo "PASS: alerting configuration validation succeeded"
