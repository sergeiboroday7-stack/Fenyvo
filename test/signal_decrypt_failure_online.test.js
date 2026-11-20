'use strict';

const fs = require('fs');
const assert = require('node:assert/strict');

const source = fs.readFileSync('server.js', 'utf8');

const start = source.indexOf(
  "if (type === 'e2ee_decrypt_failed')"
);
const end = source.indexOf(
  "if (type === 'e2ee_message')", start
);

assert(start >= 0 && end > start, 'Failure handler missing');
const body = source.slice(start, end);

assert(
  source.includes('recentE2eeOnlineDeliveries.set(messageData.id'),
  'Online delivery registration missing'
);
assert(
  source.includes('expiresAt: now + 600000'),
  'Ten-minute expiration missing'
);
assert(
  source.includes('recentE2eeOnlineDeliveries.size >= 2048'),
  'Bounded map protection missing'
);
assert(
  body.includes('onlineEvidence.from !== from') &&
  body.includes('onlineEvidence.to !== currentUser') &&
  body.includes('onlineEvidence.expiresAt <= Date.now()'),
  'Online ownership checks missing'
);

const handler = new Function(
  'type',
  'currentUser',
  'ws',
  'wsSessionIdentity',
  'data',
  'offlineMessages',
  'sendOrQueueMessageStatus',
  'recentE2eeOnlineDeliveries',
  body
);

const id = 'signalOnlineMessage123';

function scenario(name, opts, shouldNotify) {
  const ws = {};
  const queue = [];
  const before = JSON.stringify(queue);
  const events = [];
  const records = new Map();

  if (opts.record !== false) {
    records.set(id, {
      from: opts.recordFrom || 'AllaAlla',
      to: opts.recordTo || 'Sparta',
      expiresAt: Date.now() +
        (opts.expired ? -1000 : 600000)
    });
  }

  handler(
    'e2ee_decrypt_failed',
    opts.currentUser || 'Sparta',
    ws,
    {
      getAuthenticatedUser: () =>
        opts.authenticated === false ? 'Impostor' : 'Sparta'
    },
    {
      messageId: opts.requestId || id,
      from: opts.requestFrom || 'AllaAlla'
    },
    { Sparta: queue },
    (recipient, event, payload) =>
      events.push({ recipient, event, payload }),
    records
  );

  assert.equal(
    events.length,
    shouldNotify ? 1 : 0,
    name + ': unexpected result'
  );
  assert.equal(
    JSON.stringify(queue),
    before,
    name + ': offline queue changed'
  );

  if (shouldNotify) {
    assert.deepEqual(events[0], {
      recipient: 'AllaAlla',
      event: 'e2ee_decrypt_failure',
      payload: {
        messageId: id,
        from: 'AllaAlla',
        to: 'Sparta'
      }
    });
  }

  console.log('PASS: ' + name);
}

scenario('valid online recipient', {}, true);
scenario('missing online record', { record: false }, false);
scenario('expired online record', { expired: true }, false);
scenario('wrong record sender', { recordFrom: 'Other' }, false);
scenario('wrong record recipient', { recordTo: 'Other' }, false);
scenario('spoofed requester', { authenticated: false }, false);
scenario('spoofed message sender', { requestFrom: 'Other' }, false);
scenario('unknown message id', {
  requestId: 'unknownOnlineMessage123'
}, false);

console.log('ALL 8 ONLINE SECURITY SCENARIOS PASSED');