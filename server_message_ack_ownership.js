'use strict';

function verifyMessageAckOwnership({
  authenticatedUser,
  messageId,
  from,
  to,
  queue,
}) {
  if (
    typeof authenticatedUser !== 'string' ||
    typeof messageId !== 'string' ||
    typeof from !== 'string' ||
    typeof to !== 'string' ||
    !authenticatedUser.trim() ||
    !messageId.trim() ||
    !from.trim() ||
    !to.trim()
  ) {
    return { allowed: false, reason: 'invalid' };
  }

  if (authenticatedUser !== to) {
    return { allowed: false, reason: 'forbidden' };
  }

  if (!Array.isArray(queue)) {
    return { allowed: false, reason: 'not_found' };
  }

  const matches = queue.filter(item =>
    item &&
    !item.__eventType &&
    item.id === messageId
  );

  if (matches.length !== 1) {
    return {
      allowed: false,
      reason: matches.length > 1 ? 'ambiguous' : 'not_found',
    };
  }

  const stored = matches[0];

  if (stored.from !== from || stored.to !== to) {
    return { allowed: false, reason: 'identity_mismatch' };
  }

  return { allowed: true };
}

module.exports = { verifyMessageAckOwnership };