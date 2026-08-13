const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');

const app = require('../src/app');

test('GET /status retorna HTTP 200 e status ok', async () => {
  const server = app.listen(0, '127.0.0.1');

  await once(server, 'listening');

  try {
    const address = server.address();
    const response = await fetch(
      `http://127.0.0.1:${address.port}/status`,
    );

    assert.equal(response.status, 200);

    const body = await response.json();

    assert.equal(body.status, 'ok');
    assert.equal(body.environment, 'local');
    assert.equal(body.version, 'development');
    assert.equal(typeof body.timestamp, 'string');
    assert.equal(typeof body.uptimeSeconds, 'number');
  } finally {
    await new Promise((resolve, reject) => {
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }

        resolve();
      });
    });
  }
});

test('rota inexistente retorna HTTP 404', async () => {
  const server = app.listen(0, '127.0.0.1');

  await once(server, 'listening');

  try {
    const address = server.address();
    const response = await fetch(
      `http://127.0.0.1:${address.port}/rota-inexistente`,
    );

    assert.equal(response.status, 404);

    const body = await response.json();

    assert.equal(body.error, 'not_found');
  } finally {
    await new Promise((resolve, reject) => {
      server.close((error) => {
        if (error) {
          reject(error);
          return;
        }

        resolve();
      });
    });
  }
});