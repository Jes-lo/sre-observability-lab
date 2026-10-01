const crypto = require("node:crypto");
const express = require("express");
const pinoHttp = require("pino-http");
const client = require("@prometheus-io/client");
const { logger, redactHeaders } = require("./logger");

const app = express();

const registry = new client.Registry();

client.collectDefaultMetrics({
  register: registry,
  prefix: "sre_lab_",
});

const httpRequestsTotal = new client.Counter({
  name: "sre_lab_http_requests_total",
  help: "Total number of HTTP requests",
  labelNames: ["method", "route", "status_code"],
  registers: [registry],
});

const httpRequestDuration = new client.Histogram({
  name: "sre_lab_http_request_duration_seconds",
  help: "HTTP request duration in seconds",
  labelNames: ["method", "route", "status_code"],
  buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5],
  registers: [registry],
});

const faultRequestsTotal = new client.Counter({
  name: "sre_lab_fault_requests_total",
  help: "Total requests to controlled fault-injection endpoints",
  labelNames: ["fault_type"],
  registers: [registry],
});

app.disable("x-powered-by");
app.use(express.json({ limit: "32kb" }));

app.use(
  pinoHttp({
    logger,
    serializers: {
      req(req) {
        if (req.headers) {
          req.headers = redactHeaders(req.headers);
        }

        return req;
      },
      res(res) {
        if (res.headers) {
          res.headers = redactHeaders(res.headers);
        }

        return res;
      },
    },
    genReqId(req, res) {
      const supplied = req.headers["x-request-id"];

      const requestId =
        typeof supplied === "string" && supplied.length <= 128
          ? supplied
          : crypto.randomUUID();

      res.setHeader("x-request-id", requestId);
      return requestId;
    },
  })
);

app.use((req, res, next) => {
  const start = process.hrtime.bigint();

  res.on("finish", () => {
    const elapsed = Number(process.hrtime.bigint() - start) / 1e9;
    const route = req.route?.path || "unmatched";
    const statusCode = String(res.statusCode);

    httpRequestsTotal.inc({
      method: req.method,
      route,
      status_code: statusCode,
    });

    httpRequestDuration.observe(
      {
        method: req.method,
        route,
        status_code: statusCode,
      },
      elapsed
    );
  });

  next();
});

function faultsEnabled() {
  return process.env.LAB_FAULTS_ENABLED === "true";
}

app.get("/", (req, res) => {
  res.json({
    service: "sre-observability-lab-api",
    status: "ok",
  });
});

app.get("/healthz", (req, res) => {
  res.status(200).json({
    status: "healthy",
  });
});

app.get("/readyz", (req, res) => {
  res.status(200).json({
    status: "ready",
  });
});

app.get("/api/work", (req, res) => {
  res.status(200).json({
    status: "ok",
    requestId: req.id,
  });
});

app.get("/api/slow", async (req, res) => {
  if (!faultsEnabled()) {
    return res.status(403).json({
      error: "fault injection disabled",
    });
  }

  const requested = Number.parseInt(req.query.ms, 10);
  const delayMs = Number.isFinite(requested)
    ? Math.min(Math.max(requested, 0), 5000)
    : 1000;

  faultRequestsTotal.inc({
    fault_type: "latency",
  });

  await new Promise((resolve) => setTimeout(resolve, delayMs));

  return res.status(200).json({
    status: "delayed",
    delayMs,
    requestId: req.id,
  });
});

app.get("/api/error", (req, res) => {
  if (!faultsEnabled()) {
    return res.status(403).json({
      error: "fault injection disabled",
    });
  }

  faultRequestsTotal.inc({
    fault_type: "http_500",
  });

  return res.status(500).json({
    error: "simulated internal server error",
    requestId: req.id,
  });
});

app.get("/metrics", async (req, res, next) => {
  try {
    res.setHeader("Content-Type", registry.contentType);
    res.status(200).send(await registry.metrics());
  } catch (error) {
    next(error);
  }
});

app.use((req, res) => {
  res.status(404).json({
    error: "not found",
  });
});

app.use((error, req, res, next) => {
  req.log.error(
    {
      err: error,
      requestId: req.id,
    },
    "Unhandled request error"
  );

  res.status(500).json({
    error: "internal server error",
    requestId: req.id,
  });
});

module.exports = {
  app,
  registry,
};
