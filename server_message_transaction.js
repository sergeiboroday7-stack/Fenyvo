const { createMessageStorageLimits, measureStorageBytes } =
  require('./server_message_storage_limits');
'use strict';

const { createDedupStore } = require('./server_message_dedup_store');
const crypto = require('node:crypto');

function createMessageTransaction({
  store,
  filePath,
  maxStorageBytes = 64 * 1024 * 1024,
  maxPayloadBytes = 1024 * 1024,
  deliveredRetentionMs = 7 * 24 * 60 * 60 * 1000,
  now = () => Date.now(),
} = {}) {
  if (!Number.isSafeInteger(deliveredRetentionMs) ||
      deliveredRetentionMs <= 0) {
    throw new RangeError('Invalid delivered retention');
  }
  if (typeof now !== 'function') {
    throw new TypeError('Invalid clock');
  }
  if (!Number.isSafeInteger(maxPayloadBytes) || maxPayloadBytes <= 0) {
    throw new RangeError('Invalid message size limit');
  }
  const backend = store || createDedupStore(filePath);
  const initial = backend.load();

  if (!initial || typeof initial !== 'object' || Array.isArray(initial)) {
    throw new TypeError('Invalid transaction store');
  }

  let records = initial;

  function keyFor(message) {
    if (!message || !['from', 'to', 'id'].every(
      key => typeof message[key] === 'string' && message[key].trim()
    )) {
      throw new TypeError('Invalid message identity');
    }
    return JSON.stringify([message.from, message.to, message.id]);
  }

  function canonicalize(value) {
    if (Array.isArray(value)) {
      return value.map(canonicalize);
    }

    if (value && typeof value === 'object') {
      const result = {};

      for (const key of Object.keys(value).sort()) {
        if (value[key] !== undefined) {
          result[key] = canonicalize(value[key]);
        }
      }

      return result;
    }

    return value;
  }

  function fingerprint(message) {
    const value = JSON.stringify(canonicalize(message));

    if (typeof value !== 'string') {
      throw new TypeError('Invalid message payload');
    }

    return crypto.createHash('sha256').update(value).digest('hex');
  }

  function legacyFingerprint(message) {
    return crypto.createHash('sha256')
      .update(JSON.stringify(message))
      .digest('hex');
  }
  const storageLimits = createMessageStorageLimits({
    maxStorageBytes,
  });

  function saveWithinLimit(next) {
    const previousBytes = measureStorageBytes(records);
    const nextBytes = measureStorageBytes(next);

    // Reject growth beyond capacity, but allow operations
    // that reduce an already oversized legacy storage file.
    if (nextBytes > previousBytes) {
      storageLimits.assertCanStore(next);
    }

    backend.save(next);
  }
  function accept(message) {
    const key = keyFor(message);

    if (Object.hasOwn(records, key)) {
      const previous = records[key];

      const currentHash = fingerprint(message);
      const previousHash = previous.payloadHash;

      const matchesCurrent =
        previous.payloadHashVersion === 2 &&
        previousHash === currentHash;

      const matchesLegacy =
        previous.payloadHashVersion == null &&
        previous.payload != null &&
        previousHash === legacyFingerprint(previous.payload) &&
        fingerprint(previous.payload) === currentHash;

      if (!matchesCurrent && !matchesLegacy) {
        return {
          duplicate: false,
          conflict: true,
          record: null,
        };
      }

      return {
        duplicate: true,
        conflict: false,
        record: structuredClone(previous),
      };
    }

    const serialized = JSON.stringify(message);

    if (typeof serialized !== 'string') {
      throw new TypeError('Invalid message payload');
    }

    const size = Buffer.byteLength(serialized, 'utf8');

    if (size > maxPayloadBytes) {
      throw new RangeError('Message payload exceeds size limit');
    }

    const record = {
      id: message.id,
      from: message.from,
      to: message.to,
      status: 'pending',
      payloadHashVersion: 2,
      payloadHash: fingerprint(message),
      payload: structuredClone(message),
      acceptedAt: new Date().toISOString(),
    };

    const next = { ...records, [key]: record };

    // Message and identity commit in the same stored snapshot.
    saveWithinLimit(next);
    records = next;

    return {
      duplicate: false,
      record: structuredClone(record),
    };
  }

  function get(message) {
    const record = records[keyFor(message)];
    return record ? structuredClone(record) : null;
  }

  function markDelivered(message, authenticatedRecipient) {
    if (
      typeof authenticatedRecipient !== 'string' ||
      !authenticatedRecipient.trim() ||
      authenticatedRecipient !== message?.to
    ) {
      return false;
    }
    const key = keyFor(message);

    if (!Object.hasOwn(records, key)) return false;
    if (records[key].status === 'delivered') return true;

    const next = {
      ...records,
      [key]: {
        ...records[key],
        status: 'delivered',
        deliveredAtMs: now(),
        payload: null,
      },
    };

    saveWithinLimit(next);
    records = next;
    return true;
  }

  function pendingFor(recipient) {
    return Object.values(records)
      .filter(item => item.to === recipient && item.status === 'pending')
      .map(item => structuredClone(item.payload));
  }

  function pruneDelivered() {
    const current = now();
    const next = {};
    let removed = 0;

    for (const [key, record] of Object.entries(records)) {
      const deliveredAt = record?.deliveredAtMs;

      if (
        record?.status === 'delivered' &&
        Number.isSafeInteger(deliveredAt) &&
        deliveredAt >= 0 &&
        current >= deliveredAt &&
        current - deliveredAt >= deliveredRetentionMs
      ) {
        removed++;
        continue;
      }

      next[key] = record;
    }

    if (removed === 0) return 0;

    // No in-memory mutation before durable storage succeeds.
    saveWithinLimit(next);
    records = next;
    return removed;
  }

  return { accept, get, markDelivered, pendingFor, pruneDelivered };
}

module.exports = { createMessageTransaction };