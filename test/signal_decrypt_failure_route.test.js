'use strict';

const fs = require('fs');
const assert = require('assert');

const code = fs.readFileSync('server.js', 'utf8');
const start = code.indexOf("if (type === 'e2ee_decrypt_failed')");
const end = code.indexOf("if (type === 'e2ee_message')", start);

assert(start >= 0 && end > start, 'Handler not found');

const body = code.slice(start, end);

assert(!body.includes('purgeOfflineMessageArtifacts('));
assert(!body.includes('deleteSession('));

const execute = new Function(
  'type', 'currentUser', 'ws', 'wsSessionIdentity',
  'data', 'offlineMessages', 'sendOrQueueMessageStatus',
  body
);

const id = 'signalMessage123';
const original = {
  id,
  from: 'AllaAlla',
  to: 'Sparta',
  e2ee: true,
  ciphertext: 'encrypted-only'
};

function scenario(name, options, expectedCount) {
  const queue = [Object.assign({}, original)];
  const initial = JSON.stringify(queue);
  const events = [];

  const ws = {};
  const actualUser =
    options.authenticated === false ? 'SomeoneElse' : 'Sparta';

  execute(
    'e2ee_decrypt_failed',
    options.currentUser || 'Sparta',
    ws,
    {
      getAuthenticatedUser: () => actualUser
    },
    {
      messageId: options.messageId || id,
      from: options.from || 'AllaAlla'
    },
    {
      Sparta: options.emptyQueue ? [] : queue
    },
    (recipient, event, payload) => {
      events.push({ recipient, event, payload });
    }
  );

  assert.strictEqual(
    events.length,
    expectedCount,
    name + ': unexpected notification count'
  );
  assert.strictEqual(
    JSON.stringify(queue),
    initial,
    name + ': message queue was modified'
  );

  if (expectedCount === 1) {
    assert.strictEqual(events[0].recipient, 'AllaAlla');
    assert.strictEqual(events[0].event, 'e2ee_decrypt_failure');
    assert.deepStrictEqual(events[0].payload, {
      messageId: id,
      from: 'AllaAlla',
      to: 'Sparta'
    });
  }

  console.log('PASS: ' + name);
}

scenario('valid authenticated recipient', {}, 1);
scenario('forged authenticated account', {
  authenticated: false
}, 0);
scenario('wrong message owner', {
  currentUser: 'SomeoneElse'
}, 0);
scenario('forged message sender', {
  from: 'UnknownUser'
}, 0);
scenario('unknown message ID', {
  messageId: 'unknownMessage123'
}, 0);
scenario('no message in offline queue', {
  emptyQueue: true
}, 0);

console.log('ALL 6 SECURITY SCENARIOS PASSED');