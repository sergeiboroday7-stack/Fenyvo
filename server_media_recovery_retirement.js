'use strict';

function createMediaRecoveryRetirement({
  getQueues,
  saveQueues,
  commitQueues,
  journal
}) {
  const dependencies = {
    getQueues,
    saveQueues,
    commitQueues
  };

  for (const [name, fn] of Object.entries(dependencies)) {
    if (typeof fn !== 'function') {
      throw new TypeError('INVALID_DEPENDENCY: ' + name);
    }
  }

  if (!journal ||
      typeof journal.retire !== 'function') {
    throw new TypeError('RETIREMENT_JOURNAL_REQUIRED');
  }

  const valid = value =>
    typeof value === 'string' &&
    /^[a-zA-Z0-9_-]{1,120}$/.test(value);

  function retireAndRemove(message, authenticatedRecipient) {
    if (!message ||
        typeof message !== 'object' ||
        Array.isArray(message) ||
        !['id', 'mediaId', 'from', 'to'].every(
          key => valid(message[key])
        ) ||
        !valid(authenticatedRecipient) ||
        message.to !== authenticatedRecipient) {
      return {
        removed: false,
        reason: 'INVALID_IDENTITY'
      };
    }

    const queues = getQueues();

    if (!queues ||
        typeof queues !== 'object' ||
        Array.isArray(queues)) {
      throw new Error('INVALID_QUEUE_STATE');
    }

    const existing = queues[authenticatedRecipient];

    if (!Array.isArray(existing)) {
      return {
        removed: false,
        reason: 'NOT_PENDING'
      };
    }

    const matches = existing.filter(item =>
      item &&
      !item.__eventType &&
      item.id === message.id
    );

    if (matches.length !== 1) {
      return {
        removed: false,
        reason: matches.length > 1
          ? 'AMBIGUOUS_MESSAGE'
          : 'NOT_PENDING'
      };
    }

    const stored = matches[0];

    if (stored.id !== message.id ||
        stored.mediaId !== message.mediaId ||
        stored.from !== message.from ||
        stored.to !== message.to) {
      return {
        removed: false,
        reason: 'MESSAGE_MISMATCH'
      };
    }

    const nextRecipientQueue = existing.filter(
      item => item !== stored
    );

    const nextQueues = {
      ...queues
    };

    if (nextRecipientQueue.length === 0) {
      delete nextQueues[authenticatedRecipient];
    } else {
      nextQueues[authenticatedRecipient] =
        nextRecipientQueue;
    }

    // Fail closed. Do not delete from the queue when retirement
    // cannot be recorded successfully.
    journal.retire({
      id: stored.id,
      mediaId: stored.mediaId,
      from: stored.from,
      to: stored.to
    });

    // Persist complete next state before changing active RAM.
    saveQueues(nextQueues);
    commitQueues(nextQueues);

    return {
      removed: true,
      proofRetired: true
    };
  }

  return Object.freeze({
    retireAndRemove
  });
}

module.exports = {
  createMediaRecoveryRetirement
};