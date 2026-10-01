#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(
  cd "$(
    dirname "${BASH_SOURCE[0]}"
  )/.."
  pwd
)"

cd "$ROOT_DIR"

echo "===== REQUIRED FILES ====="

for FILE in \
  observability/prometheus/prometheus.yml \
  observability/prometheus/recording-rules.yml \
  grafana/dashboards/sre-slo-overview.json \
  grafana/provisioning/datasources/prometheus.yml \
  grafana/provisioning/dashboards/dashboards.yml \
  docs/slo-error-budgets.md
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
echo "===== PROMETHEUS CONFIGURATION ====="

bash scripts/validate-prometheus.sh

echo
echo "===== SLO RECORDING RULE SEMANTICS ====="

python3 - <<'PY'
from pathlib import Path
import re

path = Path(
    "observability/prometheus/recording-rules.yml"
)

text = path.read_text()

records = re.findall(
    r"^\s*-\s+record:\s+(\S+)\s*$",
    text,
    flags=re.MULTILINE,
)

actual = [
    record
    for record in records
    if record.startswith(
        "sre_api:slo_"
    )
]

expected = [
    "sre_api:slo_requests:increase30m",
    "sre_api:slo_5xx:increase30m",
    "sre_api:slo_availability:ratio30m",
    "sre_api:slo_latency_good:increase30m",
    "sre_api:slo_latency_total:increase30m",
    "sre_api:slo_latency:ratio30m",
    "sre_api:slo_availability_target:ratio",
    "sre_api:slo_latency_target:ratio",
    "sre_api:slo_availability_error_budget:ratio",
    "sre_api:slo_latency_error_budget:ratio",
    "sre_api:slo_availability_budget_consumed:ratio30m",
    "sre_api:slo_latency_budget_consumed:ratio30m",
    "sre_api:slo_availability_budget_remaining:ratio30m",
    "sre_api:slo_latency_budget_remaining:ratio30m",
]

if actual != expected:
    print(
        "actual="
        + repr(actual)
    )
    raise SystemExit(
        "FAIL: unexpected SLO recording-rule set/order"
    )

checks = {
    "eligible route scope":
        'route=~"/api/(work|slow|error)"',
    "latency threshold":
        'le="0.25"',
    "availability target":
        "sre_api:slo_availability_target:ratio",
    "latency target":
        "sre_api:slo_latency_target:ratio",
    "availability no-traffic guard":
        "sre_api:slo_requests:increase30m > 0",
    "latency no-traffic guard":
        "sre_api:slo_latency_total:increase30m > 0",
}

for label, value in checks.items():
    if value not in text:
        raise SystemExit(
            f"FAIL: missing {label}: {value}"
        )

if text.count(
    'status_code!~"5.."'
) != 2:
    raise SystemExit(
        "FAIL: latency rules must exclude 5xx "
        "in exactly two expressions"
    )

if text.count(
    "vector(0.99)"
) != 2:
    raise SystemExit(
        "FAIL: expected exactly two 99% SLO targets"
    )

if "alert:" in text:
    raise SystemExit(
        "FAIL: alerting rules detected in Feature #6"
    )

print(
    f"slo_rule_count={len(actual)}"
)

print(
    "PASS: SLO recording-rule semantics valid"
)
PY

echo
echo "===== GRAFANA SLO DASHBOARD ====="

python3 - <<'PY'
from pathlib import Path
import json

path = Path(
    "grafana/dashboards/sre-slo-overview.json"
)

dashboard = json.loads(
    path.read_text()
)

if (
    dashboard.get("uid")
    != "sre-slo-overview"
):
    raise SystemExit(
        "FAIL: unexpected SLO dashboard UID"
    )

if (
    dashboard.get("title")
    != "SRE Lab - SLO & Error Budget"
):
    raise SystemExit(
        "FAIL: unexpected SLO dashboard title"
    )

if dashboard.get(
    "time",
    {},
).get("from") != "now-30m":
    raise SystemExit(
        "FAIL: SLO dashboard window must start at now-30m"
    )

panels = dashboard.get(
    "panels",
    [],
)

if len(panels) != 8:
    raise SystemExit(
        f"FAIL: expected 8 SLO panels; found {len(panels)}"
    )

expected_queries = {
    "sre_api:slo_availability:ratio30m",
    "sre_api:slo_latency:ratio30m",
    "sre_api:slo_availability_target:ratio",
    "sre_api:slo_latency_target:ratio",
    "sre_api:slo_availability_budget_consumed:ratio30m",
    "sre_api:slo_latency_budget_consumed:ratio30m",
    "sre_api:slo_availability_budget_remaining:ratio30m",
    "sre_api:slo_latency_budget_remaining:ratio30m",
}

actual_queries = set()

for panel in panels:
    if panel.get("type") != "stat":
        raise SystemExit(
            "FAIL: all SLO dashboard panels must be stat panels"
        )

    datasource = panel.get(
        "datasource",
        {},
    )

    if datasource.get("uid") != "prometheus":
        raise SystemExit(
            "FAIL: SLO panel does not use Prometheus datasource"
        )

    targets = panel.get(
        "targets",
        [],
    )

    if len(targets) != 1:
        raise SystemExit(
            "FAIL: each SLO panel must have exactly one target"
        )

    target = targets[0]

    if (
        target.get(
            "datasource",
            {},
        ).get("uid")
        != "prometheus"
    ):
        raise SystemExit(
            "FAIL: SLO target does not use Prometheus datasource"
        )

    expr = target.get(
        "expr"
    )

    if not expr:
        raise SystemExit(
            "FAIL: SLO dashboard target missing PromQL expression"
        )

    actual_queries.add(
        expr
    )

    print(
        f"panel={panel.get('title')} query={expr}"
    )

if actual_queries != expected_queries:
    print(
        "actual_queries="
        + repr(
            sorted(
                actual_queries
            )
        )
    )
    raise SystemExit(
        "FAIL: unexpected SLO dashboard query set"
    )

print(
    "PASS: SLO dashboard structure valid"
)
PY

echo
echo "===== GRAFANA PROVISIONING ====="

grep -Fq \
  'uid: prometheus' \
  grafana/provisioning/datasources/prometheus.yml

grep -Fq \
  'url: http://prometheus:9090' \
  grafana/provisioning/datasources/prometheus.yml

grep -Fq \
  'path: /etc/grafana/dashboards' \
  grafana/provisioning/dashboards/dashboards.yml

echo "PASS: Grafana provisioning supports SLO dashboard"

echo
echo "===== SLO DOCUMENTATION ====="

for VALUE in \
  '# SLIs, SLOs, and Error Budgets' \
  '99%' \
  '250 ms' \
  '30 minute' \
  'sre_lab_http_requests_total' \
  'sre_lab_http_request_duration_seconds_bucket'
do
  if ! grep -Fq \
    -- "$VALUE" \
    docs/slo-error-budgets.md
  then
    echo "FAIL: documentation value missing: $VALUE"
    exit 1
  fi
done

echo "PASS: SLO documentation contains required design decisions"

echo
echo "===== VALIDATION COMPLETE ====="

echo "PASS: SLO and error-budget configuration validation succeeded"
