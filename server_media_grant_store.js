'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const MAX_GRANT_FILE_BYTES = 4 * 1024 * 1024;
const MAX_GRANTS = 100000;
const MAX_RECIPIENTS = 10000;

function createMediaGrantStore({ filePath, allowedRoot }) {
  if (typeof filePath !== 'string' ||
      typeof allowedRoot !== 'string' ||
      !path.isAbsolute(filePath) ||
      !path.isAbsolute(allowedRoot)) {
    throw new TypeError('Trusted absolute paths required');
  }

  const root = fs.realpathSync(allowedRoot);
  const parent = fs.realpathSync(path.dirname(filePath));
  const actualPath = path.join(parent, path.basename(filePath));

  if (parent !== root &&
      !parent.startsWith(root + path.sep)) {
    throw new Error('GRANTS_STORAGE_OUTSIDE_ROOT');
  }

  if (fs.existsSync(actualPath) &&
      !fs.lstatSync(actualPath).isFile()) {
    throw new Error('GRANTS_STORAGE_INVALID_FILE');
  }

  const grants = new Map();

  function validId(id) {
    return typeof id === 'string' &&
      /^[a-zA-Z0-9_-]{1,120}$/.test(id);
  }

  function validUser(user) {
    return typeof user === 'string' &&
      user.length > 0 &&
      user.length <= 120 &&
      !/[\u0000-\u001f]/.test(user);
  }

  function normalize(raw) {
    if (!raw || typeof raw !== 'object' ||
        Array.isArray(raw)) {
      throw new TypeError('INVALID_GRANT');
    }

    const recipients = raw.recipients === undefined
      ? []
      : raw.recipients;

    if (!Array.isArray(recipients) ||
        recipients.length > MAX_RECIPIENTS ||
        !recipients.every(validUser)) {
      throw new Error('GRANT_RECIPIENTS_INVALID_OR_TOO_MANY');
    }

    if (raw.groupId != null && !validId(raw.groupId)) {
      throw new Error('INVALID_GROUP_ID');
    }

    if (raw.expiresAt != null &&
        (!Number.isSafeInteger(raw.expiresAt) ||
         raw.expiresAt <= 0)) {
      throw new Error('INVALID_EXPIRATION');
    }

    return {
      recipients: [...new Set(recipients)],
      groupId: raw.groupId || null,
      expiresAt: raw.expiresAt || null,
      revoked: raw.revoked === true,
    };
  }

  function load() {
    if (!fs.existsSync(actualPath)) return;

    const stat = fs.statSync(actualPath);
    if (stat.size > MAX_GRANT_FILE_BYTES) {
      throw new Error('GRANTS_STORAGE_FILE_TOO_LARGE');
    }

    let parsed;
    try {
      parsed = JSON.parse(fs.readFileSync(actualPath, 'utf8'));
    } catch (_) {
      throw new Error('GRANTS_STORAGE_UNREADABLE');
    }

    if (!parsed || parsed.version !== 1 ||
        !Array.isArray(parsed.grants)) {
      throw new Error('GRANTS_STORAGE_INVALID');
    }

    if (parsed.grants.length > MAX_GRANTS) {
      throw new Error('GRANTS_STORAGE_TOO_MANY_ENTRIES');
    }

    for (const entry of parsed.grants) {
      if (!Array.isArray(entry) || entry.length !== 2 ||
          !validId(entry[0]) || grants.has(entry[0])) {
        throw new Error('GRANTS_STORAGE_INVALID');
      }
      grants.set(entry[0], normalize(entry[1]));
    }
  }

  function persist() {
    const serialized = JSON.stringify({
      version: 1,
      grants: [...grants],
    });

    if (Buffer.byteLength(serialized, 'utf8') >
        MAX_GRANT_FILE_BYTES) {
      throw new Error('GRANTS_STORAGE_FILE_TOO_LARGE');
    }

    const tmp = path.join(
      parent,
      `.grants-${crypto.randomUUID()}.tmp`
    );

    try {
      fs.writeFileSync(tmp, serialized, {
        flag: 'wx',
        mode: 0o600,
      });
      fs.renameSync(tmp, actualPath);
    } finally {
      try { fs.unlinkSync(tmp); } catch (_) {}
    }
  }

  function update(id, raw) {
    if (!validId(id)) throw new TypeError('Invalid media ID');

    const value = normalize(raw);
    const previous = grants.get(id);

    if (!previous && grants.size >= MAX_GRANTS) {
      throw new Error('GRANTS_STORAGE_TOO_MANY_ENTRIES');
    }

    grants.set(id, value);

    try {
      persist();
    } catch (error) {
      if (previous) grants.set(id, previous);
      else grants.delete(id);
      throw error;
    }
  }

  function getGrant(id) {
    if (!validId(id)) return null;
    const value = grants.get(id);
    return value ? {
      ...value,
      recipients: [...value.recipients],
    } : null;
  }

  function addRecipient(id, user) {
    if (!validId(id) || !validUser(user)) {
      throw new TypeError('Invalid identity');
    }

    const grant = getGrant(id) || {
      recipients: [],
      groupId: null,
      expiresAt: null,
      revoked: false,
    };

    if (grant.revoked) throw new Error('GRANT_REVOKED');

    if (!grant.recipients.includes(user)) {
      grant.recipients.push(user);
    }

    update(id, grant);
  }

  function allowGroup(id, groupId) {
    if (!validId(groupId)) {
      throw new TypeError('Invalid group');
    }

    const grant = getGrant(id) || {
      recipients: [],
      groupId: null,
      expiresAt: null,
      revoked: false,
    };

    if (grant.revoked) throw new Error('GRANT_REVOKED');
    grant.groupId = groupId;
    update(id, grant);
  }

  function revoke(id) {
    const grant = getGrant(id) || {
      recipients: [],
      groupId: null,
      expiresAt: null,
      revoked: false,
    };

    grant.revoked = true;
    update(id, grant);
  }

  load();

  return Object.freeze({
    getGrant,
    addRecipient,
    allowGroup,
    revoke,
    update,
  });
}

module.exports = {
  createMediaGrantStore,
  MAX_GRANT_FILE_BYTES,
  MAX_RECIPIENTS,
};