# Security Policy

## Scope

This repository is a portfolio and engineering demonstration project for SRE,
observability, telemetry, monitoring, logging, and distributed tracing
practices.

Security issues relevant to this repository may include:

- accidentally committed credentials or secrets;
- sensitive information recorded in metrics, logs, or traces;
- authentication tokens, cookies, API keys, or authorization headers exposed
  through telemetry;
- insecure Prometheus, Grafana, Loki, Tempo, or Grafana Alloy configuration;
- unintended external exposure of observability services or telemetry
  endpoints;
- unsafe Docker or container configuration;
- Docker socket access introduced into observability components;
- insecure OpenTelemetry collector or exporter configuration;
- unbounded or unsafe telemetry cardinality;
- insecure CI/CD configuration;
- unintended privilege escalation;
- security-sensitive documentation errors.

## Reporting a security issue

Do not publish credentials, secrets, tokens, private keys, sensitive telemetry,
or other confidential information in a public issue.

When private vulnerability reporting is available through GitHub, use that
mechanism.

Otherwise, contact the repository owner privately before disclosing sensitive
details publicly.

## Credentials and secrets

This repository must not contain:

- passwords or API tokens intended for real environments;
- cloud access credentials;
- private SSH or TLS keys;
- production credentials;
- real customer data;
- employer confidential information;
- authentication cookies or authorization tokens;
- telemetry containing credentials or secret values.

Real credentials must not be introduced solely to simplify local testing or
observability configuration.

## Telemetry privacy

Metrics, logs, and traces must be treated as potentially sensitive operational
data.

Sensitive HTTP headers should be redacted before log storage.

Credentials, authentication tokens, cookies, private keys, and other secret
values must not be intentionally recorded in logs or traces.

Telemetry attributes and labels should be limited to information required for
the engineering purpose of the laboratory.

High-cardinality values should not be promoted to persistent metric or log
labels without an explicit technical reason.

## Observability and runtime changes

Changes to application instrumentation, Docker Compose configuration,
Prometheus, Grafana, Loki, Tempo, Grafana Alloy, OpenTelemetry configuration,
container configuration, and repository security controls should be reviewed
and validated before merge.

Observability components should not receive Docker socket access unless a
future requirement is explicitly reviewed and justified.

Changes that expose local observability services, telemetry receivers, or
administrative interfaces beyond their intended environment require explicit
security review.

Automated validation should be used where applicable before changes reach the
maintained branch.

## Security findings

Security findings produced by automated validation or security tooling should
be reviewed individually.

Suppressions or exceptions should include a documented technical justification
rather than disabling security controls globally.

If a credential or sensitive value is accidentally exposed, revoking or
rotating it is required; removing it from the repository alone is not
considered sufficient remediation.

If sensitive telemetry is unintentionally collected, the source of collection
should be corrected in addition to removing or expiring the affected local
telemetry data where applicable.

## Supported versions

This repository represents an actively developed portfolio project rather than
a versioned production software product.

Only the current `main` branch is considered maintained.
