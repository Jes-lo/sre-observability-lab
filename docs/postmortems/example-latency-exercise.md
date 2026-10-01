# Example Postmortem: Controlled Latency Incident

## Metadata

- Incident ID: LAB-LATENCY-EXAMPLE
- Date: 2026-10-01
- Start time: not persisted by the exercise output
- Recovery time: not persisted by the exercise output
- Duration: not used as an acceptance criterion
- Severity: laboratory critical and warning alert signals
- Affected SLO: latency
- Primary alert: `SreApiLatencyBurnRateFast`

## Summary

A controlled local incident generated approximately 500 ms application
responses through the isolated fault-enabled exercise API.

The exercise was intentionally designed to exceed the laboratory
250 ms latency SLO threshold without modifying the primary API.

This was a laboratory incident. No customer impact is claimed.

## Impact

During the degraded phase, the observed one-minute latency bad-event
ratio reached:

    0.5

The isolated exercise therefore generated sufficient controlled
latency to exercise the configured latency alert paths.

The primary observability stack remained unchanged.

## Detection

The following alerts reached `firing`:

- `SreApiHighLatencyRatio`
- `SreApiLatencyBurnRateFast`
- `SreApiLatencyBurnRateSlow`

Alertmanager routing was observed as:

    SreApiLatencyBurnRateFast -> local-critical
    SreApiLatencyBurnRateSlow -> local-warning
    SreApiHighLatencyRatio    -> local-warning

## Timeline

| Relative phase | Event |
| --- | --- |
| Baseline | Healthy `/api/work` traffic was generated and scraped. |
| Detection | Controlled `/api/slow?ms=500` traffic caused latency alerts to transition through pending to firing. |
| Investigation | Latency bad-event ratio and burn-rate metrics exceeded their configured thresholds. |
| Mitigation | The controlled slow-traffic process was stopped. |
| Recovery | Healthy traffic was generated and the latency bad-event ratio decreased. |
| Cleanup | Temporary API, Prometheus, Alertmanager, network, and exercise image were removed. |

Exact wall-clock incident timestamps were not persisted by this
exercise run and are therefore not invented here.

## Evidence

Observed degraded-state values:

    bad_ratio_before=0.5
    burn_1m=49.99999999999996
    burn_5m=48.84372099698386
    burn_15m=48.84372099698386

Observed recovery value:

    bad_ratio_after=0.15662650602409645

Additional evidence:

    alerts_expected=3
    alerts_firing=true
    alertmanager_routing_valid=true
    mitigation=controlled_fault_source_stopped
    healthy_response=200
    temporary_runtime_removed=true
    primary_runtime_changed=false

These values describe this specific validated run. They are not fixed
performance targets for future runs.

## Contributing Factors

The exercise intentionally alternated healthy traffic with controlled
responses from:

    GET /api/slow?ms=500

The configured laboratory latency objective is 250 ms, so these
requests intentionally produced bad latency events.

This should not be interpreted as a production root cause.

## Mitigation

The controlled slow-request traffic generator was stopped.

No unrelated observability service was restarted or modified.

## Recovery Verification

Recovery was demonstrated by:

- successful HTTP 200 responses from `/api/work`;
- latency bad-event ratio decreasing from `0.5` to
  `0.15662650602409645`;
- removal of all temporary exercise containers and network;
- unchanged primary observability container IDs;
- primary fault injection remaining disabled;
- external n8n remaining unchanged.

The ratio was not required to reach zero immediately because the
recording rule uses a rolling time window.

## What Went Well

- all three expected latency alerts fired;
- critical and warning routing matched the configured design;
- mitigation required only stopping the controlled workload;
- recovery was visible in the latency SLO signal;
- temporary runtime cleanup succeeded.

## What Could Be Improved

The runner currently prints evidence to standard output but does not
persist structured wall-clock timestamps or a machine-readable
incident artifact.

## Follow-Up Actions

| Action | Owner | Status |
| --- | --- | --- |
| Preserve the current reproducible latency exercise in CI. | Lab maintainer | Implemented in Feature #9 CI integration |
| Consider machine-readable evidence artifacts in a future iteration. | Lab maintainer | Future enhancement |

## Lessons

The laboratory can reproduce a latency incident, detect it through real
Prometheus alert rules, route alerts through Alertmanager, mitigate the
controlled workload, observe initial recovery, and clean up without
modifying the primary runtime.

## Scope Note

This postmortem documents a controlled laboratory incident and does not
claim production or customer impact.
