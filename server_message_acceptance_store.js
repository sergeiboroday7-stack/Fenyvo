'use strict';

const { createDedupStore } = require('./server_message_dedup_store');

function createMessageAcceptanceStore({ store, filePath } = {}) {
  const backend = store || createDedupStore(filePath);
  const initial = backend.load();

  if (!initial || typeof initial !== 'object' || Array.isArray(initial)) {
    throw new TypeError('Invalid acceptance store');
  }

  let records = initial;

  function keyFor(message) {
    const { from, to, id } = message;

    if (![from, to, id].every(
      value => typeof value === 'string' && value.trim()
    )) {
      throw new TypeError('Invalid message identity');
    }

    return JSON.stringify([from, to, id]);
  }

  function accept(message) {
    const key = keyFor(message);
    const previous = records[key];

    if (previous) {
      return {
        accepted: false,
        duplicate: true,
        record: { ...previous },
      };
    }

    const record = {
      id: message.id,
      from: message.from,
      to: message.to,
      status: 'accepted',
      acceptedAt: new Date().toISOString(),
    };

    const next = {
      ...records,
      [key]: record,
    };

    // The new state is published only after successful persistence.
    backend.save(next);
    records = next;

    return {
      accepted: true,
      duplicate: false,
      record: { ...record },
    };
  }

  function get(message) {
    const record = records[keyFor(message)];
    return record ? { ...record } : null;
  }

  function markDelivered(message) {
    const key = keyFor(message);
    const record = records[key];

    if (!record) return false;
    if (record.status === 'delivered') return true;

    const next = {
      ...records,
      [key]: {
        ...record,
        status: 'delivered',
      },
    };

    backend.save(next);
    records = next;
    return true;
  }

  return {
    accept,
    get,
    markDelivered,
  };
}

module.exports = { createMessageAcceptanceStore };