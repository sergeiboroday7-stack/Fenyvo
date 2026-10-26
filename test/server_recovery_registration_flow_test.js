'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { createRecoveryRegistrationFlow } = require('../server_recovery_registration_flow');

test('registration verifies the password, persists the key and preserves the profile', async () => {
  const users = {
    alice: {
      salt: 'a'.repeat(32),
      passwordHash: 'b'.repeat(128),
      profile: { about: 'Original' },
    },
  };
  const publicKeyHex = 'c'.repeat(64);
  let persisted;
  const flow = createRecoveryRegistrationFlow({
    confirmPassword: async (user, password) => {
      assert.equal(user, users.alice);
      return password === 'CurrentPassword123!';
    },
    saveUsers: value => {
      persisted = structuredClone(value);
      return true;
    },
  });

  const result = await flow.registerKey({
    username: 'alice',
    password: 'CurrentPassword123!',
    publicKeyHex,
    users,
    isSessionActive: () => true,
  });

  assert.equal(result, true);
  assert.equal(users.alice.recoveryPublicKey, publicKeyHex);
  assert.equal(persisted.alice.recoveryPublicKey, publicKeyHex);
  assert.deepEqual(users.alice.profile, { about: 'Original' });
});

test('registration rejects a wrong password and never persists', async () => {
  const users = { alice: { salt: 'a'.repeat(32), passwordHash: 'b'.repeat(128) } };
  let saveCalls = 0;
  const flow = createRecoveryRegistrationFlow({
    confirmPassword: async () => false,
    saveUsers: () => { saveCalls += 1; return true; },
  });

  const result = await flow.registerKey({
    username: 'alice',
    password: 'WrongPassword123!',
    publicKeyHex: 'c'.repeat(64),
    users,
    isSessionActive: () => true,
  });

  assert.equal(result, false);
  assert.equal(saveCalls, 0);
  assert.equal(Object.hasOwn(users.alice, 'recoveryPublicKey'), false);
});

test('registration cannot silently replace an existing recovery key', async () => {
  const users = {
    alice: {
      salt: 'a'.repeat(32),
      passwordHash: 'b'.repeat(128),
      recoveryPublicKey: 'd'.repeat(64),
    },
  };
  const flow = createRecoveryRegistrationFlow({
    confirmPassword: async () => true,
    saveUsers: () => true,
  });

  const result = await flow.registerKey({
    username: 'alice',
    password: 'CurrentPassword123!',
    publicKeyHex: 'c'.repeat(64),
    users,
    isSessionActive: () => true,
  });

  assert.equal(result, false);
  assert.equal(users.alice.recoveryPublicKey, 'd'.repeat(64));
});
