const app = require('./app');

const port = Number(process.env.PORT || 3000);

const server = app.listen(port, '0.0.0.0', () => {
  console.log(
    JSON.stringify({
      event: 'server_started',
      port,
      environment: process.env.APP_ENV || 'local',
      version: process.env.APP_VERSION || 'development',
    }),
  );
});

let isShuttingDown = false;

function shutdown(signal) {
  if (isShuttingDown) {
    return;
  }

  isShuttingDown = true;

  console.log(
    JSON.stringify({
      event: 'shutdown_started',
      signal,
    }),
  );

  server.close((error) => {
    if (error) {
      console.error(
        JSON.stringify({
          event: 'shutdown_failed',
          message: error.message,
        }),
      );

      process.exit(1);
    }

    console.log(
      JSON.stringify({
        event: 'shutdown_completed',
      }),
    );

    process.exit(0);
  });

  setTimeout(() => {
    console.error(
      JSON.stringify({
        event: 'shutdown_timeout',
      }),
    );

    process.exit(1);
  }, 10000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));