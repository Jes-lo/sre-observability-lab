# SLIs, SLOs, and Error Budgets

## Overview

Feature #6 introduces request-based service level indicators,
service level objectives, and error-budget calculations for the
SRE & Observability Lab.

The implementation is intentionally local and designed for
reproducible SRE practice rather than production SLA management.

## Eligible Service Traffic

The SLO scope includes HTTP GET requests to:

- `/api/work`
- `/api/slow`
- `/api/error`

The following traffic is deliberately excluded:

- `/`
- `/healthz`
- `/readyz`
- `/metrics`
- unmatched routes

Health checks and Prometheus scrapes are operational traffic and
must not dominate user-facing service-level measurements.

The controlled fault endpoints remain in scope so later laboratory
features can demonstrate intentional error-budget consumption.

## Availability SLI

Availability is request based.

A good availability event is an eligible request that does not
return an HTTP 5xx response.

The SLI is:

    non-5xx eligible requests
    --------------------------
       all eligible requests

HTTP 4xx responses are treated as served requests for this
availability SLI because they indicate that the service remained
available and returned an application-level response.

A separate correctness SLI is outside the current project scope.

## Availability SLO

The laboratory availability objective is:

    99%

The allowed bad-event fraction is therefore:

    1%

## Latency SLI

Latency is also request based.

A good latency event is an eligible request completed within:

    250 ms

The application histogram has an explicit `0.25` second bucket, so
the latency SLI can use exact histogram bucket counts rather than a
quantile approximation.

The latency SLI is evaluated only across eligible non-5xx requests.

A failed 5xx request is already a bad availability event and is excluded
from the latency denominator. This prevents a fast server failure from
artificially improving the latency SLI.

The SLI is:

    non-5xx eligible requests <= 250 ms
    -------------------------------------
       all non-5xx eligible requests

## Latency SLO

The laboratory latency objective is:

    99% of eligible requests <= 250 ms

The allowed slow-event fraction is therefore:

    1%

## Evaluation Window

Feature #6 uses a rolling:

    30 minute

window.

This short window is intentional for a local laboratory because it
allows SLO and error-budget behavior to be demonstrated without
requiring weeks of continuously running infrastructure.

It must not be interpreted as a recommendation for a production
SLO window.

If no eligible requests exist in the rolling window, the availability
or latency ratio is intentionally left without a value rather than
treating an idle service as either perfect or failed.

## Error Budget

For each SLO:

    error budget = 1 - SLO target

With a 99% objective:

    error budget = 1%

Budget consumption is calculated as:

    observed bad-event ratio
    ------------------------
        allowed bad ratio

A value of:

- `0` means no budget has been consumed
- `1` means the entire budget has been consumed
- greater than `1` means the objective has been exceeded

Remaining budget is bounded at zero.

## Prometheus Recording Rules

The SLO recording rules calculate:

- eligible request volume
- HTTP 5xx volume
- availability ratio
- requests completed within 250 ms
- total latency-observed requests
- latency ratio
- SLO targets
- allowed error budgets
- budget consumption
- remaining error budgets

The rules use the existing application metrics:

    sre_lab_http_requests_total
    sre_lab_http_request_duration_seconds_bucket
    sre_lab_http_request_duration_seconds_count

No additional application instrumentation is required.

## Scope

Feature #6 does not introduce:

- Alertmanager
- alert routing
- burn-rate alerts
- multi-window alerting
- k6
- production SLA reporting

Burn-rate alerting and Alertmanager belong to the next alerting
feature.

Controlled load and failure scenarios belong to the later load
generation feature.

## Grafana Dashboard

Feature #6 adds the provisioned dashboard:

    SRE Lab - SLO & Error Budget

Dashboard UID:

    sre-slo-overview

The dashboard uses the existing Prometheus datasource and visualizes:

- availability SLI
- latency SLI
- availability SLO target
- latency SLO target
- availability error-budget consumption
- latency error-budget consumption
- remaining availability error budget
- remaining latency error budget

The default dashboard time range is the same rolling 30-minute window
used by the SLO recording rules.

## Validation

Feature #6 configuration is validated by:

    scripts/validate-slo.sh

GitHub Actions executes the validator in:

    SLO Configuration Validation

The validator checks:

- required SLO files
- Docker Compose parsing
- Prometheus configuration and recording-rule syntax
- the exact SLO recording-rule set
- eligible-route scope
- exclusion of HTTP 5xx responses from the latency SLI
- the 250 ms latency threshold
- 99% availability and latency objectives
- no-traffic guards
- absence of alerting rules from Feature #6
- Grafana dashboard UID, title, panel count, datasource, and PromQL
- Grafana provisioning
- required SLO documentation

Feature #6 was also runtime-validated with controlled traffic.

The runtime proof established that:

- healthy requests contributed to the eligible request population
- controlled HTTP 500 responses reduced the availability SLI
- controlled slow responses reduced the latency SLI
- error-budget consumption matched the defined arithmetic
- remaining error budgets were bounded at zero
- the API was restored to its safe default with fault injection disabled

Alerting and burn-rate notification logic remain outside Feature #6.
