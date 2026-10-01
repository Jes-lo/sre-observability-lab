# Example Postmortem: Controlled Availability Incident

## Metadata

- Incident ID: LAB-AVAILABILITY-EXAMPLE
- Date: 2026-10-01
- Start time: not persisted by the exercise output
- Recovery time: not persisted by the exercise output
- Duration: not used as an acceptance criterion
- Severity: laboratory critical and warning alert signals
- Affected SLO: availability
- Primary alert: `SreApiAvailabilityBurnRateFast`

## Summary

A controlled local incident generated HTTP 500 responses through the
fault-enabled isolated exercise API.

The exercise was intentionally designed to trigger the availability
symptom and error-budget burn-rate alerts without enabling fault
injection on the primary API.

This was a laboratory incident. No customer impact is claimed.

## Impact

During the degraded phase, the observed one-minute availability
bad-event ratio reached:

    0.5

The isolated exercise therefore produced sufficient controlled
availability degradation to exceed the configured alert thresholds.

The exercise did not modify the primary observability stack.

## Detection

The following alerts reached `firing`:

- `SreApiHigh5xxRatio`
- `SreApiAvailabilityBurnRateFast`
- `SreApiAvailabilityBurnRateSlow`

Alertmanager routing was observed as:

    SreApiAvailabilityBurnRateFast -> local-critical
    SreApiAvailabilityBurnRateSlow -> local-warning
    SreApiHigh5xxRatio             -> local-warning

## Timeline

| Relative phase | Event |
| --- | --- |
| Baseline | Healthy `/api/work` traffic was generated and scraped. |
| Detection | Controlled HTTP 500 traffic caused the availability alerts to transition through pending to firing. |
| Investigation | Availability bad-event ratio and burn-rate metrics exceeded their configured thresholds. |
| Mitigation | The controlled fault-traffic process was stopped. |
| Recovery | Healthy traffic was generated and the bad-event ratio decreased. |
| Cleanup | Temporary API, Prometheus, Alertmanager, network, and exercise image were removed. |

Exact wall-clock incident timestamps were not persisted by this
exercise run and are therefore not invented here.

## Evidence

Observed degraded-state values:

    bad_ratio_before=0.5
    burn_1m=49.99999999999996
    burn_5m=49.50982625274114
    burn_15m=49.50982625274115

Observed recovery value:

    bad_ratio_after=0.3775198533903482

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

The exercise intentionally generated a mixture of healthy requests and
controlled HTTP 500 responses.

This generated the availability degradation required to exercise the
configured symptom and burn-rate alert paths.

It should not be interpreted as a production root cause.

## Mitigation

The controlled HTTP 500 traffic generator was stopped.

No unrelated service was restarted or modified.

## Recovery Verification

Recovery was demonstrated by:

- successful HTTP 200 responses from `/api/work`;
- availability bad-event ratio decreasing from `0.5` to
  `0.3775198533903482`;
- removal of all temporary exercise containers and network;
- unchanged primary observability container IDs;
- primary fault injection remaining disabled;
- external n8n remaining unchanged.

The ratio was not required to reach zero immediately because the
recording rule uses a rolling time window.

## What Went Well

- all three expected availability alerts fired;
- critical and warning routing matched the configured design;
- mitigation required only stopping the controlled fault source;
- recovery was observable in the SLO signal;
- temporary runtime cleanup succeeded.

## What Could Be Improved

The runner currently prints evidence to standard output but does not
persist structured wall-clock timestamps or a machine-readable
incident artifact.

## Follow-Up Actions

| Action | Owner | Status |
| --- | --- | --- |
| Preserve the current reproducible availability exercise in CI. | Lab maintainer | Implemented in Feature #9 CI integration |
| Consider machine-readable evidence artifacts in a future iteration. | Lab maintainer | Future enhancement |

## Lessons

The laboratory can reproduce an availability incident from controlled
HTTP 500 traffic, detect it through real Prometheus alert rules, route
the alerts through Alertmanager, mitigate the fault source, observe
initial recovery, and clean up without modifying the primary stack.

## Scope Note

This postmortem documents a controlled laboratory incident and does not
claim production or customer impact.
