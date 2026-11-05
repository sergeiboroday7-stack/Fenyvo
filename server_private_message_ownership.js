'use strict';

const fs = require('node:fs');
const path = require('node:path');

function createPrivateMessageOwnership({ filePath }) {
  if (typeof filePath !== 'string' || !filePath.trim()) {
    throw new TypeError('OWNERSHIP_PATH_REQUIRED');
  }

  function isValid(identity) {
    return identity &&
      typeof identity === 'object' &&
      !Array.isArray(identity) &&
      [identity.id, identity.from, identity.to].every(
        value => typeof value === 'string' &&
          value.length > 0 &&
          value === value.trim()
      );
  }

  function keyOf(identity) {
    if (!isValid(identity)) {
      throw new TypeError('INVALID_MESSAGE_IDENTITY');
    }

    return JSON.stringify([
      identity.from,
      identity.to,
      identity.id
    ]);
  }

  let records;

  if (fs.existsSync(filePath)) {
    records = JSON.parse(fs.readFileSync(filePath, 'utf8'));

    if (!records ||
        typeof records !== 'object' ||
        Array.isArray(records)) {
      throw new Error('INVALID_OWNERSHIP_STORE');
    }

    for (const [key, record] of Object.entries(records)) {
      if (!isValid(record) || keyOf(record) !== key) {
        throw new Error('INVALID_OWNERSHIP_RECORD');
      }
    }
  } else {
    records = {};
  }

  function persist(next) {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });

    const tempPath = filePath + '.pending-' +
      process.pid + '-' +
      require('node:crypto').randomBytes(8).toString('hex');

    try {
      fs.writeFileSync(
        tempPath,
        JSON.stringify(next, null, 2),
        { encoding: 'utf8', flag: 'wx' }
      );

      // Flush ownership records before atomic replacement.
      const durabilityFd = fs.openSync(tempPath, 'r+');
      try {
        fs.fsyncSync(durabilityFd);
      } finally {
        fs.closeSync(durabilityFd);
      }
      fs.renameSync(tempPath, filePath);
    } finally {
      try {
        if (fs.existsSync(tempPath)) fs.unlinkSync(tempPath);
      } catch {}
    }
  }

  function remember(identity) {
    const key = keyOf(identity);
    const previous = records[key];

    if (previous) {
      return { accepted: true, duplicate: true };
    }

    const record = {
      id: identity.id,
      from: identity.from,
      to: identity.to
    };

    const next = {
      ...records,
      [key]: record
    };

    persist(next);
    records = next;

    return { accepted: true, duplicate: false };
  }

  function resolve(messageId) {
    if (typeof messageId !== 'string' ||
        !messageId.trim()) return null;

    const matches = Object.values(records).filter(
      item => item.id === messageId
    );

    // An ID may be reused in different conversations.
    // Never guess ownership when the ID is ambiguous.
    if (matches.length !== 1) return null;

    return { ...matches[0] };
  }

  function verify({ messageId, from, to, actor, action }) {
    if (![messageId, from, to, actor, action].every(
      value => typeof value === 'string' && value.trim()
    )) {
      return { allowed: false, reason: 'invalid' };
    }

    const record = resolve(messageId);

    if (!record) {
      return { allowed: false, reason: 'not_found_or_ambiguous' };
    }

    if (record.from !== from || record.to !== to) {
      return { allowed: false, reason: 'identity_mismatch' };
    }

    if (action === 'edit' || action === 'delete') {
      return actor === record.from
        ? { allowed: true }
        : { allowed: false, reason: 'not_sender' };
    }

    if (action === 'read') {
      return actor === record.to
        ? { allowed: true }
        : { allowed: false, reason: 'not_recipient' };
    }

    if (action === 'reaction' || action === 'pin') {
      return actor === record.from || actor === record.to
        ? { allowed: true }
        : { allowed: false, reason: 'not_participant' };
    }

    return { allowed: false, reason: 'unknown_action' };
  }

  return Object.freeze({
    remember,
    resolve,
    verify
  });
}

module.exports = { createPrivateMessageOwnership };