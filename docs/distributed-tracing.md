# Distributed Tracing

## Overview

Feature #5 adds distributed tracing and log-to-trace correlation to the local SRE and observability laboratory.

The tracing path is:

    Node.js API
      -> OpenTelemetry SDK
      -> OTLP/HTTP
      -> Grafana Alloy
      -> batch processor
      -> OTLP/gRPC
      -> Grafana Tempo
      -> Grafana

The logging correlation path is:

    Node.js API
      -> Pino JSON log
      -> trace_id / span_id / trace_flags
      -> shared API log volume
      -> Grafana Alloy
      -> Loki structured metadata
      -> Grafana
      -> Tempo derived-field navigation

The reverse correlation path is:

    Tempo trace
      -> Grafana tracesToLogsV2
      -> Loki
      -> matching application log

## Application Instrumentation

Tracing is implemented with the OpenTelemetry Node.js SDK.

The application uses:

- `@opentelemetry/api`
- `@opentelemetry/sdk-node`
- `@opentelemetry/auto-instrumentations-node`
- `@opentelemetry/exporter-trace-otlp-proto`

Tracing is explicitly enabled by:

    OTEL_TRACES_ENABLED=true

The service name is:

    sre-observability-lab-api

The application exports traces to Alloy through:

    http://alloy:4318/v1/traces

The local laboratory uses `always_on` sampling so controlled test requests are deterministic.

OpenTelemetry metric and log exporters are disabled because metrics and logs already have dedicated pipelines in this project.

## Noise Reduction

The following incoming endpoints are excluded from HTTP tracing:

    /healthz
    /readyz
    /metrics

This prevents health checks and Prometheus scraping from generating unnecessary trace volume.

Filesystem auto-instrumentation is also disabled because it does not contribute useful signal for this laboratory.

## Collector Pipeline

Grafana Alloy acts as the OpenTelemetry collector.

It receives application traces using OTLP over HTTP on port `4318`.

The trace pipeline is:

    otelcol.receiver.otlp "api_traces"
      -> otelcol.processor.batch "api_traces"
      -> otelcol.exporter.otlp "tempo"

Alloy forwards traces to:

    tempo:4317

The Alloy-to-Tempo connection uses OTLP over gRPC inside the local Docker network.

No Docker socket access is required.

## Tempo

Tempo runs as a single local instance for laboratory purposes.

It receives OTLP/gRPC traffic on:

    4317

Its HTTP API is exposed only on localhost:

    127.0.0.1:3200

Trace data is stored in the persistent Docker volume:

    tempo_data

The storage backend is intentionally local.

Tempo usage reporting is disabled.

This architecture is designed for local SRE practice rather than production-scale distributed trace storage.

## W3C Trace Context

The application accepts standard W3C `traceparent` propagation.

A controlled request can therefore provide a known trace ID and remote parent span ID.

The runtime validation performed for Feature #5 demonstrated that:

- the injected trace ID was preserved by the API
- Pino received the active OpenTelemetry context
- the JSON application log contained the same trace ID
- the logged span ID matched the exported server span
- the server span retained the injected remote parent span ID
- Tempo returned the corresponding trace

This establishes exact request, log, span, and trace correlation.

## Log Correlation

OpenTelemetry Pino instrumentation adds these fields to logs produced while a span is active:

    trace_id
    span_id
    trace_flags

Alloy extracts these values and stores them as Loki structured metadata.

They are deliberately not promoted to indexed Loki labels.

That avoids creating high-cardinality label sets while keeping the values queryable during troubleshooting.

Example Loki query by trace ID:

    {service="sre-api"} | trace_id="TRACE_ID"

Example Loki query by span ID:

    {service="sre-api"} | span_id="SPAN_ID"

## Loki to Tempo Navigation

The Loki datasource defines a Grafana derived field named:

    TraceID

It extracts a 32-character hexadecimal trace ID from the JSON log and targets the Tempo datasource.

This allows an operator investigating a log entry to open the corresponding distributed trace.

The datasource UID is stable:

    tempo

## Tempo to Loki Navigation

The Tempo datasource uses `tracesToLogsV2`.

Its Loki datasource target is:

    loki

The custom query is conceptually:

    {service="sre-api"} | trace_id=`TRACE_ID`

A five-minute range is added before and after the selected span to provide troubleshooting context.

This creates bidirectional navigation:

    log -> trace
    trace -> log

## Graceful Shutdown

The OpenTelemetry SDK is shut down during the application shutdown sequence.

This gives the SDK an opportunity to flush pending trace data before the Node.js process exits.

Telemetry shutdown failure is logged and contributes to a non-zero shutdown result rather than being silently ignored.

## Security and Privacy

The tracing implementation follows the same local security boundary as the rest of the laboratory.

It includes:

- no cloud tracing service
- no cloud credentials
- no Docker socket access
- localhost-only Tempo HTTP exposure
- pinned Tempo and Alloy image digests
- non-root containers
- read-only root filesystems where configured
- dropped Linux capabilities
- `no-new-privileges`
- explicit CPU, memory, and PID limits
- disabled Tempo usage reporting
- no trace IDs promoted to high-cardinality Loki labels

Tracing does not override application-level data minimization or log redaction.

## Validation

Tracing configuration is validated by:

    scripts/validate-tracing.sh

The validator checks:

- required tracing files
- Docker Compose parsing
- Tempo configuration validity
- Alloy configuration validity
- required OpenTelemetry dependencies
- application telemetry lifecycle
- ignored health and metrics paths
- Tempo local storage and privacy settings
- API OpenTelemetry environment
- pinned Tempo image
- Tempo container hardening
- Alloy OTLP receiver, processor, and exporter topology
- trace correlation structured metadata
- high-cardinality label guardrails
- Grafana Loki-to-Tempo correlation
- Grafana Tempo-to-Loki correlation
- absence of Docker socket access

GitHub Actions executes the validator in:

    Tracing Configuration Validation

Application tests separately validate telemetry configuration behavior and graceful shutdown behavior.

Feature #5 was also runtime-validated end to end with a controlled W3C trace context across:

    API
      -> Alloy
      -> Tempo
      -> Grafana
      -> Loki

The runtime proof confirmed bidirectional log and trace correlation without recreating unrelated persistent services.

## Scope and Non-Goals

This implementation demonstrates local distributed tracing and telemetry correlation for SRE practice and portfolio purposes.

It does not attempt to provide:

- production Tempo clustering
- distributed object storage
- multi-region tracing
- production retention engineering
- tail-based sampling
- production multi-tenancy
- managed tracing services
- production-scale ingestion

Those concerns remain intentionally outside the current laboratory scope.
