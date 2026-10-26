'use strict';

function createRecoveryReauth(verifyPassword) {
  if (typeof verifyPassword !== 'function') throw new TypeError('Missing password verifier');

  async function confirmPassword(user, password) {
    if (!user || typeof user !== 'object' || Array.isArray(user)) return false;
    if (typeof password !== 'string' || !password || password.length > 128) return false;
    if (typeof user.salt !== 'string' || typeof user.passwordHash !== 'string') return false;
    try {
      return (await verifyPassword(password, user.salt, user.passwordHash)) === true;
    } catch (_) {
      return false;
    }
  }

  return Object.freeze({ confirmPassword });
}

module.exports = { createRecoveryReauth };
