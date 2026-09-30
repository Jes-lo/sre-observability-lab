# Grafana Dashboard Validation

## Purpose

This document describes the Grafana visualization layer of the
SRE & Observability Lab.

Grafana is fully provisioned from version-controlled files. No manual
dashboard or datasource creation is required.

## Prometheus Datasource

The Prometheus datasource is provisioned with the stable UID:

    prometheus

Grafana connects to Prometheus over the Docker network:

    http://prometheus:9090

The datasource is configured as the default datasource and is not
editable through the Grafana UI.

## Dashboard Provisioning

The dashboard provider loads dashboards from:

    /etc/grafana/dashboards

Provisioned dashboards are placed in:

    SRE Lab

The initial dashboard has the stable UID:

    sre-red-overview

and the title:

    SRE Lab - RED Overview

## RED Panels

The dashboard contains four panels:

1. Request Rate
2. HTTP 5xx Error Ratio
3. HTTP 5xx Rate
4. P95 Request Latency

The panels consume the Prometheus recording rules:

    sre_api:http_requests:rate1m
    sre_api:http_error_ratio:rate1m
    sre_api:http_5xx:rate1m
    sre_api:http_request_duration_seconds:p95_1m

This keeps dashboard queries simple and moves reusable RED calculations
into Prometheus.

## Local Access

Grafana is published only on the loopback interface:

    http://127.0.0.1:3001

The service is not intentionally exposed on all host interfaces.

Anonymous access is enabled with the Viewer role for this local lab so
the repository does not require a committed administrator password.

This configuration is intended for local development and demonstration,
not public Internet exposure.

## Runtime Security

The Grafana container is configured with:

- non-root process execution
- read-only root filesystem
- all Linux capabilities dropped
- no-new-privileges
- CPU limit
- memory limit
- PID limit
- dedicated persistent data volume
- localhost-only published port

Grafana state is stored in:

    sre-observability-lab_grafana_data

## Deterministic Plugin Behavior

The Grafana container image is pinned by immutable SHA-256 digest.

Runtime plugin auto-updates are disabled so the software executed by
the lab remains consistent with the digest-pinned image.

The configuration disables:

- automatic updates of preinstalled plugins
- plugin administration through the UI
- Grafana update checks
- plugin update checks
- anonymous usage reporting

This also allows the container root filesystem to remain read-only
without Grafana attempting to replace bundled datasource plugins at
runtime.

## Validation

Run:

    ./scripts/validate-grafana.sh

The validation confirms:

- Docker Compose syntax
- dashboard JSON structure
- expected PromQL expressions
- provisioning files
- Grafana HTTP health
- Docker healthcheck
- Prometheus datasource provisioning
- dashboard provisioning
- Grafana-to-Prometheus connectivity
- non-root execution
- runtime hardening
- localhost-only exposure

## CI

GitHub Actions executes Grafana validation automatically for pull
requests and changes merged to main.

The Grafana integration validation starts the observability stack only
when necessary and removes containers without deleting persistent
volumes.
