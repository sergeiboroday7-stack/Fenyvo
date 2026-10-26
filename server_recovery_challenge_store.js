'use strict';

const { createRecoveryChallenge } = require('./server_recovery_challenges');
const crypto = require('node:crypto');

function createRecoveryChallengeStore() {
  const pending = new Map();
  const MAX_PENDING = 1000;

  function issue(username) {
    const now = Date.now();
    for (const [id, item] of pending) {
      if (item.expiresAt <= now && !reservations.has(id)) { pending.delete(id); }
    }
    if (pending.size >= MAX_PENDING) {
      throw new Error('Recovery challenge capacity exceeded');
    }
    const challenge = createRecoveryChallenge(username);
    pending.set(challenge.challengeId, challenge);
    return { ...challenge };
  }

  function consume(challengeId, username) {
    if (typeof challengeId !== 'string' || typeof username !== 'string') return false;
    const challenge = pending.get(challengeId);
    if (!challenge) return false;
    if (reservations.has(challengeId)) return false;
    if (challenge.expiresAt <= Date.now()) {
      pending.delete(challengeId);
      return false;
    }
    if (challenge.username !== username.trim()) return false;
    pending.delete(challengeId);
    return true;
  }

  const reservations = new Map();

  function reserve(challengeId, username) {
    if (typeof challengeId !== 'string' || typeof username !== 'string') return null;
    const item = pending.get(challengeId);
    if (!item || item.username !== username.trim() || reservations.has(challengeId)) return null;
    if (item.expiresAt <= Date.now()) { pending.delete(challengeId); return null; }
    const token = crypto.randomBytes(32).toString('hex');
    reservations.set(challengeId, token);
    return token;
  }

  function commit(challengeId, token) {
    if (!token || reservations.get(challengeId) !== token) return false;
    reservations.delete(challengeId);
    pending.delete(challengeId);
    return true;
  }

  function release(challengeId, token) {
    if (!token || reservations.get(challengeId) !== token) return false;
    reservations.delete(challengeId);
    return true;
  }

  return { issue, consume, reserve, commit, release };
}

module.exports = { createRecoveryChallengeStore };
