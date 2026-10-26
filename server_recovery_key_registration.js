'use strict';

function prepareRecoveryKeyRegistration(user, publicKeyHex, authenticated) {
  if (authenticated !== true) throw new Error('Authentication required');
  if (!user || typeof user !== 'object' || Array.isArray(user)) throw new TypeError('Invalid account record');
  if (typeof publicKeyHex !== 'string' || !/^[0-9a-f]{64}$/.test(publicKeyHex)) throw new TypeError('Invalid Ed25519 public key');
  if (Object.hasOwn(user, 'recoveryPublicKey')) throw new Error('Recovery key already registered');
  return { ...user, recoveryPublicKey: publicKeyHex };
}

module.exports = { prepareRecoveryKeyRegistration };
