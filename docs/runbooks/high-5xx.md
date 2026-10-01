# Runbook: High HTTP 5xx Ratio

## Trigger

Use this runbook for:

- `SreApiHigh5xxRatio`
- `SreApiAvailabilityBurnRateFast`
- `SreApiAvailabilityBurnRateSlow`

## Symptom

Eligible application requests are returning HTTP 5xx responses and
availability error budget may be consumed.

## Initial Checks

Confirm the active alert and inspect:

    sre_api:slo_availability_bad_ratio:rate1m

and, when relevant:

    sre_api:slo_availability_burn_rate:ratio1m
    sre_api:slo_availability_burn_rate:ratio5m
    sre_api:slo_availability_burn_rate:ratio15m

Check the RED dashboard and identify which eligible route is
producing 5xx responses.

## Logs

Use Loki to inspect application logs near the alert time.

Prefer entries containing:

- route
- status code
- request ID
- trace ID when available

## Traces

If a trace ID is present, inspect the corresponding Tempo trace to
understand the request path.

## Controlled-Lab Cause

Feature #8 can deliberately generate HTTP 500 responses against:

    GET /api/error

This is a controlled laboratory fault.

Do not assume a 5xx alert in another environment has the same cause.

## Mitigation

For the controlled exercise:

1. stop the HTTP 500 workload;
2. do not enable fault injection on the primary API;
3. preserve relevant metrics/log evidence;
4. verify healthy traffic using `/api/work`.

## Recovery Verification

Confirm:

- `/api/work` returns HTTP 200;
- controlled 5xx generation has stopped;
- availability bad-event ratio decreases;
- burn rate returns toward zero as windows age out;
- availability alerts resolve after their configured durations;
- primary `/api/error` remains HTTP 403 when faults are disabled.

## Escalation

This laboratory does not configure external escalation.

If the cause cannot be explained by the controlled scenario, record
the unresolved evidence and stop the exercise rather than introducing
unplanned destructive changes.
