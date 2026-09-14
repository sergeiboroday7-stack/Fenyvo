const assert = require('node:assert/strict');
const test = require('node:test');

const {
  AuthRateLimiter,
  getClientAddress,
} = require('../server_security');

test('auth limiter blocks attempts until its window expires', () => {
  let now = 1000;
  const limiter = new AuthRateLimiter({
    maxAttempts: 2,
    windowMs: 5000,
    now: () => now,
  });

  assert.equal(limiter.consume('client').allowed, true);
  assert.equal(limiter.consume('client').allowed, true);
  const blocked = limiter.consume('client');
  assert.equal(blocked.allowed, false);
  assert.equal(blocked.retryAfterSeconds, 5);

  now = 6000;
  assert.equal(limiter.consume('client').allowed, true);
});

test('successful authentication can reset the client bucket', () => {
  const limiter = new AuthRateLimiter({ maxAttempts: 1, windowMs: 5000 });
  assert.equal(limiter.consume('client').allowed, true);
  assert.equal(limiter.consume('client').allowed, false);
  limiter.reset('client');
  assert.equal(limiter.consume('client').allowed, true);
});

test('forwarded addresses are ignored unless the proxy is trusted', () => {
  const request = {
    headers: { 'x-forwarded-for': '203.0.113.7, 127.0.0.1' },
    socket: { remoteAddress: '::ffff:192.168.0.20' },
  };
  assert.equal(getClientAddress(request, false), '192.168.0.20');
  assert.equal(getClientAddress(request, true), '203.0.113.7');
});
