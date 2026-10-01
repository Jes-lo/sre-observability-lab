# Controlled Load and Failure Scenarios

## Overview

Feature #8 adds reproducible controlled-load and controlled-failure
scenarios to the SRE & Observability Lab using Grafana k6.

The feature is designed for local SRE experimentation and automated
validation. It is not a production capacity benchmark.

The implementation deliberately separates the load-test runtime from
the primary observability runtime.

## Architecture

The controlled-load path is:

    k6
     |
     v
    api-load-target

Both services run only when the Docker Compose `load-test` profile is
enabled.

The dedicated runtime uses an internal Docker network and neither
service publishes a host port.

The primary API remains separate and retains:

    LAB_FAULTS_ENABLED=false

The dedicated load target uses:

    LAB_FAULTS_ENABLED=true

This prevents controlled fault scenarios from requiring fault
injection to be enabled on the primary API.

## k6 Image

The laboratory uses k6 v2.3.0 through the immutable image:

    grafana/k6@sha256:9c2dee7f8ed74d317e4027c06a10f169b625638189de8d4555d0b3486a5aeb34

The k6 runtime is configured with:

    K6_NO_USAGE_REPORT=true

The controlled-load network is also Docker-internal, so the test
runtime is not intended to contact external services.

## Scenarios

The test definition is:

    load/k6/scenarios.js

Three scenarios are implemented.

### Healthy Traffic

Scenario:

    healthy

Target:

    GET /api/work

Execution:

    2 virtual users
    10 seconds

Expected behavior:

    HTTP 200

### Controlled Latency

Scenario:

    latency

Target:

    GET /api/slow?ms=500

Execution:

    2 virtual users
    10 seconds

Expected behavior:

    HTTP 200
    response duration >= 450 ms
    response duration < 2000 ms

The broad upper boundary prevents the local test from turning normal
scheduler variance into a false failure.

It is not a production latency objective.

### Controlled HTTP 500

Scenario:

    http500

Target:

    GET /api/error

Execution:

    2 virtual users
    10 seconds

Expected behavior:

    HTTP 500

The HTTP 500 response is intentional.

k6 may therefore report a high `http_req_failed` value during this
scenario even when the scenario is operating correctly.

Acceptance is based on the explicit check that the controlled endpoint
returns HTTP 500.

## Scenario Threshold

The current k6 threshold requires:

    checks rate > 0.99

This checks whether the explicit scenario assertions succeed.

It does not assert a production throughput, capacity, or availability
target.

## Runtime Isolation

`api-load-target` uses:

- a dedicated Docker Compose profile
- no published host ports
- an internal Docker network
- a read-only root filesystem
- all Linux capabilities dropped
- `no-new-privileges`
- explicit CPU, memory, and PID limits
- ephemeral application logging under `/tmp`
- OpenTelemetry tracing disabled for the temporary target

k6 uses:

- a digest-pinned image
- explicit non-root UID/GID `65534:65534`
- a read-only root filesystem
- all Linux capabilities dropped
- `no-new-privileges`
- explicit CPU, memory, and PID limits
- no Docker socket access

## Metrics Validation

After executing the three scenarios, runtime validation confirms that
the application exported request counter series for:

    /api/work  -> HTTP 200
    /api/slow  -> HTTP 200
    /api/error -> HTTP 500

Exact request counts are intentionally not fixed acceptance values.

Counts can vary slightly with runtime scheduling and scenario timing.

## Automated Validation

Static validation is provided by:

    scripts/validate-load.sh

Runtime validation is provided by:

    scripts/validate-load-runtime.sh

The runtime validator uses a separate Docker Compose project name so
it cannot recreate or remove containers from the primary laboratory
Compose project.

The validator:

- starts only the dedicated load target
- waits for it to become healthy
- verifies runtime isolation and hardening
- runs `healthy`
- runs `latency`
- runs `http500`
- validates real application metrics
- verifies k6 run containers are ephemeral
- removes its temporary runtime
- preserves an existing primary stack when one is present
- preserves the external n8n container when one is present

GitHub Actions executes both static and runtime validation in the
`Load Scenario Validation` job.

## Scope

Feature #8 does not claim to provide:

- production performance benchmarking
- production capacity planning
- stress testing of external systems
- production fault injection
- production SLA validation
- autoscaling validation
- distributed load generation
- cloud load testing

The scenarios intentionally remain small, local, reproducible, and
bounded.

Incident-response workflows, runbooks, and postmortems are implemented
separately in Feature #9.
