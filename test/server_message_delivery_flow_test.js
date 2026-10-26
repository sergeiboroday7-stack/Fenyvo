'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const { createMessageTransaction } =
  require('../server_message_transaction');

const message = {
  id: '1234567890123456-abcdef0123456789',
  from: 'alice',
  to: 'bob',
  text: 'delivery flow test',
};

function createHarness(filePath) {
  const tx = createMessageTransaction({ filePath });
  const events = [];

  function submit(data) {
    const result = tx.accept(data);

    events.push({
      type: 'message_sent',
      id: result.record.id,
      duplicate: result.duplicate,
    });

    return result;
  }

  function pendingFor(recipient) {
    return tx.pendingFor(recipient);
  }

  function delivered(data) {
    const result = tx.markDelivered(data, data.to);

    if (result) {
      events.push({
        type: 'message_delivered',
        id: data.id,
      });
    }

    return result;
  }

  return { submit, pendingFor, delivered, events };
}

function withTempFile(run) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fenyvo-flow-'));
  const filePath = path.join(dir, 'messages.json');

  try {
    run(filePath);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

test('first submission produces one pending message and sender ack', () => {
  withTempFile(filePath => {
    const server = createHarness(filePath);

    assert.equal(server.submit(message).duplicate, false);
    assert.equal(server.pendingFor('bob').length, 1);
    assert.equal(server.events[0].type, 'message_sent');
  });
});

test('retry returns sender ack without adding a second pending message', () => {
  withTempFile(filePath => {
    const server = createHarness(filePath);

    server.submit(message);
    assert.equal(server.submit(message).duplicate, true);

    assert.equal(server.pendingFor('bob').length, 1);
    assert.equal(
      server.events.filter(event => event.type === 'message_sent').length,
      2
    );
  });
});

test('retry after server restart retains one pending message', () => {
  withTempFile(filePath => {
    createHarness(filePath).submit(message);

    const restarted = createHarness(filePath);

    assert.equal(restarted.submit(message).duplicate, true);
    assert.equal(restarted.pendingFor('bob').length, 1);
  });
});

test('delivery acknowledgement clears pending message', () => {
  withTempFile(filePath => {
    const server = createHarness(filePath);

    server.submit(message);
    assert.equal(server.delivered(message), true);
    assert.equal(server.pendingFor('bob').length, 0);
  });
});

test('retry after delivery does not resurrect pending message', () => {
  withTempFile(filePath => {
    const server = createHarness(filePath);

    server.submit(message);
    server.delivered(message);

    assert.equal(server.submit(message).duplicate, true);
    assert.equal(server.pendingFor('bob').length, 0);
  });
});

test('delivery state persists across restart', () => {
  withTempFile(filePath => {
    const first = createHarness(filePath);

    first.submit(message);
    first.delivered(message);

    const restarted = createHarness(filePath);

    assert.equal(restarted.submit(message).duplicate, true);
    assert.equal(restarted.pendingFor('bob').length, 0);
  });
});