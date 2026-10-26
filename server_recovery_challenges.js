'use strict';

const crypto = require('node:crypto');

const CHALLENGE_TTL_MS = 5 * 60 * 1000;

function createRecoveryChallenge(username) {
  if (typeof username !== 'string' || !username.trim()) {
    throw new TypeError('Invalid account identifier');
  }
  const account = username.trim();
  const challengeId = crypto.randomBytes(32).toString('hex');
  const expiresAt = Date.now() + CHALLENGE_TTL_MS;
  return {
    challengeId,
    username: account,
    purpose: 'account-password-recovery',
    expiresAt,
  };
}

module.exports = { createRecoveryChallenge, CHALLENGE_TTL_MS };
