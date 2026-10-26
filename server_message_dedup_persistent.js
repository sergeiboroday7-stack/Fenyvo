'use strict';

const { DEFAULT_TTL_MS } = require('./server_message_dedup');
const { createDedupStore } = require('./server_message_dedup_store');

function createPersistentMessageDedup({
  filePath,
  store = filePath ? createDedupStore(filePath) : undefined,
  ttlMs = DEFAULT_TTL_MS,
  now = () => Date.now(),
} = {}) {
  if (!store || typeof store.load !== 'function' ||
      typeof store.save !== 'function') {
    throw new TypeError('A persistent store is required');
  }

  if (!Number.isSafeInteger(ttlMs) || ttlMs <= 0) {
    throw new RangeError('Invalid TTL');
  }

  function keyFor({ from, to, id }) {
    if (![from, to, id].every(
      value => typeof value === 'string' && value.trim()
    )) {
      throw new TypeError('Invalid message identity');
    }

    return JSON.stringify([from, to, id]);
  }

  const loaded = store.load();
  const entries = Object.entries(loaded);
  const records = new Map();

  for (const [key, expiry] of entries) {
    if (typeof expiry !== 'number' ||
        !Number.isSafeInteger(expiry) ||
        expiry < 0) {
      throw new TypeError('Invalid stored expiration');
    }

    if (expiry > now()) records.set(key, expiry);
  }

  function has(message) {
    const key = keyFor(message);
    return (records.get(key) ?? 0) > now();
  }

  function mark(message) {
    const key = keyFor(message);
    const current = now();

    if ((records.get(key) ?? 0) > current) {
      return false;
    }

    const next = new Map();

    for (const [storedKey, expiry] of records) {
      if (expiry > current) next.set(storedKey, expiry);
    }

    next.set(key, current + ttlMs);

    // The in-memory state changes only after persistence succeeds.
    store.save(Object.fromEntries(next));

    records.clear();

    for (const [storedKey, expiry] of next) {
      records.set(storedKey, expiry);
    }

    return true;
  }

  return {
    has,
    mark,
    get size() {
      return [...records.values()].filter(
        expiry => expiry > now()
      ).length;
    },
  };
}

module.exports = { createPersistentMessageDedup };