'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'server.js'),
  'utf8'
);

const { verifyMessageAckOwnership } =
  require('../server_message_ack_ownership');

const start = source.indexOf(
  "// MESSAGE DELIVERED"
);

const end = source.indexOf(
  "// MESSAGE READ",
  start
);

const handler = source.slice(start, end);

test('ownership module is imported into main server', () => {
  assert.match(
    source,
    /require\('\.\/server_message_ack_ownership'\)/
  );
});

test('delivery ACK uses server-bound session identity', () => {
  assert.match(
    handler,
    /authenticatedUser:\s*wsSessionIdentity\.getAuthenticatedUser\(ws\)/
  );
});

test('delivery ACK checks the actual recipient queue', () => {
  assert.match(
    handler,
    /queue:\s*offlineMessages\[messageTo\]/
  );
});

test('ownership verification precedes destructive purge', () => {
  const verify = handler.indexOf(
    'verifyMessageAckOwnership({'
  );

  const reject = handler.indexOf(
    'if (!ackOwnership.allowed)'
  );

  const purge = handler.indexOf(
    'purgeOfflineMessageArtifacts('
  );

  const notify = handler.indexOf(
    'sendOrQueueMessageStatus('
  );

  assert.ok(verify >= 0);
  assert.ok(reject > verify);
  assert.ok(purge > reject);
  assert.ok(notify > purge);

  assert.match(
    handler,
    /if \(!ackOwnership\.allowed\)\s*\{[^}]*return;/
  );
});

test('forged sender cannot authorize queued deletion', () => {
  const result = verifyMessageAckOwnership({
    authenticatedUser: 'bob',
    messageId: 'm1',
    from: 'mallory',
    to: 'bob',
    queue: [{
      id: 'm1',
      from: 'alice',
      to: 'bob',
      text: 'ciphertext',
    }],
  });

  assert.equal(result.allowed, false);
  assert.equal(result.reason, 'identity_mismatch');
});

test('legitimate recipient can verify queued message', () => {
  const result = verifyMessageAckOwnership({
    authenticatedUser: 'bob',
    messageId: 'm1',
    from: 'alice',
    to: 'bob',
    queue: [{
      id: 'm1',
      from: 'alice',
      to: 'bob',
      text: 'ciphertext',
    }],
  });

  assert.equal(result.allowed, true);
});

test('missing original message cannot generate delivery ACK', () => {
  const result = verifyMessageAckOwnership({
    authenticatedUser: 'bob',
    messageId: 'm1',
    from: 'alice',
    to: 'bob',
    queue: [],
  });

  assert.equal(result.allowed, false);
});

test('existing WebSocket protections remain in place', () => {
  assert.match(source, /wsFrameGuard\.check\(ws,\s*rawMessage,\s*isBinary\)/);
  assert.match(source, /wsSessionIdentity\.revoke\(ws\)/);
  assert.match(source, /MESSAGE_IP_RATE_LIMITER\.consume\(clientAddress\)/);
});