#!/usr/bin/env bash

set -euo pipefail

echo "===== REQUIRED INCIDENT-RESPONSE FILES ====="

for FILE in \
  docs/incident-response.md \
  docs/runbooks/high-5xx.md \
  docs/runbooks/high-latency.md \
  docs/postmortems/template.md \
  docs/postmortems/example-availability-exercise.md \
  docs/postmortems/example-latency-exercise.md \
  scripts/run-incident-exercise.sh
do
  if [[ ! -f "$FILE" ]]; then
    echo "FAIL: missing $FILE"
    exit 1
  fi

  echo "PASS: $FILE"
done

echo
echo "===== INCIDENT WORKFLOW ====="

python3 - <<'PY'
from pathlib import Path

text = Path(
    "docs/incident-response.md"
).read_text()

required = [
    "Detect",
    "Triage",
    "Investigate",
    "Mitigate",
    "Recover",
    "Verify",
    "Review",
    "SreApiHigh5xxRatio",
    "SreApiHighLatencyRatio",
    "SreApiAvailabilityBurnRateFast",
    "SreApiLatencyBurnRateFast",
    "docs/postmortems/template.md",
]

for item in required:
    if item not in text:
        raise SystemExit(
            "FAIL: incident workflow missing: "
            + item
        )

print("PASS: incident lifecycle documentation valid")
PY

echo
echo "===== 5XX RUNBOOK ====="

python3 - <<'PY'
from pathlib import Path

text = Path(
    "docs/runbooks/high-5xx.md"
).read_text()

required = [
    "SreApiHigh5xxRatio",
    "SreApiAvailabilityBurnRateFast",
    "SreApiAvailabilityBurnRateSlow",
    "sre_api:slo_availability_bad_ratio:rate1m",
    "sre_api:slo_availability_burn_rate:ratio1m",
    "/api/error",
    "/api/work",
    "HTTP 403",
]

for item in required:
    if item not in text:
        raise SystemExit(
            "FAIL: 5xx runbook missing: "
            + item
        )

print("PASS: 5xx runbook valid")
PY

echo
echo "===== LATENCY RUNBOOK ====="

python3 - <<'PY'
from pathlib import Path

text = Path(
    "docs/runbooks/high-latency.md"
).read_text()

required = [
    "SreApiHighLatencyRatio",
    "SreApiLatencyBurnRateFast",
    "SreApiLatencyBurnRateSlow",
    "sre_api:slo_latency_bad_ratio:rate1m",
    "sre_api:slo_latency_burn_rate:ratio1m",
    "/api/slow?ms=500",
    "/api/work",
    "250 ms",
]

for item in required:
    if item not in text:
        raise SystemExit(
            "FAIL: latency runbook missing: "
            + item
        )

print("PASS: latency runbook valid")
PY

echo
echo "===== POSTMORTEM TEMPLATE ====="

python3 - <<'PY'
from pathlib import Path

text = Path(
    "docs/postmortems/template.md"
).read_text()

required = [
    "## Metadata",
    "## Summary",
    "## Impact",
    "## Detection",
    "## Timeline",
    "## Evidence",
    "## Contributing Factors",
    "## Mitigation",
    "## Recovery Verification",
    "## What Went Well",
    "## What Could Be Improved",
    "## Follow-Up Actions",
    "## Lessons",
]

for item in required:
    if item not in text:
        raise SystemExit(
            "FAIL: postmortem template missing: "
            + item
        )

print("PASS: postmortem template valid")
PY

echo
echo "===== POSTMORTEM EXAMPLES ====="

python3 - <<'PYEXAMPLES'
from pathlib import Path

availability = Path(
    "docs/postmortems/example-availability-exercise.md"
).read_text()

latency = Path(
    "docs/postmortems/example-latency-exercise.md"
).read_text()

