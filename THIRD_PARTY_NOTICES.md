# Third-Party Notices

This project uses third-party software, libraries, container images, tools,
and services as part of its development, validation, and local runtime
environment.

Third-party components remain subject to their respective copyrights,
licenses, terms, trademark rights, and other applicable intellectual-property
rights.

## Components Currently Used

| Component | Version / Reference | Project Use | License / Terms |
|---|---|---|---|
| Prometheus | `sha256:6976aa8a60fec930796ce5772b8d12da7a318a5daa8d40d69c5c7819a05eeed7` | Metrics collection, storage, rules, and queries | Apache-2.0 |
| Prometheus Alertmanager | `v0.34.1`, `prom/alertmanager@sha256:e9733bafb1bdef9b00e25a21f8f99dc26a22224bf16641ad754d1649f4c3357a` | Alert grouping, routing, silencing, and local alert inspection | Apache-2.0 |
| Grafana k6 | `v2.3.0`, `grafana/k6@sha256:9c2dee7f8ed74d317e4027c06a10f169b625638189de8d4555d0b3486a5aeb34` | Controlled local load and fault-scenario generation | AGPL-3.0 |
| Grafana | `sha256:b28bae15e219c998fb0e0424ed724930cc61b1f61fb404d47c862f9a23f9e572` | Dashboards and observability correlation | AGPL-3.0-only by default; see upstream licensing for exceptions |
| Grafana Loki | `sha256:1107dd5274e0ada47e42472b7a7e71f3b2a2fe878878108f3e2f9e51528f0193` | Centralized log storage and queries | AGPL-3.0-only by default; see upstream licensing for exceptions |
| Grafana Tempo | `sha256:0296560ac66f8a3600d7fb3014a52c189d4d9c3549ad6ff441bf2409855d68d5` | Distributed trace storage and queries | AGPL-3.0-only by default; see upstream licensing for exceptions |
| Grafana Alloy | `sha256:2aa2099af76c0098d4af7a4d6e48f86cb66dc1a000222ad927a1c67c6542d13f` | Telemetry collection and routing | Apache-2.0 by default |
| Node.js Docker image | `sha256:0e0ff40c39bc087845bfb27465a0df4ea419520094bc35842ff83dd8cbe6f9b6` | Application build and runtime base image | Node.js Docker project: MIT; software contained in the image remains subject to its own licenses |
| `@opentelemetry/api` | 1.9.1 | OpenTelemetry API | Apache-2.0 |
| `@opentelemetry/auto-instrumentations-node` | 0.80.0 | Node.js automatic tracing instrumentation | Apache-2.0 |
| `@opentelemetry/exporter-trace-otlp-proto` | 0.222.0 | OTLP trace export | Apache-2.0 |
| `@opentelemetry/sdk-node` | 0.222.0 | Node.js OpenTelemetry SDK | Apache-2.0 |
| `@prometheus-io/client` | 0.16.1 | Application metrics instrumentation | Apache-2.0 |
| Express | 5.2.1 | Demo API framework | MIT |
| Pino | 10.3.1 | Structured application logging | MIT |
| `pino-http` | 11.0.0 | HTTP request logging | MIT |
| Supertest | 7.3.0 | Application API testing | MIT |
| `actions/checkout` | v7.0.1, commit-SHA pinned | GitHub Actions repository checkout | MIT |
| `actions/setup-node` | v7.0.0, commit-SHA pinned | Node.js setup in CI | MIT |

Container images may include operating-system packages and other bundled
software governed by additional licenses. The references above identify the
third-party projects and immutable image references used directly by this
repository; software included within those images remains subject to its own
applicable licenses and notices.

Transitive npm dependencies recorded in `app/package-lock.json` remain subject
to their respective licenses and terms.

## External Services and Tooling

Docker and Docker Compose are used as external local development and runtime
tooling and remain subject to their applicable licenses and terms.

GitHub and GitHub Actions are used for source hosting, pull requests, and
continuous validation and remain subject to GitHub's applicable terms and
policies.

## Repository-Owned Material

Repository-specific application source code, Docker Compose configuration,
observability configuration, Prometheus rules, Grafana dashboards and
provisioning, Alloy configuration, Loki configuration, Tempo configuration,
automation, validation scripts, documentation, tests, diagrams, and
integrations are created specifically for this portfolio project unless
otherwise identified as third-party material.

The repository does not claim ownership of Prometheus, Alertmanager, Grafana,
Loki, Tempo, Grafana Alloy, k6, OpenTelemetry, Node.js, Docker,
GitHub Actions, or any other
third-party technology used by the project.

Third-party names and trademarks are used only for identification,
interoperability, documentation, and description of the technologies used.

## Third-Party Source Code

No third-party source code is intentionally copied or vendored into this
repository unless explicitly documented.

Dependencies installed through package managers, container images, GitHub
Actions, and other externally distributed artifacts remain subject to their
original licenses and terms.

## Maintenance

Additional third-party components will be documented here when they are
actually introduced into the project.
