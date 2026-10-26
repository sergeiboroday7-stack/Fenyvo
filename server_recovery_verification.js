'use strict';

const { verifyRecoverySignature } = require('./server_account_recovery');

function createRecoveryVerifier(store, getRecoveryPublicKey) {
  if (!store || typeof store.consume !== 'function') {
    throw new TypeError('Invalid recovery challenge store');
  }

  if (typeof getRecoveryPublicKey !== 'function') throw new TypeError('Missing trusted key lookup');

  function verifyProof({ username, challengeId, signatureBytes }) {
    if (typeof username !== 'string' || !username.trim()) return false;
    if (typeof challengeId !== 'string' || !/^[0-9a-f]{64}$/.test(challengeId)) return false;
    const account = username.trim();
    const publicKeyBytes = getRecoveryPublicKey(account);
    const message = Buffer.from(`FENYVO/account-password-recovery/v1:${account}:${challengeId}`, 'utf8');
    return verifyRecoverySignature(publicKeyBytes, message, signatureBytes);
  }

  function verifyAndConsume({ username, challengeId, signatureBytes }) {
    if (typeof username !== 'string' || !username.trim()) return false;
    if (typeof challengeId !== 'string' || !/^[0-9a-f]{64}$/.test(challengeId)) return false;
    const message = Buffer.from(`FENYVO/account-password-recovery/v1:${username.trim()}:${challengeId}`, 'utf8');
    const publicKeyBytes = getRecoveryPublicKey(username.trim());
    if (!verifyRecoverySignature(publicKeyBytes, message, signatureBytes)) return false;
    return store.consume(challengeId, username);
  }

  return { verifyAndConsume, verifyProof };
}

module.exports = { createRecoveryVerifier };
