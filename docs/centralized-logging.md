# Centralized Logging

## Overview

The SRE & Observability Lab centralizes structured application logs locally with Grafana Alloy and Loki.

The implemented flow is:

    Node.js API
        |
        | structured JSON
        v
    /var/log/sre-api/api.log
        |
        | read-only shared volume
        v
    Grafana Alloy
        |
        | Loki HTTP push API
        v
    Loki
        |
        | Grafana datasource
        v
    Grafana

The logging path is intentionally independent from the Docker socket.

## Design Goals

The centralized logging implementation is designed to demonstrate:

- structured JSON application logging
- sensitive-header redaction before centralization
- deterministic local collection
- low-cardinality Loki labels
- structured metadata for correlation fields
- original event timestamp preservation
- persistent file-tail positions
- persistent Loki storage
- read-only access to application logs from the collector
- non-root container execution
- restricted Linux capabilities
- explicit CPU, memory, and PID limits
- local-only service exposure where a host port is required
- no required cloud service
- no persistent cloud credentials

## Application Logging

The Node.js API uses Pino and pino-http.

Application logs are written to:

    /var/log/sre-api/api.log

The same structured events remain available on stdout.

The application performs sensitive-header redaction before data reaches the centralized logging pipeline.

Examples of headers treated as sensitive include:

- authorization
- cookie
- set-cookie
- proxy-authorization
- x-api-key
- x-auth-token
- x-access-token
- x-amz-security-token

Redacted values are represented as:

    [Redacted]

This prevents the centralized logging system from becoming the first location where sensitive HTTP header values are removed.

## Shared Log Volume

The API writes application logs to the named Compose volume:

    api_logs

The API receives writable access:

    api_logs:/var/log/sre-api

Grafana Alloy receives read-only access:

    api_logs:/var/log/sre-api:ro

Alloy therefore does not require write access to application log files.

The implementation does not mount:

    /var/run/docker.sock

This avoids granting the telemetry collector access to the Docker daemon.

## Grafana Alloy

Grafana Alloy reads:

    /var/log/sre-api/api.log

The collector runs explicitly as:

    UID 473
    GID 473

Its root filesystem is read-only and the container drops all Linux capabilities.

Anonymous Alloy usage reporting is explicitly disabled with:

    --disable-reporting

Persistent Alloy state is stored under:

    /var/lib/alloy/data

through the named volume:

    alloy_data

The storage path is explicitly configured with:

    --storage.path=/var/lib/alloy/data

## Persistent File Positions

The file source stores its current read offset under the Alloy storage path.

For the API source, the persistent positions file is:

    /var/lib/alloy/data/loki.source.file.api/positions.yml

This state allows Alloy to resume reading from the previously persisted file position after a restart.

Runtime validation demonstrated that:

1. an event written while Alloy was running was ingested once
2. the persisted file offset advanced
3. Alloy was stopped
4. a second event was written while Alloy was stopped
5. that event was not present in Loki while Alloy was offline
6. the persisted offset remained unchanged while Alloy was stopped
7. the same Alloy container was restarted
8. the second event was ingested
9. the first event was not reingested
10. the second event appeared exactly once
11. the persisted offset advanced after recovery

## Loki Labels

Only stable, low-cardinality dimensions are assigned as Loki labels:

    service="sre-api"
    environment="local"

Fields that may have high cardinality are deliberately not Loki labels.

Examples include:

- request_id
- method
- URL
- status code
- response time

This reduces unnecessary Loki stream cardinality.

## Structured Metadata

Correlation and request-specific fields are retained as structured metadata instead of stream labels.

The Alloy pipeline extracts:

- level
- event
- request_id
- method
- url
- status_code
- response_time_ms

The original JSON log line is preserved.

This allows request-specific investigation without turning each request into a distinct Loki stream.

## Timestamp Preservation

Pino records event time in Unix milliseconds.

Alloy extracts the original `time` field and applies:

    format = "UnixMs"

The resulting Loki timestamp therefore represents the original application event time rather than merely the collector ingestion time.

