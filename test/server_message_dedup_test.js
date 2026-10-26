'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createMessageDedup } = require('../server_message_dedup');

const base = {
  from: 'alice',
  to: 'bob',
  id: '1234567890123456-abcdef0123456789',
};

test('first ID is accepted, duplicate is rejected', () => {
  const dedup = createMessageDedup();

  assert.equal(dedup.mark(base), true);
  assert.equal(dedup.mark(base), false);
  assert.equal(dedup.size, 1);
});

test('different IDs remain distinct', () => {
  const dedup = createMessageDedup();

  assert.equal(dedup.mark(base), true);
  assert.equal(dedup.mark({ ...base, id: base.id + '-2' }), true);
  assert.equal(dedup.size, 2);
});

test('sender and recipient are part of identity', () => {
  const dedup = createMessageDedup();

  assert.equal(dedup.mark(base), true);
  assert.equal(dedup.mark({ ...base, from: 'charlie' }), true);
  assert.equal(dedup.mark({ ...base, to: 'charlie' }), true);
});

test('expired records are removable', () => {
  let clock = 1000;
  const dedup = createMessageDedup({
    ttlMs: 5000,
    now: () => clock,
  });

  assert.equal(dedup.mark(base), true);

  clock = 5999;
  assert.equal(dedup.has(base), true);

  clock = 6000;
  assert.equal(dedup.has(base), false);
  assert.equal(dedup.mark(base), true);
});

test('invalid or missing IDs are rejected', () => {
  const dedup = createMessageDedup();

  assert.throws(() => dedup.mark({ ...base, id: '' }), TypeError);
  assert.throws(() => dedup.mark({ ...base, id: null }), TypeError);
});

test('key construction does not collide across fields', () => {
  const dedup = createMessageDedup();

  assert.equal(
    dedup.mark({ from: 'a:b', to: 'c', id: '123456' }),
    true
  );
  assert.equal(
    dedup.mark({ from: 'a', to: 'b:c', id: '123456' }),
    true
  );
});