'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createRecoveryChallenge, CHALLENGE_TTL_MS } = require('../server_recovery_challenges');

test('challenge has correct account, purpose and expiry', () => {
  const before = Date.now();
  const challenge = createRecoveryChallenge(' test_user ');
  const after = Date.now();
  assert.equal(challenge.username, 'test_user');
  assert.equal(challenge.purpose, 'account-password-recovery');
  assert.match(challenge.challengeId, /^[0-9a-f]{64}$/);
  assert.ok(challenge.expiresAt >= before + CHALLENGE_TTL_MS);
  assert.ok(challenge.expiresAt <= after + CHALLENGE_TTL_MS);
});

test('each challenge has a unique identifier', () => {
  const first = createRecoveryChallenge('test_user');
  const second = createRecoveryChallenge('test_user');
  assert.notEqual(first.challengeId, second.challengeId);
});

test('invalid account identifiers are rejected', () => {
  assert.throws(() => createRecoveryChallenge('   '), TypeError);
  assert.throws(() => createRecoveryChallenge(null), TypeError);
});
