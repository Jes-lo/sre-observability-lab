# Prometheus Monitoring Validation

## Purpose

This document describes how the SRE & Observability Lab validates its
Prometheus-based monitoring layer.

The monitoring stack currently provides:

- Prometheus metrics collection
- API and Prometheus target health validation
- RED service metrics
- Prometheus recording rules
- persistent local time-series storage
- local-only service exposure
- hardened container runtime settings
- automated Prometheus configuration validation in CI

## Monitored Service

The instrumented API exposes Prometheus metrics at `/metrics`.

Prometheus scrapes the service using the internal Docker DNS name:

    api:3000

Prometheus also scrapes itself:

    prometheus:9090

## RED Metrics

The service exposes the following primary metrics:

    sre_lab_http_requests_total
    sre_lab_http_request_duration_seconds

These metrics provide the basis for the RED method:

- Rate — request throughput
- Errors — HTTP 5xx activity and error ratio
- Duration — request latency

## Recording Rules

Prometheus evaluates the following recording rules:

    sre_api:http_requests:rate1m
    sre_api:http_5xx:rate1m
    sre_api:http_error_ratio:rate1m
    sre_api:http_request_duration_seconds:p95_1m

### Request Rate

Represents total API request throughput over a one-minute rate window.

Expression:

    sum(
      rate(
        sre_lab_http_requests_total{
          job="sre-observability-api"
        }[1m]
      )
    )

### HTTP 5xx Rate

Represents the rate of server-side HTTP errors.

Expression:

    sum(
      rate(
        sre_lab_http_requests_total{
          job="sre-observability-api",
          status_code=~"5.."
        }[1m]
      )
    )
    or vector(0)

The zero fallback makes the recording rule available even when no 5xx
series currently exists.

### HTTP Error Ratio

Represents HTTP 5xx traffic as a fraction of total request traffic.

The denominator is protected with `clamp_min` to avoid division by zero.

### P95 Request Duration

Calculates the 95th percentile request latency from the Prometheus
histogram buckets.

Expression:

    histogram_quantile(
      0.95,
      sum by (le) (
        rate(
          sre_lab_http_request_duration_seconds_bucket{
            job="sre-observability-api"
          }[1m]
        )
      )
    )

## Local Security Boundary

Published ports are bound only to loopback:

    127.0.0.1:3000 -> API
    127.0.0.1:9090 -> Prometheus

This allows local browser and CLI access without exposing the services
on all host interfaces.

Container runtime controls include:

- non-root execution
- read-only root filesystem
- all Linux capabilities dropped
- `no-new-privileges`
- CPU limits
- memory limits
- PID limits

## Persistence

Prometheus time-series data is stored in the dedicated Docker volume:

    sre-observability-lab_prometheus_data

Stopping the stack with:

    docker compose down

preserves the volume.

Do not use:

    docker compose down -v

unless intentional deletion of monitoring data is required.

## Static Validation

Run:

    ./scripts/validate-prometheus.sh

The validation checks:

1. `prometheus.yml` with `promtool`
2. recording rules with `promtool`
3. Docker Compose configuration

## Runtime Validation

A valid running environment should report both targets as healthy:

    job=prometheus health=up
    job=sre-observability-api health=up

The four recording rules should report:

    health=ok

## CI

GitHub Actions runs a dedicated job:

    Prometheus Configuration Validation

The job validates the Prometheus configuration, recording rules, and
Docker Compose model before changes can be accepted.

GitHub Actions runners are explicitly pinned to:

    ubuntu-24.04

Actions are referenced by full commit SHA.
