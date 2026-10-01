const {
  getNodeAutoInstrumentations,
} = require("@opentelemetry/auto-instrumentations-node");
const {
  OTLPTraceExporter,
} = require("@opentelemetry/exporter-trace-otlp-proto");
const {
  NodeSDK,
} = require("@opentelemetry/sdk-node");

const DEFAULT_SERVICE_NAME = "sre-observability-lab-api";

const IGNORED_INCOMING_PATHS = new Set([
  "/healthz",
  "/readyz",
  "/metrics",
]);

let sdk = null;

function tracingEnabled(env = process.env) {
  return env.OTEL_TRACES_ENABLED === "true";
}

function resolveTelemetryConfig(env = process.env) {
  const enabled = tracingEnabled(env);

  const serviceName =
    (env.OTEL_SERVICE_NAME || DEFAULT_SERVICE_NAME).trim()
    || DEFAULT_SERVICE_NAME;

  if (!enabled) {
    return {
      enabled: false,
      endpoint: "",
      serviceName,
    };
  }

  const endpoint =
    (env.OTEL_EXPORTER_OTLP_TRACES_ENDPOINT || "").trim();

  if (!endpoint) {
    throw new Error(
      "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT is required "
      + "when OTEL_TRACES_ENABLED=true"
    );
  }

  let parsed;

  try {
    parsed = new URL(endpoint);
  } catch {
    throw new Error(
      "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT must be a valid URL"
    );
  }

  if (!["http:", "https:"].includes(parsed.protocol)) {
    throw new Error(
      "OTLP trace endpoint must use http or https"
    );
  }

  if (!parsed.pathname.endsWith("/v1/traces")) {
    throw new Error(
      "OTLP trace endpoint must end with /v1/traces"
    );
  }

  return {
    enabled: true,
    endpoint,
    serviceName,
  };
}

function shouldIgnoreIncomingRequest(request) {
  const rawUrl =
    typeof request?.url === "string"
      ? request.url
      : "";

  const path = rawUrl.split("?", 1)[0];

  return IGNORED_INCOMING_PATHS.has(path);
}

function startTelemetry() {
  const config = resolveTelemetryConfig();

  if (!config.enabled) {
    return false;
  }

  if (sdk) {
    return true;
  }

  if (!process.env.OTEL_SERVICE_NAME?.trim()) {
    process.env.OTEL_SERVICE_NAME = config.serviceName;
  }

  const traceExporter = new OTLPTraceExporter({
    url: config.endpoint,
  });

  sdk = new NodeSDK({
    traceExporter,
    instrumentations: [
      getNodeAutoInstrumentations({
        "@opentelemetry/instrumentation-fs": {
          enabled: false,
        },

        "@opentelemetry/instrumentation-http": {
          ignoreIncomingRequestHook:
            shouldIgnoreIncomingRequest,
        },
      }),
    ],
  });

  sdk.start();

  return true;
}

async function shutdownTelemetry() {
  if (!sdk) {
    return;
  }

  const activeSdk = sdk;
  sdk = null;

  await activeSdk.shutdown();
}

module.exports = {
  DEFAULT_SERVICE_NAME,
  resolveTelemetryConfig,
  shouldIgnoreIncomingRequest,
  shutdownTelemetry,
  startTelemetry,
  tracingEnabled,
};
