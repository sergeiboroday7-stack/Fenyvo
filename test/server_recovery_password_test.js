'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { prepareRecoveryPasswordUpdate } = require('../server_recovery_password');

const passwordData = { salt: 'a'.repeat(32), hash: 'b'.repeat(128) };

test('updates password and preserves account fields', () => {
  const user = { salt: 'c'.repeat(32), passwordHash: 'd'.repeat(128), createdAt: '2026-01-01', profile: { about: 'Hello' }, legalAcceptance: { ageConfirmed: true } };
  const result = prepareRecoveryPasswordUpdate(user, passwordData);
  assert.equal(result.salt, passwordData.salt);
  assert.equal(result.passwordHash, passwordData.hash);
  assert.deepEqual(result.profile, user.profile);
  assert.deepEqual(result.legalAcceptance, user.legalAcceptance);
  assert.equal(result.createdAt, user.createdAt);
});

test('does not modify original account', () => {
  const user = { salt: 'c'.repeat(32), passwordHash: 'd'.repeat(128), profile: { about: 'Original' } };
  const original = structuredClone(user);
  const result = prepareRecoveryPasswordUpdate(user, passwordData);
  assert.deepEqual(user, original);
  assert.notStrictEqual(result, user);
});

test('rejects invalid password hash data', () => {
  const user = { profile: { about: 'Safe' } };
  assert.throws(() => prepareRecoveryPasswordUpdate(user, { salt: 'invalid', hash: 'bad' }), TypeError);
  assert.deepEqual(user, { profile: { about: 'Safe' } });
});
