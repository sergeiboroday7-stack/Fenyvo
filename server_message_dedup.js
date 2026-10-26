'use strict';

const DEFAULT_TTL_MS = 7 * 24 * 60 * 60 * 1000;

function createMessageDedup({
  ttlMs = DEFAULT_TTL_MS,
  now = () => Date.now(),
} = {}) {
  if (!Number.isSafeInteger(ttlMs) || ttlMs <= 0) {
    throw new RangeError('ttlMs must be a positive safe integer');
  }

  const records = new Map();

  function keyFor({ from, to, id }) {
    if (
      typeof from !== 'string' || !from.trim() ||
      typeof to !== 'string' || !to.trim() ||
      typeof id !== 'string' || !id.trim()
    ) {
      throw new TypeError('from, to and id are required strings');
    }

    return JSON.stringify([from, to, id]);
  }

  function prune() {
    const current = now();

    for (const [key, expiresAt] of records) {
      if (expiresAt <= current) {
        records.delete(key);
      }
    }
  }

  function has(message) {
    prune();
    return records.has(keyFor(message));
  }

  function mark(message) {
    prune();
    const key = keyFor(message);

    if (records.has(key)) {
      return false;
    }

    records.set(key, now() + ttlMs);
    return true;
  }

  return {
    has,
    mark,
    prune,
    get size() {
      prune();
      return records.size;
    },
  };
}

module.exports = {
  createMessageDedup,
  DEFAULT_TTL_MS,
};