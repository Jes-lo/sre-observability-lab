# Incident Response

## Purpose

This document defines the incident-response workflow for the local
SRE & Observability Lab.

The workflow is designed for reproducible laboratory exercises.
It is not an organization-wide production incident-management policy.

## Incident Lifecycle

The laboratory incident lifecycle is:

    Detect
      |
      v
    Triage
      |
      v
    Investigate
      |
      v
    Mitigate
      |
      v
    Recover
      |
      v
    Verify
      |
      v
    Review

An incident is not considered complete until service recovery has
been verified and relevant evidence has been recorded.

## Detection Sources

Current detection signals include:

- Prometheus symptom alerts
- SLO and error-budget burn-rate alerts
- Grafana dashboards
- application metrics
- centralized logs in Loki
- distributed traces in Tempo
- controlled k6 scenarios

## Current Alert Classes

Availability-related alerts:

- `SreApiHigh5xxRatio`
- `SreApiAvailabilityBurnRateFast`
- `SreApiAvailabilityBurnRateSlow`

Latency-related alerts:

- `SreApiHighLatencyRatio`
- `SreApiLatencyBurnRateFast`
- `SreApiLatencyBurnRateSlow`

## Severity

The laboratory currently uses two alert severities:

### Critical

Represents rapid error-budget consumption that requires immediate
investigation during the exercise.

### Warning

Represents a service symptom or sustained error-budget consumption
that should be investigated before it develops further.

These local severities are intentionally scoped to the laboratory and
must not be interpreted as production severity standards.

## Roles

A laboratory exercise may be performed by one person, but the
following logical responsibilities should still be identified:

- incident coordinator
- investigator
- communications recorder
- evidence recorder

One person may perform all four roles.

## Triage

Initial triage should establish:

1. which alert fired;
2. which SLO is affected;
3. whether the symptom is availability or latency;
4. whether the problem is still active;
5. which routes are affected;
6. whether logs or traces provide additional evidence.

## Investigation Order

Use evidence in this order when practical:

1. active alert and labels;
2. SLO and burn-rate metrics;
3. RED metrics;
4. application logs;
5. distributed traces;
6. recent controlled workload or fault scenario.

Avoid changing the service before enough evidence has been collected
to understand the symptom.

## Mitigation

Mitigation should:

- stop or reduce the controlled fault source;
- avoid destructive actions;
- avoid modifying unrelated services;
- preserve useful evidence;
- keep fault injection disabled on the primary API unless an isolated
  exercise explicitly requires otherwise.

## Recovery

Recovery requires more than stopping the fault.

Verify:

- the affected endpoint returns its expected response;
- request error or latency symptoms return to normal;
- relevant alert conditions stop firing after their configured
  evaluation periods;
- the primary API returns to its safe fault-disabled state;
- no temporary incident-exercise runtime remains.

## Evidence

Useful evidence may include:

- alert name
- severity
- SLO
- timestamps
- PromQL result
- request status
- request duration
- relevant log event
- trace ID
- mitigation performed
- recovery verification

Do not record secrets, tokens, credentials, personal data, or
unrelated production information.

## Reproducible Incident Exercises

The repository includes an isolated incident exercise runner:

    scripts/run-incident-exercise.sh

Availability exercise:

    ./scripts/run-incident-exercise.sh availability

Latency exercise:

    ./scripts/run-incident-exercise.sh latency

Each exercise:

- builds the API from the current repository source;
- creates a uniquely named temporary Docker network;
- starts a temporary fault-enabled API;
- starts temporary Prometheus and Alertmanager instances;
- uses dynamically assigned localhost ports;
- generates a healthy baseline;
- introduces only the selected controlled incident;
- waits for the expected real alert rules to reach `firing`;
- validates Alertmanager severity routing;
- stops the controlled fault source;
- generates recovery traffic;
- requires the affected bad-event ratio to decrease;
- verifies a healthy HTTP 200 response;
- removes its temporary runtime and exercise image.

The runner does not require the primary observability stack to be
running.

If a primary stack is already running, the runner records its container
IDs and verifies that they remain unchanged.

Example evidence from validated runs is documented in:

    docs/postmortems/example-availability-exercise.md
    docs/postmortems/example-latency-exercise.md

Observed metric values are evidence from those specific runs and are
not fixed acceptance constants for future executions.

## Postmortem

A completed exercise should use:

    docs/postmortems/template.md

The postmortem is blameless and focuses on:

- what happened
- impact
- detection
- timeline
- contributing factors
- response
- recovery
- lessons
- follow-up actions

## Scope

This workflow does not provide:

- production paging
- organizational escalation policy
- customer communications
- legal or regulatory incident handling
- security-incident forensics
- production incident severity definitions
