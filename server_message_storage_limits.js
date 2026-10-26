'use strict';

const DEFAULT_MAX_STORAGE_BYTES = 64 * 1024 * 1024;

function measureStorageBytes(records) {
  if (!records || typeof records !== 'object' ||
      Array.isArray(records)) {
    throw new TypeError('Invalid storage records');
  }

  const serialized = JSON.stringify(records);

  if (typeof serialized !== 'string') {
    throw new TypeError('Invalid storage data');
  }

  return Buffer.byteLength(serialized, 'utf8');
}

function createMessageStorageLimits({
  maxStorageBytes = DEFAULT_MAX_STORAGE_BYTES,
} = {}) {
  if (!Number.isSafeInteger(maxStorageBytes) ||
      maxStorageBytes <= 0) {
    throw new RangeError('Invalid storage size limit');
  }

  function check(nextRecords) {
    const bytes = measureStorageBytes(nextRecords);

    return {
      allowed: bytes <= maxStorageBytes,
      bytes,
      maxStorageBytes,
    };
  }

  function assertCanStore(nextRecords) {
    const result = check(nextRecords);

    if (!result.allowed) {
      throw new RangeError('Message storage capacity exceeded');
    }

    return result;
  }

  return {
    check,
    assertCanStore,
    maxStorageBytes,
  };
}

module.exports = {
  DEFAULT_MAX_STORAGE_BYTES,
  measureStorageBytes,
  createMessageStorageLimits,
};