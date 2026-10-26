'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { once } = require('node:events');
const WebSocket = require('ws');

const { createWsFrameGuard } =
  require('../server_ws_frame_guard');

async function runFrame(data, options) {
  const server = new WebSocket.Server({
    host: '127.0.0.1',
    port: 0,
    maxPayload: 1024,
    perMessageDeflate: false,
  });

  let client;

  try {
    if (!server.address()) {
      await once(server, 'listening');
    }

    const result = new Promise((resolve, reject) => {
      server.once('connection', socket => {
        socket.once('message', (frame, isBinary) => {
          try {
            const guard = createWsFrameGuard({
              maxFrameBytes: 1024,
              maxRequests: 10,
            });

            resolve({
              actualBinary: isBinary,
              buffer: Buffer.isBuffer(frame),
              size: frame.length,
              decision: guard.check(
                socket,
                frame,
                isBinary
              ),
            });
          } catch (error) {
            reject(error);
          }
        });
      });
    });

    const port = server.address().port;

    client = new WebSocket(
      `ws://127.0.0.1:${port}`,
      { perMessageDeflate: false }
    );

    await once(client, 'open');
    client.send(data, options);

    return await result;
  } finally {
    if (client) {
      client.terminate();
    }

    for (const socket of server.clients) {
      socket.terminate();
    }

    await new Promise(resolve => server.close(resolve));
  }
}

test('real text frame is received as Buffer', async () => {
  const result = await runFrame(
    JSON.stringify({ type: 'ping', data: {} }),
    { binary: false }
  );

  assert.equal(result.actualBinary, false);
  assert.equal(result.buffer, true);
  assert.equal(result.decision.allowed, true);
});

test('real binary frame has distinct isBinary flag', async () => {
  const result = await runFrame(
    Buffer.from([1, 2, 3]),
    { binary: true }
  );

  assert.equal(result.actualBinary, true);
  assert.equal(result.buffer, true);
  assert.equal(
    result.decision.reason,
    'binary_not_allowed'
  );
});

test('UTF-8 text frame is counted using bytes', async () => {
  const text = 'Привет FENYVO';

  const result = await runFrame(
    text,
    { binary: false }
  );

  assert.equal(result.actualBinary, false);
  assert.equal(
    result.size,
    Buffer.byteLength(text, 'utf8')
  );
  assert.equal(result.decision.allowed, true);
});

test('guard rejects an oversized Buffer independently', () => {
  const guard = createWsFrameGuard({
    maxFrameBytes: 32,
  });

  const result = guard.check(
    {},
    Buffer.alloc(33),
    false
  );

  assert.equal(result.reason, 'frame_too_large');
});