# Runbook: High Latency Ratio

## Trigger

Use this runbook for:

- `SreApiHighLatencyRatio`
- `SreApiLatencyBurnRateFast`
- `SreApiLatencyBurnRateSlow`

## Symptom

Eligible non-5xx requests are exceeding the laboratory latency
threshold and latency error budget may be consumed.

The current SLO latency threshold is:

    250 ms

## Initial Checks

Inspect:

    sre_api:slo_latency_bad_ratio:rate1m

and, when relevant:

    sre_api:slo_latency_burn_rate:ratio1m
    sre_api:slo_latency_burn_rate:ratio5m
    sre_api:slo_latency_burn_rate:ratio15m

Use the RED dashboard to confirm elevated request duration.

## Logs

Inspect application logs around the affected period.

Correlate:

- route
- request ID
- duration
- trace ID when available

## Traces

Use Tempo when trace correlation is available to inspect the request
timeline.

## Controlled-Lab Cause

Feature #8 can deliberately generate latency through:

    GET /api/slow?ms=500

This is a controlled laboratory scenario and is intentionally above
the 250 ms SLO threshold.

## Mitigation

For the controlled exercise:

1. stop the latency workload;
2. preserve relevant metrics and trace evidence;
3. verify normal traffic using `/api/work`;
4. avoid restarting unrelated observability services.

## Recovery Verification

Confirm:

- healthy requests return HTTP 200;
- controlled latency generation has stopped;
- latency bad-event ratio decreases;
- latency burn rate returns toward zero as windows age out;
- latency alerts resolve after their configured durations;
- the primary API remains fault-disabled.

## Escalation

The laboratory provides no external paging or production escalation.

If the observed latency cannot be explained by the controlled
scenario, preserve the evidence and end the exercise without making
unplanned infrastructure changes.
