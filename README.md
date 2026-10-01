# SRE & Observability Lab

**Core technologies:** Node.js · Docker Compose · Prometheus · Alertmanager · Grafana · Loki · Grafana Alloy · OpenTelemetry · Tempo · k6 · GitHub Actions

A local, reproducible SRE and observability laboratory focused on service reliability engineering, telemetry correlation, SLOs, alerting, incident response, and troubleshooting.

## Project Goals

The project will demonstrate:

- application instrumentation
- RED metrics: rate, errors, and duration
- Prometheus metrics collection
- Grafana dashboards
- centralized logs with Loki
- telemetry collection with Grafana Alloy
- distributed tracing with OpenTelemetry and Tempo
- metrics, logs, and traces correlation
- SLIs, SLOs, and error budgets
- symptom-based and burn-rate alerting
- Alertmanager routing
- controlled load generation with k6
- controlled failure scenarios
- incident detection and troubleshooting
- runbooks and postmortems
- automated configuration validation
- reproducible local bootstrap

## Architecture Direction

The laboratory will run locally using Docker Compose.

Core components:

- instrumented Node.js API
- Prometheus
- Grafana
- Alertmanager
- Grafana Alloy
- Loki
- Tempo
- OpenTelemetry instrumentation
- k6

## Implemented Features

The current laboratory includes:

- instrumented Node.js API with RED metrics and controlled fault injection
- Prometheus collection and recording rules
- Grafana RED overview dashboard
- structured application logging with sensitive-header redaction
- Grafana Alloy file collection without Docker socket access
- Loki centralized log storage
- persistent Alloy file positions and Loki data
- Grafana Loki datasource provisioning
- OpenTelemetry distributed tracing exported through Grafana Alloy to Tempo
- exact log-to-trace correlation with `trace_id` and `span_id`
- bidirectional Grafana navigation between Loki logs and Tempo traces
- request-based availability and latency SLIs over explicit application routes
- 99% availability and latency SLOs over a rolling 30-minute local-lab window
- Prometheus error-budget consumption and remaining-budget recording rules
- Grafana SLO and error-budget dashboard
- symptom-based HTTP 5xx and latency alerts
- multi-window availability and latency error-budget burn-rate alerting
- local Alertmanager severity routing with no external notification credentials
- deterministic Prometheus alert-rule tests
- isolated k6 controlled-load and controlled-failure scenarios
- hardened load-test target on a dedicated internal Docker network
- reproducible availability and latency incident exercises
- incident-response lifecycle and operational runbooks
- blameless postmortem template and validated exercise examples
- automated application, container, Prometheus, Grafana, logging, tracing, SLO, alerting, load-scenario, and incident-response validation

Observability design and operational details are documented in:

- [Centralized Logging](docs/centralized-logging.md)
- [Distributed Tracing](docs/distributed-tracing.md)
- [SLIs, SLOs, and Error Budgets](docs/slo-error-budgets.md)
- [Alerting and Alertmanager](docs/alerting-and-alertmanager.md)
- [Controlled Load and Failure Scenarios](docs/controlled-load-and-failures.md)
- [Incident Response](docs/incident-response.md)
- [Runbook: High HTTP 5xx Ratio](docs/runbooks/high-5xx.md)
- [Runbook: High Latency Ratio](docs/runbooks/high-latency.md)
- [Postmortem Template](docs/postmortems/template.md)
- [Availability Incident Example](docs/postmortems/example-availability-exercise.md)
- [Latency Incident Example](docs/postmortems/example-latency-exercise.md)

## Security Principles

- no secrets committed to Git
- no persistent cloud credentials
- least privilege where applicable
- containers run with restricted privileges where supported
- explicit resource limits
- minimal exposed ports
- immutable or pinned dependencies where practical
- configuration validated before merge

## Cost Boundary

The primary environment is local.

No cloud infrastructure is required for the core project.

Any future cloud integration must be:

1. optional,
2. explicitly documented,
3. disabled by default,
4. protected by cost guardrails.

## Non-Goals

This project is not intended to demonstrate:

- Kubernetes platform engineering
- production multi-region architecture
- managed cloud observability services
- production-scale high availability

Those concerns are intentionally separated from the SRE and observability focus.

## Status

Implemented so far:

1. instrumented application
2. Prometheus metrics collection and recording rules
3. Grafana RED dashboard
4. centralized logging with Grafana Alloy and Loki
5. OpenTelemetry distributed tracing with Alloy, Tempo, and bidirectional log correlation
6. request-based SLIs, SLOs, and error budgets with Prometheus and Grafana
7. symptom-based and burn-rate alerting with Prometheus and Alertmanager
8. controlled load and failure scenarios with k6
9. reproducible incident response, runbooks, and postmortems

The feature roadmap is complete through incident response. Final fresh-clone reproducibility and release validation remain before `v1.0.0`.

## License and Third-Party Software

Repository-specific material is provided under the terms in
[LICENSE](LICENSE).

Third-party software, services, libraries, tools, trademarks, container images,
and other materials remain subject to their respective licenses, terms, and
intellectual-property rights.

See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party components
and technologies currently used by this project.

See [SECURITY.md](SECURITY.md) for the repository security policy.
