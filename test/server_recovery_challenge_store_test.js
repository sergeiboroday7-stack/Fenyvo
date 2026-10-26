'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createRecoveryChallengeStore } = require('../server_recovery_challenge_store');

test('challenge can be consumed only once', () => {
  const store = createRecoveryChallengeStore();
  const challenge = store.issue('test_user');
  assert.equal(store.consume(challenge.challengeId, 'test_user'), true);
  assert.equal(store.consume(challenge.challengeId, 'test_user'), false);
});

test('another account cannot consume the challenge', () => {
  const store = createRecoveryChallengeStore();
  const challenge = store.issue('test_user');
  assert.equal(store.consume(challenge.challengeId, 'other_user'), false);
  assert.equal(store.consume(challenge.challengeId, 'test_user'), true);
});

test('expired challenge is rejected', () => {
  const originalNow = Date.now;
  let now = originalNow();
  try {
    Date.now = () => now;
    const store = createRecoveryChallengeStore();
    const challenge = store.issue('test_user');
    now = challenge.expiresAt + 1;
    assert.equal(store.consume(challenge.challengeId, 'test_user'), false);
  } finally {
    Date.now = originalNow;
  }
});
