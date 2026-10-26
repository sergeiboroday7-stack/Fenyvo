'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const { prepareRecoveryPasswordUpdate } = require('../server_recovery_password');
const { createRecoveryFlow } = require('../server_recovery_flow');

function createStore() {
  let reserved = false;
  let committed = false;
  return {
    reserve(challengeId, username) {
      if (reserved || committed || challengeId !== 'challenge' || username !== 'alice') return null;
      reserved = true;
      return 'token';
    },
    commit(challengeId, token) {
      if (!reserved || challengeId !== 'challenge' || token !== 'token') return false;
      reserved = false;
      committed = true;
      return true;
    },
    release(challengeId, token) {
      if (!reserved || challengeId !== 'challenge' || token !== 'token') return false;
      reserved = false;
      return true;
    },
    get committed() { return committed; },
    get reserved() { return reserved; },
  };
}

test('recovery flow persists and applies the new password exactly once', async () => {
  const users = {
    alice: {
      salt: 'a'.repeat(32),
      passwordHash: 'b'.repeat(128),
      recoveryPublicKey: 'e'.repeat(64),
      profile: { about: 'Original' },
    },
  };
  const store = createStore();
  let persisted;
  const flow = createRecoveryFlow({
    verifyProof: async () => true,
    hashPassword: async password => {
      assert.equal(password, 'NewPassword123!');
      return { salt: 'c'.repeat(32), hash: 'd'.repeat(128) };
    },
    saveUsers: value => {
      persisted = structuredClone(value);
      return true;
    },
  });

  const result = await flow.recoverPassword({
    username: 'alice',
    challengeId: 'challenge',
    signatureBytes: Buffer.alloc(64),
    newPassword: 'NewPassword123!',
    users,
    store,
    lock: { run: async (_username, operation) => operation() },
  });

  assert.equal(result.alice.passwordHash, 'd'.repeat(128));
  assert.equal(persisted.alice.passwordHash, 'd'.repeat(128));
  assert.equal(users.alice.passwordHash, 'd'.repeat(128));
  assert.equal(users.alice.salt, 'c'.repeat(32));
  assert.deepEqual(users.alice.profile, { about: 'Original' });
  assert.equal(store.committed, true);

  const replay = await flow.recoverPassword({
    username: 'alice',
    challengeId: 'challenge',
    signatureBytes: Buffer.alloc(64),
    newPassword: 'AnotherPassword123!',
    users,
    store,
    lock: { run: async (_username, operation) => operation() },
  });
  assert.equal(replay, false);
});

test('recovery flow keeps the active password when persistence fails', async () => {
  const users = { alice: { salt: 'a'.repeat(32), passwordHash: 'b'.repeat(128) } };
  const store = createStore();
  const flow = createRecoveryFlow({
    verifyProof: async () => true,
    hashPassword: async () => ({ salt: 'c'.repeat(32), hash: 'd'.repeat(128) }),
    saveUsers: () => { throw new Error('disk unavailable'); },
  });

  await assert.rejects(
    flow.recoverPassword({
      username: 'alice',
      challengeId: 'challenge',
      signatureBytes: Buffer.alloc(64),
      newPassword: 'NewPassword123!',
      users,
      store,
      lock: { run: async (_username, operation) => operation() },
    }),
    /disk unavailable/,
  );
  assert.equal(users.alice.salt, 'a'.repeat(32));
  assert.equal(users.alice.passwordHash, 'b'.repeat(128));
  assert.equal(store.committed, false);
  assert.equal(store.reserved, false);
});

test('failed persistence leaves original password unchanged', () => {
  const user = { salt: 'a'.repeat(32), passwordHash: 'b'.repeat(128), profile: { about: 'Original' } };
  const original = structuredClone(user);
  const newPassword = { salt: 'c'.repeat(32), hash: 'd'.repeat(128) };
  const prepared = prepareRecoveryPasswordUpdate(user, newPassword);
  assert.throws(() => { throw new Error('simulated save failure'); }, /simulated save failure/);
  assert.deepEqual(user, original);
  assert.notEqual(prepared.passwordHash, user.passwordHash);
});

test("persists updated password and preserves profile", () => {
  const fs = require("node:fs");
  const os = require("node:os");
  const path = require("node:path");
  const { saveRecoveryJsonAtomic } = require("../server_recovery_storage");
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "fenyvo-recovery-flow-"));
  try {
    const file = path.join(dir, "users.json");
    const users = { alice: { salt: "a".repeat(32), passwordHash: "b".repeat(128), profile: { about: "Original" } } };
    fs.writeFileSync(file, JSON.stringify(users));
    const prepared = prepareRecoveryPasswordUpdate(users.alice, { salt: "c".repeat(32), hash: "d".repeat(128) });
    saveRecoveryJsonAtomic(file, { ...users, alice: prepared });
    const saved = JSON.parse(fs.readFileSync(file, "utf8"));
    assert.equal(saved.alice.passwordHash, "d".repeat(128));
    assert.deepEqual(saved.alice.profile, users.alice.profile);
    assert.equal(users.alice.passwordHash, "b".repeat(128));
  } finally { fs.rmSync(dir, { recursive: true, force: true }); }
});

test("rename failure preserves stored password", () => {
  const fs = require("node:fs");
  const os = require("node:os");
  const path = require("node:path");
  const { saveRecoveryJsonAtomic } = require("../server_recovery_storage");
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "fenyvo-recovery-flow-"));
  const originalRename = fs.renameSync;
  try {
    const file = path.join(dir, "users.json");
    const users = { alice: { salt: "a".repeat(32), passwordHash: "b".repeat(128), profile: { about: "Original" } } };
    fs.writeFileSync(file, JSON.stringify(users));
    const prepared = prepareRecoveryPasswordUpdate(users.alice, { salt: "c".repeat(32), hash: "d".repeat(128) });
    fs.renameSync = () => { throw new Error("simulated rename failure"); };
    assert.throws(() => saveRecoveryJsonAtomic(file, { ...users, alice: prepared }), /simulated rename failure/);
    const saved = JSON.parse(fs.readFileSync(file, "utf8"));
    assert.deepEqual(saved, users);
    assert.deepEqual(fs.readdirSync(dir), ["users.json"]);
  } finally {
    fs.renameSync = originalRename;
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
