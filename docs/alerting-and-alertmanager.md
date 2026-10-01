# Alerting and Alertmanager

## Overview

Feature #7 introduces symptom-based alerting, multi-window
error-budget burn-rate alerting, and local Alertmanager routing for
the SRE & Observability Lab.

The implementation builds on the request-based SLIs, 99% SLOs, and
1% error budgets introduced in Feature #6.

The design is intentionally optimized for a reproducible local
laboratory. The thresholds and short windows used here must not be
interpreted as production alerting recommendations.

## Architecture

The alerting path is:

    instrumented API
          |
          v
      Prometheus
          |
          +-- alerting recording rules
          |
          +-- alert rules
          |
          v
     Alertmanager
          |
          +-- critical -> local-critical
          |
          +-- warning  -> local-warning

Prometheus evaluates the alert rules and sends firing alerts to:

    alertmanager:9093

Alertmanager is exposed to the host only on:

    127.0.0.1:9093

No external notification service is configured.

## Eligible Traffic

Alerting uses the same service-traffic scope as the SLO implementation.

Eligible requests are HTTP GET requests to:

- `/api/work`
- `/api/slow`
- `/api/error`

Operational traffic such as health checks, readiness checks,
Prometheus scrapes, and unmatched routes is excluded.

## Availability Bad-Event Ratio

An availability bad event is an eligible HTTP request returning a
5xx response.

For each alerting window:

    HTTP 5xx eligible request rate
    ------------------------------
       all eligible request rate

The implementation calculates the ratio over:

- 1 minute
- 5 minutes
- 15 minutes

If no eligible traffic exists, the ratio intentionally has no value.
An idle service is not represented as either successful or failed.

## Latency Bad-Event Ratio

The latency threshold remains:

    250 ms

Latency alerting evaluates only eligible non-5xx requests, consistent
with the Feature #6 latency SLI.

The bad-event ratio is equivalent to:

    1 - good latency ratio

where a good latency event is a non-5xx eligible request completed
within 250 ms.

The same windows are calculated:

- 1 minute
- 5 minutes
- 15 minutes

HTTP 5xx responses are excluded from the latency denominator because
they are already availability failures.

## Burn Rate

Burn rate measures how quickly the allowed error budget is being
consumed.

For each SLO:

    observed bad-event ratio
    ------------------------
       allowed bad ratio

The laboratory SLO target is 99%, so the allowed bad ratio is 1%.

For example:

    observed bad-event ratio = 12%
    allowed bad ratio        = 1%

therefore:

    burn rate = 12x

Feature #7 records availability and latency burn rates over 1-minute,
5-minute, and 15-minute windows.

## Symptom Alerts

Two direct symptom alerts provide fast visibility into user-facing
service degradation.

### High HTTP 5xx Ratio

Alert:

    SreApiHigh5xxRatio

Condition:

    availability bad-event ratio over 1 minute > 5%

Required duration:

    30 seconds

Severity:

    warning

### High Latency Ratio

Alert:

    SreApiHighLatencyRatio

Condition:

    latency bad-event ratio over 1 minute > 5%

Required duration:

    30 seconds

Severity:

    warning

These alerts react directly to symptoms rather than infrastructure
implementation details.

## Fast Burn Alerts

Fast-burn alerts represent rapid error-budget consumption.

Availability alert:

    SreApiAvailabilityBurnRateFast

Latency alert:

    SreApiLatencyBurnRateFast

Condition:

    burn rate over 1 minute > 10x
    AND
    burn rate over 5 minutes > 10x

Required duration:

    30 seconds

Severity:

    critical

Because the laboratory SLO evaluation period is deliberately short,
a sustained 10x burn rate is conceptually equivalent to consuming a
30-minute error budget in approximately 3 minutes.

This relationship is useful for the laboratory but is not a
production SLO-window recommendation.

## Sustained Burn Alerts

Sustained-burn alerts identify slower but persistent budget
consumption.

Availability alert:

    SreApiAvailabilityBurnRateSlow

Latency alert:

    SreApiLatencyBurnRateSlow

Condition:

    burn rate over 5 minutes > 2x
    AND
    burn rate over 15 minutes > 2x

Required duration:

    1 minute

Severity:

    warning

With the laboratory's 30-minute SLO window, a sustained 2x burn rate
is conceptually equivalent to consuming the error budget in
approximately 15 minutes.

## Alertmanager Routing

Alertmanager defines three local receivers:

    local-default
    local-critical
    local-warning

Severity routing is:

    severity="critical" -> local-critical
    severity="warning"  -> local-warning

The receivers intentionally have no external notification
integration.

