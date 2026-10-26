'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  measureStorageBytes,
  createMessageStorageLimits,
} = require('../server_message_storage_limits');

test('empty storage size is measured', () => {
  assert.equal(measureStorageBytes({}), 2);
});

test('UTF-8 storage size is measured in bytes', () => {
  const records = {
    message1: {
      text: 'Привет 🌍',
    },
  };

  assert.equal(
    measureStorageBytes(records),
    Buffer.byteLength(JSON.stringify(records), 'utf8')
  );
});

test('storage within limit is accepted', () => {
  const records = { a: { text: 'hello' } };
  const bytes = measureStorageBytes(records);

  const limits = createMessageStorageLimits({
    maxStorageBytes: bytes,
  });

  assert.equal(limits.check(records).allowed, true);
  assert.equal(limits.assertCanStore(records).bytes, bytes);
});

test('storage exceeding limit is rejected', () => {
  const limits = createMessageStorageLimits({
    maxStorageBytes: 100,
  });

  const records = {
    a: { text: 'x'.repeat(200) },
  };

  assert.equal(limits.check(records).allowed, false);

  assert.throws(
    () => limits.assertCanStore(records),
    /capacity exceeded/
  );
});

test('capacity check does not modify stored messages', () => {
  const records = {
    pending: {
      status: 'pending',
      payload: { text: 'important' },
    },
  };

  const original = structuredClone(records);

  const limits = createMessageStorageLimits({
    maxStorageBytes: 10,
  });

  assert.throws(
    () => limits.assertCanStore(records),
    RangeError
  );

  assert.deepEqual(records, original);
});

test('invalid capacity configuration is rejected', () => {
  assert.throws(
    () => createMessageStorageLimits({
      maxStorageBytes: 0,
    }),
    RangeError
  );
});

test('different limits are independently configurable', () => {
  const records = {
    item: { text: 'test' },
  };

  const small = createMessageStorageLimits({
    maxStorageBytes: 10,
  });

  const large = createMessageStorageLimits({
    maxStorageBytes: 1000,
  });

  assert.equal(small.check(records).allowed, false);
  assert.equal(large.check(records).allowed, true);
});