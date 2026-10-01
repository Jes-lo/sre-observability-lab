const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const test = require("node:test");
const assert = require("node:assert/strict");

const {
  REDACTED,
  createLogger,
  redactHeaders,
} = require("../src/logger");

test("sensitive HTTP headers are redacted case-insensitively", () => {
  const headers = redactHeaders({
    Authorization: "Bearer top-secret-token",
    COOKIE: "session=top-secret-cookie",
    "Proxy-Authorization": "Basic top-secret-proxy",
    "X-API-Key": "top-secret-api-key",
    "X-Auth-Token": "top-secret-auth-token",
    "X-Access-Token": "top-secret-access-token",
    "X-Amz-Security-Token": "top-secret-aws-token",
    "content-type": "application/json",
  });

  assert.equal(headers.Authorization, REDACTED);
  assert.equal(headers.COOKIE, REDACTED);
  assert.equal(headers["Proxy-Authorization"], REDACTED);
  assert.equal(headers["X-API-Key"], REDACTED);
  assert.equal(headers["X-Auth-Token"], REDACTED);
  assert.equal(headers["X-Access-Token"], REDACTED);
  assert.equal(headers["X-Amz-Security-Token"], REDACTED);

  assert.equal(
    headers["content-type"],
    "application/json"
  );
});

test("Pino file output does not persist sensitive header values", () => {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), "sre-logger-")
  );

  const logfile = path.join(
    directory,
    "api.log"
  );

  try {
    const logger = createLogger({
      level: "info",
      logFilePath: logfile,
      fileSync: true,
      stdout: false,
    });

    logger.info(
      {
        req: {
          headers: {
            authorization: "Bearer secret-a",
            cookie: "session=secret-b",
            "proxy-authorization": "Basic secret-c",
            "x-api-key": "secret-d",
            "x-auth-token": "secret-e",
            "x-access-token": "secret-f",
            "x-amz-security-token": "secret-g",
            "content-type": "application/json",
          },
        },
      },
      "logger redaction test"
    );

    const output = fs.readFileSync(
      logfile,
      "utf8"
    );

    assert.doesNotMatch(
      output,
      /secret-a|secret-b|secret-c|secret-d|secret-e|secret-f|secret-g/
    );

    assert.match(
      output,
      /\[Redacted\]/
    );

    assert.match(
      output,
      /application\/json/
    );
  } finally {
    fs.rmSync(
      directory,
      {
        recursive: true,
        force: true,
      }
    );
  }
});
