'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { createLegacyMediaRegrantProtocol } =
  require('../server_legacy_media_regrant_protocol');

function setup() {
  const ws = {};
  const otherWs = {};
  const sessions = new WeakMap([[ws, 'alice'], [otherWs, 'bob']]);
  const active = new Map([['alice', ws], ['bob', otherWs]]);
  const sent = [];
  const received = [];

  const handler = {
    handle(socket, request) {
      received.push({ socket, request });
      return { ok: true };
    }
  };

  const create = options => createLegacyMediaRegrantProtocol({
    getAuthenticatedUser: socket => sessions.get(socket) || null,
    getActiveSocket: user => active.get(user) || null,
    regrantHandler: handler,
    send: (socket, type, payload) => {
      sent.push({ socket, type, payload });
    },
    ...options
  });

  return { ws, otherWs, active, sent, received, handler, create };
}

test('active authenticated owner reaches handler', () => {
  const s = setup();
  const p = s.create();

  p.handle(s.ws, 'alice', {
    mediaId: 'media001',
    recipient: 'bob',
    confirm: true,
    actor: 'forged'
  });

  assert.equal(s.sent[0].payload.ok, true);
  assert.deepEqual(s.received[0].request, {
    mediaId: 'media001',
    recipient: 'bob',
    confirm: true
  });
});

test('wrong current user denied', () => {
  const s = setup();
  s.create().handle(s.ws, 'bob', { confirm: true });

  assert.equal(s.sent[0].payload.ok, false);
  assert.equal(s.received.length, 0);
});

test('replaced socket denied', () => {
  const s = setup();
  s.active.set('alice', {});

  s.create().handle(s.ws, 'alice', { confirm: true });

  assert.equal(s.sent[0].payload.reason, 'UNAUTHENTICATED');
  assert.equal(s.received.length, 0);
});

test('unauthenticated socket denied', () => {
  const s = setup();
  s.create().handle({}, 'alice', { confirm: true });

  assert.equal(s.sent[0].payload.ok, false);
  assert.equal(s.received.length, 0);
});

test('handler failure yields safe error response', () => {
  const s = setup();

  s.create({
    regrantHandler: {
      handle() { throw new Error('PRIVATE_INTERNAL_DETAIL'); }
    }
  }).handle(s.ws, 'alice', { confirm: true });

  assert.deepEqual(s.sent[0].payload, {
    ok: false,
    reason: 'REGRANT_FAILED'
  });
});

test('unavailable handler denies', () => {
  const s = setup();
  s.create({ regrantHandler: null })
    .handle(s.ws, 'alice', { confirm: true });

  assert.equal(s.sent[0].payload.reason, 'UNAUTHENTICATED');
});