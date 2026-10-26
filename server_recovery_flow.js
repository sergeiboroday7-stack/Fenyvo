'use strict';

function createRecoveryFlow({ verifyProof, hashPassword, saveUsers }) {
  if (typeof verifyProof !== 'function') throw new TypeError('Missing proof verifier');
  if (typeof hashPassword !== 'function') throw new TypeError('Missing password hasher');
  if (typeof saveUsers !== 'function') throw new TypeError('Missing account persistence');
  async function prepareAndSave({ username, newPassword, users }) {
    if (typeof username !== 'string' || !username.trim()) throw new TypeError('Invalid account identifier');
    if (typeof newPassword !== 'string' || !newPassword) throw new TypeError('Invalid new password');
    if (!users || !Object.hasOwn(users, username.trim())) throw new Error('Account unavailable');
    const passwordData = await hashPassword(newPassword);
    const { prepareRecoveryPasswordUpdate } = require('./server_recovery_password');
    const account = username.trim();
    const updated = { ...users, [account]: prepareRecoveryPasswordUpdate(users[account], passwordData) };
    const saved = await saveUsers(updated);
    if (saved !== true) throw new Error('Account persistence not confirmed');
    return updated;
  }

  async function recoverPassword({ username, challengeId, signatureBytes, newPassword, users, store, lock }) {
    if (!store || typeof store.reserve !== 'function' || typeof store.commit !== 'function') throw new TypeError('Invalid challenge store');
    if (!lock || typeof lock.run !== 'function') throw new TypeError('Invalid recovery lock');
    if (typeof username !== 'string' || !username.trim()) return false;
    const account = username.trim();
    return lock.run(account, async () => {
      if (!users || !Object.hasOwn(users, account)) return false;
      if (typeof newPassword !== 'string' || !newPassword || newPassword.length > 128) return false;
      if ((await verifyProof({ username: account, challengeId, signatureBytes })) !== true) return false;
      const token = store.reserve(challengeId, account);
      if (!token) return false;
      const original = users[account];
      const originalSalt = original.salt;
      const originalHash = original.passwordHash;
      let updated;
      try {
        const passwordData = await hashPassword(newPassword);
        const { prepareRecoveryPasswordUpdate } = require('./server_recovery_password');
        if (users[account] !== original || original.salt !== originalSalt || original.passwordHash !== originalHash) { throw new Error('Account changed during recovery'); }
        const current = users[account];
        const updatedAccount = prepareRecoveryPasswordUpdate(current, passwordData);
        updated = { ...users, [account]: updatedAccount };
        const saved = saveUsers(updated);
        if (saved && typeof saved.then === 'function') throw new Error('Asynchronous recovery persistence is not supported');
        if (saved !== true) throw new Error('Account persistence not confirmed');
        Object.assign(current, updatedAccount);
      } catch (error) {
        store.release(challengeId, token);
        throw error;
      }
      if (store.commit(challengeId, token) !== true) throw new Error('Recovery challenge commit failed');
      return updated;
    });
  }

  return Object.freeze({ ready: true, recoverPassword });
}

module.exports = { createRecoveryFlow };
