'use strict';

function createMediaRecoveryPolicy({
  getPending,
  getMedia,
  getGrant,
  hasTrustedProof,
  addRecipient
}) {
  const dependencies = {
    getPending,
    getMedia,
    getGrant,
    hasTrustedProof,
    addRecipient
  };

  for (const [name, value] of Object.entries(dependencies)) {
    if (typeof value !== 'function') {
      throw new TypeError('INVALID_DEPENDENCY: ' + name);
    }
  }

  const valid = value =>
    typeof value === 'string' &&
    /^[a-zA-Z0-9_-]{1,120}$/.test(value);

  function sameMessage(a, b) {
    return Boolean(a && b &&
      ['id', 'mediaId', 'from', 'to'].every(
        key => valid(a[key]) && a[key] === b[key]
      ));
  }

  function repair(message, authenticatedRecipient) {
    if (!message || typeof message !== 'object' ||
        !valid(authenticatedRecipient) ||
        !['id', 'mediaId', 'from', 'to'].every(
          key => valid(message[key])
        ) ||
        message.to !== authenticatedRecipient) {
      return { repaired: false, reason: 'INVALID_IDENTITY' };
    }

    // Only a server-owned queue can establish the pending message.
    const pending = getPending(authenticatedRecipient);
    if (!Array.isArray(pending) ||
        !pending.some(entry => sameMessage(entry, message))) {
      return { repaired: false, reason: 'NOT_PENDING' };
    }

    const media = getMedia(message.mediaId);
    if (!media || media.owner !== message.from) {
      return { repaired: false, reason: 'OWNER_MISMATCH' };
    }

    const grant = getGrant(message.mediaId);

    if (grant?.revoked === true) {
      return { repaired: false, reason: 'REVOKED' };
    }

    if (grant?.groupId) {
      return { repaired: false, reason: 'GROUP_GRANT' };
    }

    if (grant?.expiresAt != null &&
        (!Number.isSafeInteger(grant.expiresAt) ||
         Date.now() >= grant.expiresAt)) {
      return { repaired: false, reason: 'EXPIRED' };
    }

    if (grant?.recipients?.includes(authenticatedRecipient)) {
      return { repaired: false, alreadyAllowed: true };
    }

    // Missing authorization can be repaired only with trusted proof.
    // This callback must read server-owned durable evidence.
    // Never resolve proof from client message fields alone.
    if (hasTrustedProof(message) !== true) {
      return { repaired: false, reason: 'NO_TRUSTED_PROOF' };
    }

    // Store controls revocation and durable persistence.
    addRecipient(message.mediaId, authenticatedRecipient);

    return { repaired: true };
  }

  return Object.freeze({ repair });
}

module.exports = { createMediaRecoveryPolicy };