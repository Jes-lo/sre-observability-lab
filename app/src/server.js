const { app } = require("./app");
const { logger } = require("./logger");

const port = Number.parseInt(process.env.PORT || "3000", 10);
const host = process.env.HOST || "0.0.0.0";

const server = app.listen(port, host, () => {
  logger.info(
    {
      event: "server_started",
      host,
      port,
    },
    "Server started"
  );
});

let shuttingDown = false;

function flushAndExit(code) {
  try {
    logger.flush((error) => {
      if (error) {
        process.stderr.write(
          JSON.stringify({
            level: "error",
            event: "logger_flush_failed",
            error: error.message,
          }) + "\n"
        );

        process.exit(1);
      }

      process.exit(code);
    });
  } catch (error) {
    process.stderr.write(
      JSON.stringify({
        level: "error",
        event: "logger_flush_failed",
        error: error.message,
      }) + "\n"
    );

    process.exit(1);
  }
}

function shutdown(signal) {
  if (shuttingDown) {
    return;
  }

  shuttingDown = true;

  logger.info(
    {
      event: "shutdown_requested",
      signal,
    },
    "Shutdown requested"
  );

  server.close((error) => {
    if (error) {
      logger.error(
        {
          event: "shutdown_failed",
          err: error,
        },
        "Server shutdown failed"
      );

      flushAndExit(1);
      return;
    }

    logger.info(
      {
        event: "server_stopped",
      },
      "Server stopped"
    );

    flushAndExit(0);
  });
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
