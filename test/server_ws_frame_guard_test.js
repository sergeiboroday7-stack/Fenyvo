'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { createWsFrameGuard } =
  require('../server_ws_frame_guard');

test('small text frame is accepted', () => {
  const guard = createWsFrameGuard();
  assert.equal(guard.check({}, '{"type":"ping"}').allowed, true);
});

test('oversized frame is rejected', () => {
  const guard = createWsFrameGuard({ maxFrameBytes: 10 });
  assert.equal(
    guard.check({}, '12345678901').reason,
    'frame_too_large'
  );
});

test('UTF-8 size is counted in bytes', () => {
  const guard = createWsFrameGuard({ maxFrameBytes: 3 });
  assert.equal(guard.check({}, 'пр').reason, 'frame_too_large');
});

test('binary frames are rejected', () => {
  const guard = createWsFrameGuard();
  assert.equal(
    guard.check({}, Buffer.from('abc'), true).reason,
    'binary_not_allowed'
  );
});

test('request limit is enforced per connection', () => {
  const guard = createWsFrameGuard({ maxRequests: 2 });
  const socket = {};

  assert.equal(guard.check(socket, 'a').allowed, true);
  assert.equal(guard.check(socket, 'b').allowed, true);
  assert.equal(
    guard.check(socket, 'c').reason,
    'rate_limited'
  );
});

test('different sockets have independent limits', () => {
  const guard = createWsFrameGuard({ maxRequests: 1 });
  const alice = {};
  const bob = {};

  assert.equal(guard.check(alice, 'a').allowed, true);
  assert.equal(guard.check(bob, 'b').allowed, true);
  assert.equal(guard.check(alice, 'c').allowed, false);
});

test('limits reset after time window', () => {
  let time = 1000;

  const guard = createWsFrameGuard({
    maxRequests: 1,
    windowMs: 1000,
    now: () => time,
  });

  const socket = {};

  assert.equal(guard.check(socket, 'a').allowed, true);
  assert.equal(guard.check(socket, 'b').allowed, false);

  time = 2000;

  assert.equal(guard.check(socket, 'c').allowed, true);
});

test('revoked connection resets its counter', () => {
  const guard = createWsFrameGuard({ maxRequests: 1 });
  const socket = {};

  assert.equal(guard.check(socket, 'a').allowed, true);
  assert.equal(guard.check(socket, 'b').allowed, false);

  guard.revoke(socket);

  assert.equal(guard.check(socket, 'c').allowed, true);
});

test('invalid limits are rejected', () => {
  assert.throws(
    () => createWsFrameGuard({ maxFrameBytes: -1 }),
    TypeError
  );

  assert.throws(
    () => createWsFrameGuard({ maxRequests: 0 }),
    TypeError
  );
});

test('invalid session is rejected', () => {
  const guard = createWsFrameGuard();

  assert.equal(
    guard.check(null, 'hello').reason,
    'invalid_session'
  );
});