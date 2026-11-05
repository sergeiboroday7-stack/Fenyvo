'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createLegacyMediaRegrantProtocol } =
  require('../server_legacy_media_regrant_protocol');

function makeProtocol() {
  const ws = {};
  const replies = [];

  const protocol = createLegacyMediaRegrantProtocol({
    getAuthenticatedUser: () => 'alice',
    getActiveSocket: () => ws,
    regrantHandler: {
      handle: () => ({ ok: true })
    },
    send: (_socket, type, payload) => {
      replies.push({ type, payload });
    }
  });

  return { ws, protocol, replies };
}

test('valid requestId is echoed on approval', () => {
  const { ws, protocol, replies } = makeProtocol();

  protocol.handle(ws, 'alice', {
    mediaId: 'm1',
    recipient: 'bob',
    confirm: true,
    requestId: 'req_159_abc'
  });

  assert.equal(replies.length, 1);
  assert.equal(replies[0].type, 'legacy_media_regrant_result');
  assert.deepEqual(replies[0].payload, {
    ok: true,
    requestId: 'req_159_abc'
  });
});

test('old clients receive no extra requestId', () => {
  const { ws, protocol, replies } = makeProtocol();

  protocol.handle(ws, 'alice', {
    mediaId: 'm1',
    recipient: 'bob',
    confirm: true
  });

  assert.deepEqual(replies[0].payload, { ok: true });
});

test('invalid requestId is never echoed', () => {
  const { ws, protocol, replies } = makeProtocol();

  protocol.handle(ws, 'alice', {
    requestId: 'bad request id',
    confirm: true
  });

  assert.deepEqual(replies[0].payload, { ok: true });
});

test('unauthorized response retains valid requestId', () => {
  const { ws, protocol, replies } = makeProtocol();

  protocol.handle(ws, 'somebody_else', {
    requestId: 'denied_159'
  });

  assert.deepEqual(replies[0].payload, {
    ok: false,
    reason: 'UNAUTHENTICATED',
    requestId: 'denied_159'
  });
});