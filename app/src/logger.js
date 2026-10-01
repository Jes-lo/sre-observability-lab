const pino = require("pino");

const REDACTED = "[Redacted]";

const SENSITIVE_HEADER_NAMES = new Set([
  "authorization",
  "cookie",
  "set-cookie",
  "proxy-authorization",
  "x-api-key",
  "x-auth-token",
  "x-access-token",
  "x-amz-security-token",
]);

const REDACT_PATHS = [
  "req.headers.authorization",
  "req.headers.cookie",
  'req.headers["set-cookie"]',
  'req.headers["proxy-authorization"]',
  'req.headers["x-api-key"]',
  'req.headers["x-auth-token"]',
  'req.headers["x-access-token"]',
  'req.headers["x-amz-security-token"]',

  "res.headers.authorization",
  "res.headers.cookie",
  'res.headers["set-cookie"]',
  'res.headers["proxy-authorization"]',
  'res.headers["x-api-key"]',
  'res.headers["x-auth-token"]',
  'res.headers["x-access-token"]',
  'res.headers["x-amz-security-token"]',

  "headers.authorization",
  "headers.cookie",
  'headers["set-cookie"]',
  'headers["proxy-authorization"]',
  'headers["x-api-key"]',
  'headers["x-auth-token"]',
  'headers["x-access-token"]',
  'headers["x-amz-security-token"]',
];

function redactHeaders(headers = {}) {
  const result = {};

  for (const [name, value] of Object.entries(headers)) {
    result[name] = SENSITIVE_HEADER_NAMES.has(name.toLowerCase())
      ? REDACTED
      : value;
  }

  return result;
}

function createLogger({
  level = process.env.LOG_LEVEL || "info",
  logFilePath = process.env.LOG_FILE_PATH || "",
  fileSync = false,
  stdout = true,
} = {}) {
  const loggerOptions = {
    level,
    redact: {
      paths: REDACT_PATHS,
      censor: REDACTED,
    },
  };

  if (!logFilePath) {
    return pino(loggerOptions);
  }

  const streams = [];

  if (stdout) {
    streams.push({
      stream: process.stdout,
    });
  }

  streams.push({
    stream: pino.destination({
      dest: logFilePath,
      sync: fileSync,
    }),
  });

  return pino(
    loggerOptions,
    pino.multistream(streams)
  );
}

const logger = createLogger();

module.exports = {
  REDACTED,
  createLogger,
  logger,
  redactHeaders,
};