Runtime validation confirmed that the Loki nanosecond timestamp matched the original Pino millisecond timestamp after conversion.

## Loki Storage

Loki runs locally in single-process form for this laboratory.

The configuration uses:

- TSDB
- schema v13
- filesystem object storage
- replication factor 1
- in-memory ring
- filesystem chunk persistence
- structured metadata enabled

Persistent Loki data uses the named volume:

    loki_data

The root filesystem remains read-only while `/loki` is writable through the dedicated volume.

This is a local SRE lab design and is not intended to represent a production high-availability Loki deployment.

## Loki Security Boundary

The Loki container runs explicitly as:

    UID 10001
    GID 10001

Runtime restrictions include:

- read-only root filesystem
- all Linux capabilities dropped
- no-new-privileges
- 256 MiB memory limit
- 0.50 CPU limit
- 150 PID limit

Loki is exposed to the host only on:

    127.0.0.1:3100

Other services communicate with Loki through the internal Compose network.

## Grafana Integration

Loki is provisioned automatically in Grafana with the stable datasource UID:

    loki

Its internal URL is:

    http://loki:3100

Prometheus remains the default Grafana datasource.

The Loki datasource is configured as non-editable through provisioning.

Runtime validation demonstrated that Grafana:

- provisioned the Loki datasource successfully
- passed the Loki datasource health check
- queried a real application log through the Grafana datasource proxy

## Example LogQL Queries

All API logs:

    {service="sre-api", environment="local"}

HTTP 500-related log content:

    {service="sre-api", environment="local"} | json | status_code=500

Requests containing a specific request ID:

    {service="sre-api", environment="local"} | json | request_id="REQUEST_ID"

Requests to the work endpoint:

    {service="sre-api", environment="local"} | json | url=~"/api/work.*"

Errors recorded by the application:

    {service="sre-api", environment="local"} | json | level>=50

Search for a controlled troubleshooting marker:

    {service="sre-api", environment="local"} |= "MARKER"

These examples are intended for local investigation and troubleshooting.

## Validation

Centralized logging configuration is validated by:

    scripts/validate-logging.sh

The validator checks:

- required configuration files
- Docker Compose parsing
- Loki configuration validity
- Alloy configuration validity
- absence of Docker socket access
- immutable Loki and Alloy image digests
- Alloy usage-reporting disablement
- persistent Alloy storage configuration
- logging pipeline structure
- label-cardinality guardrails
- structured metadata fields
- Loki local-storage configuration
- Loki analytics disablement
- Compose hardening controls
- logging volume access modes
- Grafana Loki datasource provisioning
- required persistent volumes

GitHub Actions executes the validator in the job:

    Logging Configuration Validation

Application tests separately validate sensitive-header redaction.

## Persistent Volumes

Feature #4 introduces or uses these logging-related volumes:

    api_logs
    alloy_data
    loki_data

Their responsibilities are intentionally separated:

| Volume | Purpose | Writer |
| --- | --- | --- |
| `api_logs` | Application JSON logs | API |
| `alloy_data` | Collector state and file positions | Alloy |
| `loki_data` | Loki chunks and local state | Loki |

Alloy receives `api_logs` read-only.

## Privacy Considerations

The lab follows a minimize-before-centralize approach.

Sensitive HTTP headers are redacted by the application before they are written to the shared log volume.

The logging implementation also:

- avoids Docker socket access
- disables Alloy anonymous usage reporting
- disables Loki analytics reporting
- disables Grafana analytics reporting
- keeps services local
- commits no application secrets
- uses no cloud credentials

Observability does not override the privacy boundary of the application.

## Scope and Non-Goals

This implementation demonstrates a secure local centralized-logging architecture for SRE practice and portfolio purposes.

It does not attempt to provide:

- production Loki clustering
- multi-tenant authentication
- production retention policy design
- object storage in a cloud provider
- geographically redundant storage
- production disaster recovery
- production-scale log ingestion

Those concerns are intentionally outside the current lab scope.