availability_required = [
    "LAB-AVAILABILITY-EXAMPLE",
    "SreApiHigh5xxRatio",
    "SreApiAvailabilityBurnRateFast",
    "SreApiAvailabilityBurnRateSlow",
    "bad_ratio_before=0.5",
    "bad_ratio_after=0.3775198533903482",
    "local-critical",
    "local-warning",
    "controlled_fault_source_stopped",
    "temporary_runtime_removed=true",
    "No customer impact is claimed.",
]

latency_required = [
    "LAB-LATENCY-EXAMPLE",
    "SreApiHighLatencyRatio",
    "SreApiLatencyBurnRateFast",
    "SreApiLatencyBurnRateSlow",
    "bad_ratio_before=0.5",
    "bad_ratio_after=0.15662650602409645",
    "local-critical",
    "local-warning",
    "controlled_fault_source_stopped",
    "temporary_runtime_removed=true",
    "No customer impact is claimed.",
]

for item in availability_required:
    if item not in availability:
        raise SystemExit(
            "FAIL: availability example missing: "
            + item
        )

for item in latency_required:
    if item not in latency:
        raise SystemExit(
            "FAIL: latency example missing: "
            + item
        )

print(
    "PASS: validated-run postmortem examples complete"
)
PYEXAMPLES

echo
echo "===== ALERT REFERENCES ====="

python3 - <<'PY'
from pathlib import Path

alerts = Path(
    "observability/prometheus/alerting-rules.yml"
).read_text()

docs = "\n".join(
    Path(path).read_text()
    for path in [
        "docs/incident-response.md",
        "docs/runbooks/high-5xx.md",
        "docs/runbooks/high-latency.md",
    ]
)

expected = [
    "SreApiHigh5xxRatio",
    "SreApiHighLatencyRatio",
    "SreApiAvailabilityBurnRateFast",
    "SreApiAvailabilityBurnRateSlow",
    "SreApiLatencyBurnRateFast",
    "SreApiLatencyBurnRateSlow",
]

for name in expected:
    if name not in alerts:
        raise SystemExit(
            "FAIL: alert does not exist in Prometheus rules: "
            + name
        )

    if name not in docs:
        raise SystemExit(
            "FAIL: alert missing from incident docs: "
            + name
        )

print("alerts=6")
print("PASS: runbooks reference real alert rules")
PY

echo
echo "===== SAFETY LANGUAGE ====="

grep -Fq \
  'Do not record secrets' \
  docs/incident-response.md

grep -Fq \
  'Do not include secrets or credentials.' \
  docs/postmortems/template.md

grep -Fq \
  'do not enable fault injection on the primary API' \
  docs/runbooks/high-5xx.md

grep -Fq \
  'primary API remains fault-disabled' \
  docs/runbooks/high-latency.md

echo "PASS: safety boundaries documented"

echo
echo "===== INCIDENT EXERCISE RUNNER ====="

python3 - <<'PYRUN'
from pathlib import Path

text = Path(
    "scripts/run-incident-exercise.sh"
).read_text()

required = [
    "availability|latency",
    "LAB_FAULTS_ENABLED=true",
    "SreApiHigh5xxRatio",
    "SreApiHighLatencyRatio",
    "SreApiAvailabilityBurnRateFast",
    "SreApiLatencyBurnRateFast",
    "local-critical",
    "local-warning",
    "bad-event ratio decreased after mitigation",
    "temporary incident runtime removed",
    "primary API remains fault-disabled",
]

for item in required:
    if item not in text:
        raise SystemExit(
            "FAIL: incident exercise runner missing: "
            + item
        )

for forbidden in [
    "/var/run/docker.sock",
    "docker system prune",
    "docker volume prune",
    "docker network prune",
    "docker container prune",
]:
    if forbidden in text:
        raise SystemExit(
            "FAIL: unsafe incident exercise operation: "
            + forbidden
        )

print(
    "PASS: incident exercise runner semantics valid"
)
PYRUN

echo
echo "===== VALIDATION COMPLETE ====="

echo "PASS: incident-response documentation validation succeeded"
