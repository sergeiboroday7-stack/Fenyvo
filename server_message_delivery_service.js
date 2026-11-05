'use strict';

function createMessageDeliveryService({
    afterPersist = null,
  queueMessage,
  getRecipientSocket,
  sendMessage,
  isSocketOpen,
  notifyOffline = () => {},
  pendingFor = null,
}) {
  for (const [name, fn] of Object.entries({
    queueMessage,
    getRecipientSocket,
    sendMessage,
    isSocketOpen,
    notifyOffline,
  })) {
    if (typeof fn !== 'function') {
      throw new TypeError(`Invalid delivery dependency: ${name}`);
    }
  }

  function deliver(message, context = null) {
    if (!message || typeof message !== 'object' ||
        typeof message.to !== 'string' || !message.to) {
      throw new TypeError('Invalid delivery message');
    }

    // Queue first: do not attempt online delivery
    // if persistence has failed.
    const acceptance = queueMessage(message.to, message);

    if (acceptance?.conflict === true) {
      return {
        queued: false,
        online: false,
        conflict: true,
      };
    }

    // The message is durable (or an identical durable message
    // already exists). Complete side effects before online delivery.
    // Throwing here prevents sending/acknowledging the message.
    if (typeof afterPersist === 'function') {
      afterPersist(message, acceptance, context);
    } else if (message.mediaId) {
      throw new Error('MEDIA_GRANT_COMMIT_HOOK_REQUIRED');
    }
    if (acceptance?.duplicate === true) {
      return {
        queued: true,
        online: false,
        duplicate: true,
      };
    }

    const recipientSocket = getRecipientSocket(message.to);

    if (recipientSocket && isSocketOpen(recipientSocket)) {
      sendMessage(recipientSocket, 'message', message);

      return {
        queued: true,
        online: true,
      };
    }

    notifyOffline(message.to, message);

    return {
      queued: true,
      online: false,
    };
  }

  function redeliverPending(authenticatedRecipient) {
    if (typeof pendingFor !== 'function') {
      throw new Error('Pending-message source not configured');
    }

    if (typeof authenticatedRecipient !== 'string' ||
        !authenticatedRecipient.trim()) {
      throw new TypeError('Authenticated recipient required');
    }

    // Caller must supply recipient identity from the
    // authenticated WebSocket session, never client payload.
    const socket = getRecipientSocket(authenticatedRecipient);

    if (!socket || !isSocketOpen(socket)) {
      return 0;
    }

    const pending = pendingFor(authenticatedRecipient);

    if (!Array.isArray(pending)) {
      throw new TypeError('Invalid pending-message list');
    }

    let sent = 0;

    for (const item of pending) {
      if (!item || item.to !== authenticatedRecipient) {
        throw new Error('Pending-message recipient mismatch');
      }

      // A persisted media message may have failed its grant commit.
      // Re-establish the grant before allowing replay.
      // STEP_404_REPLAY_OWNERSHIP_GUARD_BEGIN
      // Repair/check ownership for every replayed message, not just media.
      // Media must also retain its existing grant-commit guard.
      if (item.mediaId || typeof afterPersist === 'function') {
        if (typeof afterPersist !== 'function') {
          continue;
        }

        try {
          afterPersist(item, { duplicate: true, replay: true });
        } catch (_) {
          // Leave the message pending if ownership or media commit fails.
          continue;
        }
      }
      // STEP_404_REPLAY_OWNERSHIP_GUARD_END

      sendMessage(socket, 'message', item);
      sent++;
    }

    return sent;
  }

  return { deliver, redeliverPending };
}

module.exports = { createMessageDeliveryService };