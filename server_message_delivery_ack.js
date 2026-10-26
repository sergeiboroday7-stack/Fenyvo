'use strict';

function createMessageDeliveryAck({
  transaction,
  getAuthenticatedUser,
}) {
  if (!transaction ||
      typeof transaction.get !== 'function' ||
      typeof transaction.markDelivered !== 'function') {
    throw new TypeError('Invalid transaction dependency');
  }

  if (typeof getAuthenticatedUser !== 'function') {
    throw new TypeError('Authentication dependency required');
  }

  function acknowledge(socket, data) {
    const user = getAuthenticatedUser(socket);

    if (typeof user !== 'string' || !user.trim()) {
      return { accepted: false, reason: 'unauthenticated' };
    }

    if (!data || typeof data !== 'object' ||
        Array.isArray(data) ||
        typeof data.messageId !== 'string' ||
        typeof data.from !== 'string' ||
        typeof data.to !== 'string' ||
        !data.messageId.trim() ||
        !data.from.trim() ||
        !data.to.trim()) {
      return { accepted: false, reason: 'invalid' };
    }

    if (data.to !== user) {
      return { accepted: false, reason: 'forbidden' };
    }

    const identity = {
      id: data.messageId,
      from: data.from,
      to: user,
    };

    const record = transaction.get(identity);

    if (!record ||
        record.from !== data.from ||
        record.to !== user ||
        record.id !== data.messageId) {
      return { accepted: false, reason: 'not_found' };
    }

    if (record.status === 'delivered') {
      return { accepted: true, duplicate: true };
    }

    if (record.status !== 'pending') {
      return { accepted: false, reason: 'invalid_state' };
    }

    const success = transaction.markDelivered(identity, user);

    return success
      ? { accepted: true, duplicate: false }
      : { accepted: false, reason: 'not_found' };
  }

  return { acknowledge };
}

module.exports = { createMessageDeliveryAck };