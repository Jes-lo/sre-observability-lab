const { app } = require("./app");

const port = Number.parseInt(process.env.PORT || "3000", 10);
const host = process.env.HOST || "0.0.0.0";

const server = app.listen(port, host, () => {
  console.log(
    JSON.stringify({
      level: "info",
      event: "server_started",
      host,
      port,
    })
  );
});

function shutdown(signal) {
  console.log(
    JSON.stringify({
      level: "info",
      event: "shutdown_requested",
      signal,
    })
  );

  server.close((error) => {
    if (error) {
      console.error(
        JSON.stringify({
          level: "error",
          event: "shutdown_failed",
          error: error.message,
        })
      );

      process.exit(1);
    }

    console.log(
      JSON.stringify({
        level: "info",
        event: "server_stopped",
      })
    );

    process.exit(0);
  });
}

process.on("SIGTERM", () => shutdown("SIGTERM"));
process.on("SIGINT", () => shutdown("SIGINT"));
