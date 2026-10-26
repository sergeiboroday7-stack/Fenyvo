'use strict';

const { prepareRecoveryKeyRegistration } = require('./server_recovery_key_registration');

function createRecoveryRegistrationFlow({ confirmPassword, saveUsers }) {
  if (typeof confirmPassword !== 'function' || typeof saveUsers !== 'function') throw new TypeError('Invalid recovery dependencies');
  async function registerKey({ username, password, publicKeyHex, users, isSessionActive }) {
    if (typeof username !== 'string' || !username.trim() || !users) return false;
    const account = username.trim();
    const original = users[account];
    if (!original || Object.hasOwn(original, 'recoveryPublicKey')) return false;
    const originalSalt = original.salt;
    const originalHash = original.passwordHash;
    if ((await confirmPassword(original, password)) !== true) return false;
    if (users[account] !== original || original.salt !== originalSalt || original.passwordHash !== originalHash || Object.hasOwn(original, 'recoveryPublicKey')) return false;
    const updatedAccount = prepareRecoveryKeyRegistration(original, publicKeyHex, true);
    const updated = { ...users, [account]: updatedAccount };
    // RECOVERY_ACTIVE_SESSION_CHECK_V1
    if (typeof isSessionActive !== 'function' || isSessionActive() !== true) return false;
    const saved = saveUsers(updated);
    if (saved && typeof saved.then === 'function') throw new Error('Asynchronous persistence is not supported');
    if (saved !== true) throw new Error('Account persistence not confirmed');
    Object.assign(original, updatedAccount);
    return true;
  }
  return Object.freeze({ registerKey });
}

module.exports = { createRecoveryRegistrationFlow };
