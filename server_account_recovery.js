'use strict';

const crypto = require('node:crypto');

function verifyRecoverySignature(publicKeyBytes, messageBytes, signatureBytes) {
  if (!Buffer.isBuffer(publicKeyBytes) || publicKeyBytes.length !== 32) return false;
  if (!Buffer.isBuffer(messageBytes) || messageBytes.length === 0) return false;
  if (!Buffer.isBuffer(signatureBytes) || signatureBytes.length !== 64) return false;
  try {
    const spkiPrefix = Buffer.from('302a300506032b6570032100', 'hex');
    const publicKey = crypto.createPublicKey({
      key: Buffer.concat([spkiPrefix, publicKeyBytes]),
      format: 'der',
      type: 'spki',
    });
    return crypto.verify(null, messageBytes, publicKey, signatureBytes);
  } catch (_) {
    return false;
  }
}

module.exports = { verifyRecoverySignature };
