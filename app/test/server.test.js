process.env.LOG_LEVEL = "silent";

const test = require("node:test");
const assert = require("node:assert/strict");
const request = require("supertest");

const { app } = require("../src/app");

test("GET /healthz returns healthy", async () => {
  const response = await request(app)
    .get("/healthz")
    .expect(200);

  assert.equal(response.body.status, "healthy");
});

test("GET /readyz returns ready", async () => {
  const response = await request(app)
    .get("/readyz")
    .expect(200);

  assert.equal(response.body.status, "ready");
});

test("GET /api/work returns a request ID", async () => {
  const response = await request(app)
    .get("/api/work")
    .expect(200);

  assert.equal(response.body.status, "ok");
  assert.ok(response.body.requestId);
  assert.ok(response.headers["x-request-id"]);
});

test("fault endpoints are disabled by default", async () => {
  delete process.env.LAB_FAULTS_ENABLED;

  await request(app)
    .get("/api/error")
    .expect(403);

  await request(app)
    .get("/api/slow?ms=1")
    .expect(403);
});

test("controlled HTTP 500 fault can be enabled", async () => {
  process.env.LAB_FAULTS_ENABLED = "true";

  const response = await request(app)
    .get("/api/error")
    .expect(500);

  assert.equal(
    response.body.error,
    "simulated internal server error"
  );

  delete process.env.LAB_FAULTS_ENABLED;
});

test("controlled latency fault can be enabled", async () => {
  process.env.LAB_FAULTS_ENABLED = "true";

  const response = await request(app)
    .get("/api/slow?ms=10")
    .expect(200);

  assert.equal(response.body.status, "delayed");
  assert.equal(response.body.delayMs, 10);

  delete process.env.LAB_FAULTS_ENABLED;
});

test("GET /metrics exposes Prometheus metrics", async () => {
  const response = await request(app)
    .get("/metrics")
    .expect(200);

  assert.match(
    response.text,
    /sre_lab_http_requests_total/
  );

  assert.match(
    response.headers["content-type"],
    /text\/plain/
  );
});

test("unknown route returns 404", async () => {
  await request(app)
    .get("/does-not-exist")
    .expect(404);
});
