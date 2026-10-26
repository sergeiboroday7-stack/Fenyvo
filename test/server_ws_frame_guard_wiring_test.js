'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'server.js'),
  'utf8'
);

test('WebSocket guard is imported and initialized', () => {
  assert.match(source, /require\('\.\/server_ws_frame_guard'\)/);
  assert.match(source, /createWsFrameGuard\(\{/);
});

test('guard preserves existing WebSocket payload size', () => {
  assert.match(source, /maxPayload:\s*16\s*\*\s*1024\s*\*\s*1024/);
  assert.match(source, /maxFrameBytes:\s*16\s*\*\s*1024\s*\*\s*1024/);
});

test('guard executes before JSON parsing', () => {
  const handler = source.indexOf('const frameDecision = wsFrameGuard.check(');
  const parser = source.indexOf('JSON.parse(', handler);
  const limiter = source.indexOf(
    "connectionMessageRateLimiter.consume('messages')",
    handler
  );

  assert.ok(handler >= 0);
  assert.ok(parser > handler);
  assert.ok(limiter > handler);
});

test('existing rate limit remains active', () => {
  assert.match(source, /MESSAGE_IP_RATE_LIMITER\.consume\(clientAddress\)/);
  assert.match(source, /connectionMessageRateLimiter\.consume\('messages'\)/);
});

test('guard rejection closes the connection', () => {
  assert.match(source, /ws\.close\(1009, 'WebSocket frame rejected'\)/);
});