This allows grouping and routing behavior to be inspected locally
without introducing email credentials, webhook secrets, chat tokens,
PagerDuty keys, or other external dependencies.

## Grouping

Alertmanager groups alerts by:

- service
- SLO
- severity

The local timing configuration uses:

    group_wait:       5s
    group_interval:   30s
    repeat_interval:  30m

These timings make routing behavior practical to inspect during local
laboratory exercises.

## Alertmanager Runtime Security

The Alertmanager container uses:

- an immutable digest-pinned container image
- a non-root image user
- a read-only root filesystem
- all Linux capabilities dropped
- `no-new-privileges`
- explicit memory, CPU, and process limits
- localhost-only host exposure
- a persistent data volume
- no Docker socket access

Alertmanager high-availability clustering is deliberately disabled by:

    --cluster.listen-address=

The laboratory runs a single local Alertmanager instance.

## External Notifications

Feature #7 does not configure:

- email
- Slack
- Microsoft Teams
- PagerDuty
- external webhooks
- cloud notification services

No real notification credentials are required.

External receiver integrations are outside the current laboratory
scope and would require a separate security review before use.

## Deterministic Validation

Alerting behavior is tested with:

    observability/prometheus/alerting-rules.test.yml

and:

    promtool test rules

The deterministic test suite includes two scenarios.

The first verifies that no eligible traffic produces no artificial
SLI/burn-rate values and no alerts.

The second models a 12% bad-event ratio and verifies that:

    bad-event ratio ~= 0.12
    burn rate       ~= 12x

The PromQL assertions use a very small numerical tolerance because
floating-point evaluation is not guaranteed to serialize values such
as 0.12 identically.

The same scenario also verifies all six alert rules after their
configured `for` durations.

## Configuration Validation

Feature #7 is validated by:

    scripts/validate-alerting.sh

The validator checks:

- Docker Compose parsing
- Alertmanager configuration syntax with `amtool`
- Prometheus configuration syntax
- the 12 alerting recording rules
- the 6 alert rules
- deterministic `promtool test rules` scenarios
- the three local Alertmanager receivers
- critical and warning severity routing
- absence of external receiver integrations
- Alertmanager container hardening
- Prometheus-to-Alertmanager wiring
- deterministic test coverage

## Runtime Validation

The implementation has also been runtime-validated locally.

Runtime validation established that:

- Alertmanager starts with the expected non-root and hardened runtime
- Alertmanager loads the configured local receivers
- Prometheus loads all 36 current recording and alert rules
- all current Prometheus rules evaluate successfully
- Prometheus discovers one active Alertmanager target
- no Alertmanager targets are dropped
- synthetic critical alerts route to `local-critical`
- synthetic warning alerts route to `local-warning`
- routing probes can be resolved and removed cleanly
- the application remains in its safe fault-disabled state after
  validation
- unrelated project containers and the external n8n container remain
  unchanged

## Real-Fault End-to-End Validation

Feature #7 was additionally validated with an isolated temporary
runtime using the real application fault endpoints.

The validation used:

- the real `/api/work` endpoint
- the real `/api/error` controlled HTTP 500 endpoint
- the real `/api/slow` controlled latency endpoint
- the production-shaped application metrics
- the Feature #7 recording rules
- the Feature #7 alert rules
- the Feature #7 Alertmanager routing configuration

The isolated runtime established baseline counter series before
introducing sustained controlled faults.

During the degraded scenario:

- the availability bad-event ratio exceeded the 5% symptom threshold
- the latency bad-event ratio exceeded the 5% symptom threshold
- the 1-minute and 5-minute availability burn rates exceeded 10x
- the 1-minute and 5-minute latency burn rates exceeded 10x
- the 15-minute availability burn rate exceeded 2x
- the 15-minute latency burn rate exceeded 2x
- all six configured alerts reached the `firing` state
- both fast-burn alerts were routed to `local-critical`
- both symptom alerts and both sustained-burn alerts were routed to
  `local-warning`

The exact observed ratios depend on scrape timing and generated
traffic volume, so they are not treated as fixed test constants.
The validation instead requires the configured alert thresholds to
be exceeded and the resulting alert states and routing to match the
design.

The entire E2E runtime used an isolated Docker network and temporary
containers. After validation, those resources were removed.

The primary observability stack was not recreated or modified, the
primary application's fault injection remained disabled, and the
external n8n container remained unchanged.

## Scope

Feature #7 does not introduce:

- external alert delivery
- production paging
- Alertmanager high availability
- production SLO-window recommendations
- k6 load generation
- automated incident workflows
- runbooks or postmortems

Controlled load and failure scenarios are implemented in the next
laboratory phase.

Incident-response workflows, runbooks, and postmortems remain a later
phase.
