'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  createPresenceState,
} = require('../server_presence_state');

function setup() {
  let time = 100000;

  const identities = new WeakMap();

  const presence = createPresenceState({
    getAuthenticatedUser: ws => identities.get(ws) || null,
    now: () => time,
    maxAgeMs: 90000,
  });

  const ws = {};

  identities.set(ws, 'alice');

  return {
    ws,
    presence,
    identities,
    advance: ms => { time += ms; },
  };
}

test('authenticated background connection is not public online', () => {
  const h = setup();

  assert.equal(h.presence.bind(h.ws, 'alice'), true);
  assert.equal(h.presence.isOnline('alice'), false);
});

test('active foreground session becomes online', () => {
  const h = setup();

  h.presence.bind(h.ws, 'alice');

  assert.equal(h.presence.update(h.ws, true), true);
  assert.equal(h.presence.isOnline('alice'), true);
});

test('locking phone switches presence offline without closing socket', () => {
  const h = setup();

  h.presence.bind(h.ws, 'alice');
  h.presence.update(h.ws, true);
  h.presence.update(h.ws, false);

  assert.equal(h.presence.isOnline('alice'), false);
});

test('background notification does not turn user online', () => {
  const h = setup();

  h.presence.bind(h.ws, 'alice');
  h.presence.update(h.ws, false);

  // Notification transport can stay connected.
  assert.equal(h.presence.isOnline('alice'), false);
});

test('stale activity expires automatically', () => {
  const h = setup();

  h.presence.bind(h.ws, 'alice');
  h.presence.update(h.ws, true);

  h.advance(90000);

  assert.equal(h.presence.isOnline('alice'), false);
});

test('unauthenticated socket cannot forge presence', () => {
  const h = setup();

  const attacker = {};

  assert.equal(h.presence.bind(attacker, 'alice'), false);
  assert.equal(h.presence.update(attacker, true), false);
  assert.equal(h.presence.isOnline('alice'), false);
});

test('old socket cannot control replacement session', () => {
  const h = setup();

  const replacement = {};

  h.presence.bind(h.ws, 'alice');
  h.identities.set(replacement, 'alice');

  assert.equal(h.presence.bind(replacement, 'alice'), true);
  assert.equal(h.presence.update(h.ws, true), false);

  assert.equal(h.presence.update(replacement, true), true);
  assert.equal(h.presence.disconnect(h.ws), false);

  assert.equal(h.presence.isOnline('alice'), true);
});