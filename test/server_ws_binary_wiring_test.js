'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'server.js'),
  'utf8'
);

const { createWsFrameGuard } =
  require('../server_ws_frame_guard');

test('WebSocket handler receives real isBinary flag', () => {
  assert.match(
    source,
    /ws\.on\(\s*'message',\s*async\s*\(\s*rawMessage,\s*isBinary,/
  );
});

test('guard receives actual WebSocket frame type', () => {
  assert.match(
    source,
    /wsFrameGuard\.check\(ws,\s*rawMessage,\s*isBinary\)/
  );

  assert.doesNotMatch(
    source,
    /wsFrameGuard\.check\(ws,\s*rawMessage,\s*false\)/
  );
});

test('binary frames are rejected by integrated guard', () => {
  const guard = createWsFrameGuard({
    maxFrameBytes: 16 * 1024 * 1024,
    maxRequests: Number.MAX_SAFE_INTEGER,
    windowMs: 60000,
  });

  const decision = guard.check(
    {},
    Buffer.from([1, 2, 3]),
    true
  );

  assert.deepEqual(decision, {
    allowed: false,
    reason: 'binary_not_allowed',
  });
});

test('text JSON frames remain accepted', () => {
  const guard = createWsFrameGuard({
    maxFrameBytes: 16 * 1024 * 1024,
    maxRequests: Number.MAX_SAFE_INTEGER,
    windowMs: 60000,
  });

  const decision = guard.check(
    {},
    Buffer.from('{"type":"ping","data":{}}'),
    false
  );

  assert.equal(decision.allowed, true);
});

test('existing size and rate limits remain present', () => {
  assert.match(
    source,
    /maxPayload:\s*16\s*\*\s*1024\s*\*\s*1024/
  );

  assert.match(
    source,
    /connectionMessageRateLimiter\.consume\('messages'\)/
  );

  assert.match(
    source,
    /MESSAGE_IP_RATE_LIMITER\.consume\(clientAddress\)/
  );
});