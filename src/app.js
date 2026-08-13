const express = require('express');
const helmet = require('helmet');

const app = express();

app.disable('x-powered-by');

app.use(helmet());

app.use(
  express.json({
    limit: '10kb',
  }),
);

app.get('/', (request, response) => {
  response.status(200).json({
    message: 'Lacrei Saúde DevOps Challenge API',
  });
});

app.get('/status', (request, response) => {
  response.status(200).json({
    status: 'ok',
    environment: process.env.APP_ENV || 'local',
    version: process.env.APP_VERSION || 'development',
    uptimeSeconds: Math.floor(process.uptime()),
    timestamp: new Date().toISOString(),
  });
});

app.use((request, response) => {
  response.status(404).json({
    error: 'not_found',
  });
});

module.exports = app;