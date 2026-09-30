# ADR-001: SRE and Observability Lab Architecture

## Status

Accepted

## Context

The portfolio already demonstrates infrastructure automation, secure software delivery, and Kubernetes GitOps.

This project should demonstrate a different engineering discipline: operating services reliably using observability, SLOs, alerting, incident response, and evidence-driven troubleshooting.

Using Kubernetes again would add infrastructure complexity without being necessary to demonstrate the primary SRE objectives.

## Decision

The lab will use Docker Compose as its local runtime.

The initial architecture will contain:

- a purpose-built instrumented Node.js service
- Prometheus for metrics
- Grafana for visualization
- Alertmanager for alert routing
- Loki for centralized logs
- Grafana Alloy for telemetry collection
- Tempo for distributed traces
- OpenTelemetry for application telemetry
- k6 for controlled workload generation

Git will remain the source of truth for configuration and documentation.

## Reliability Model

The service will expose enough behavior to intentionally create and measure:

- normal traffic
- elevated latency
- application errors
- resource pressure
- partial degradation

The lab will define SLIs and SLOs before creating alert policies.

Alerts should prioritize user-visible symptoms and SLO consumption rather than arbitrary infrastructure thresholds.

## Telemetry Model

The project will use the three primary observability signals:

### Metrics

Used to quantify service health, traffic, errors, latency, saturation, and SLO compliance.

### Logs

Structured application and platform events used for contextual investigation.

### Traces

Request-level execution information used to understand latency and request paths.

The project will demonstrate correlation between these signals where practical.

## Security

The environment must not require committed secrets or long-lived cloud credentials.

Secrets, if required later, must be provided at runtime and excluded from source control.

Containers should use restrictive runtime settings where compatible with the software.

## Cost

The core architecture will run locally and must not require paid cloud resources.

Cloud services are outside the initial scope.

## Reproducibility

A future user should be able to clone the repository, satisfy documented prerequisites, start the environment, generate traffic, reproduce defined incidents, and execute validation workflows.

Automated bootstrap and validation will be added before the project is considered complete.

## Consequences

### Advantages

- observability remains the primary focus
- no cloud cost is required
- lower resource requirements than another Kubernetes lab
- faster incident simulation and recovery cycles
- architecture is portable and easy to reproduce

### Trade-offs

- the lab does not demonstrate Kubernetes-native observability deployment
- the environment is not production HA
- local resource constraints differ from production systems

These are deliberate boundaries rather than missing functionality.
