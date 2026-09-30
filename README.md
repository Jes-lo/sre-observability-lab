# SRE & Observability Lab

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

Planned core components:

- instrumented Node.js API
- Prometheus
- Grafana
- Alertmanager
- Grafana Alloy
- Loki
- Tempo
- OpenTelemetry instrumentation
- k6

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

Foundation and architecture phase.
