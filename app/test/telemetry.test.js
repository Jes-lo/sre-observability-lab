const assert = require("node:assert/strict");
const test = require("node:test");

const {
  DEFAULT_SERVICE_NAME,
  resolveTelemetryConfig,
  shouldIgnoreIncomingRequest,
  tracingEnabled,
} = require("../src/telemetry");

test(
  "tracing is disabled unless explicitly enabled",
  () => {
    assert.equal(
      tracingEnabled({}),
      false
    );

    assert.equal(
      tracingEnabled({
        OTEL_TRACES_ENABLED: "false",
      }),
      false
    );

    assert.equal(
      tracingEnabled({
        OTEL_TRACES_ENABLED: "true",
      }),
      true
    );
  }
);

test(
  "disabled tracing does not require an OTLP endpoint",
  () => {
    assert.deepEqual(
      resolveTelemetryConfig({}),
      {
        enabled: false,
        endpoint: "",
        serviceName: DEFAULT_SERVICE_NAME,
      }
    );
  }
);

test(
  "enabled tracing requires an OTLP traces endpoint",
  () => {
    assert.throws(
      () => {
        resolveTelemetryConfig({
          OTEL_TRACES_ENABLED: "true",
        });
      },
      /OTEL_EXPORTER_OTLP_TRACES_ENDPOINT/
    );
  }
);

test(
  "enabled tracing accepts the Alloy OTLP HTTP endpoint",
  () => {
    assert.deepEqual(
      resolveTelemetryConfig({
        OTEL_TRACES_ENABLED: "true",
        OTEL_SERVICE_NAME:
          "sre-observability-lab-api",
        OTEL_EXPORTER_OTLP_TRACES_ENDPOINT:
          "http://alloy:4318/v1/traces",
      }),
      {
        enabled: true,
        endpoint:
          "http://alloy:4318/v1/traces",
        serviceName:
          "sre-observability-lab-api",
      }
    );
  }
);

test(
  "OTLP endpoint must use HTTP and end in /v1/traces",
  () => {
    assert.throws(
      () => {
        resolveTelemetryConfig({
          OTEL_TRACES_ENABLED: "true",
          OTEL_EXPORTER_OTLP_TRACES_ENDPOINT:
            "grpc://alloy:4317",
        });
      },
      /http or https/
    );

    assert.throws(
      () => {
        resolveTelemetryConfig({
          OTEL_TRACES_ENABLED: "true",
          OTEL_EXPORTER_OTLP_TRACES_ENDPOINT:
            "http://alloy:4318",
        });
      },
      /\/v1\/traces/
    );
  }
);

test(
  "health and metrics endpoints are excluded from tracing",
  () => {
    assert.equal(
      shouldIgnoreIncomingRequest({
        url: "/healthz",
      }),
      true
    );

    assert.equal(
      shouldIgnoreIncomingRequest({
        url: "/readyz?probe=1",
      }),
      true
    );

    assert.equal(
      shouldIgnoreIncomingRequest({
        url: "/metrics",
      }),
      true
    );

    assert.equal(
      shouldIgnoreIncomingRequest({
        url: "/api/work",
      }),
      false
    );
  }
);
