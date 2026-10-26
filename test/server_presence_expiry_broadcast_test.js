'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'server.js'), 'utf8'
);

const start = source.indexOf('function checkExpiredPublicPresence(');
const end = source.indexOf('const presenceExpiryTimer', start);

assert.ok(start >= 0 && end > start);
const fn = source.slice(start, end);

function setup(active) {
  const events = [];
  const transport = new Map([['alice', {}]]);
  const published = new Map([['alice', true]]);

  const sandbox = {
    onlineUsers: transport,
    lastPublicPresence: published,
    publicPresence: { isOnline: () => active },
    broadcastUserStatus: name => events.push('status:' + name),
    broadcastUsers: () => events.push('users'),
  };

  vm.createContext(sandbox);
  vm.runInContext(fn, sandbox);

  return { sandbox, events, transport, published };
}

test('expiry emits offline event and new user list', () => {
  const h = setup(false);
  h.sandbox.checkExpiredPublicPresence();
  assert.deepEqual(h.events, ['status:alice', 'users']);
  assert.equal(h.published.get('alice'), false);
});

test('valid foreground state never expires prematurely', () => {
  const h = setup(true);
  h.sandbox.checkExpiredPublicPresence();
  assert.deepEqual(h.events, []);
});

test('expiry is announced only once', () => {
  const h = setup(false);
  h.sandbox.checkExpiredPublicPresence();
  h.sandbox.checkExpiredPublicPresence();
  assert.deepEqual(h.events, ['status:alice', 'users']);
});

test('expiry preserves WebSocket for background delivery', () => {
  const h = setup(false);
  h.sandbox.checkExpiredPublicPresence();
  assert.equal(h.transport.has('alice'), true);
});

test('public list updates published snapshot', () => {
  const a = source.indexOf('function broadcastUsers(');
  const b = source.indexOf('function getUserStatusData(', a);
  assert.ok(a >= 0 && b > a);
  assert.match(
    source.slice(a, b),
    /lastPublicPresence\.set\(\s*username,\s*publicPresence\.isOnline\(username\)/
  );
});

test('expiry timer runs every five seconds', () => {
  assert.match(
    source,
    /setInterval\(\s*checkExpiredPublicPresence,\s*5000\s*\)/
  );
  assert.match(source, /presenceExpiryTimer\.unref\?\.\(\)/);
});