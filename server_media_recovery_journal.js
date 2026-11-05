'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const FIELDS = ['id', 'mediaId', 'from', 'to'];
const VALID_ID = /^[a-zA-Z0-9_-]{1,120}$/;
const MAX_BYTES = 1024 * 1024;
const MAX_ENTRIES = 5000;

function createMediaRecoveryJournal({ filePath, key }) {
  if (typeof filePath !== 'string' ||
      !path.isAbsolute(filePath) ||
      typeof key !== 'string' ||
      !/^[a-f0-9]{64}$/i.test(key)) {
    throw new TypeError('TRUSTED_JOURNAL_CONFIGURATION_REQUIRED');
  }

  const secret = Buffer.from(key, 'hex');

  function normalize(item) {
    if (!item || typeof item !== 'object' ||
        !FIELDS.every(field =>
          typeof item[field] === 'string' &&
          VALID_ID.test(item[field]))) {
      throw new Error('INVALID_RECOVERY_ENTRY');
    }

    return Object.fromEntries(
      FIELDS.map(field => [field, item[field]])
    );
  }

  function signature(entry) {
    return crypto.createHmac('sha256', secret)
      .update(JSON.stringify(entry))
      .digest('hex');
  }

  function identity(entry) {
    return JSON.stringify(normalize(entry));
  }

  function load() {
    if (!fs.existsSync(filePath)) return [];

    const stat = fs.lstatSync(filePath);

    if (!stat.isFile() || stat.size > MAX_BYTES) {
      throw new Error('INVALID_JOURNAL_FILE');
    }

    const payload = JSON.parse(
      fs.readFileSync(filePath, 'utf8')
    );

    if (!payload || payload.version !== 2 ||
        !Array.isArray(payload.entries) ||
        payload.entries.length > MAX_ENTRIES) {
      throw new Error('INVALID_JOURNAL_FORMAT');
    }

    const entries = [];
    const seen = new Set();

    for (const stored of payload.entries) {
      const core = normalize(stored);

      if (stored.status !== 'active' &&
          stored.status !== 'retired') {
        throw new Error('INVALID_JOURNAL_STATUS');
      }

      const signed = {
        ...core,
        status: stored.status
      };

      if (typeof stored.signature !== 'string' ||
          !/^[a-f0-9]{64}$/i.test(stored.signature)) {
        throw new Error('INVALID_JOURNAL_SIGNATURE');
      }

      const actual = Buffer.from(stored.signature, 'hex');
      const expected = Buffer.from(signature(signed), 'hex');

      if (!crypto.timingSafeEqual(actual, expected)) {
        throw new Error('INVALID_JOURNAL_SIGNATURE');
      }

      const id = identity(core);

      if (seen.has(id)) {
        throw new Error('DUPLICATE_JOURNAL_ENTRY');
      }

      seen.add(id);
      entries.push(signed);
    }

    return entries;
  }

  function persist(entries) {
    if (entries.length > MAX_ENTRIES) {
      throw new Error('JOURNAL_FULL');
    }

    const content = JSON.stringify({
      version: 2,
      entries: entries.map(entry => ({
        ...entry,
        signature: signature(entry)
      }))
    });

    if (Buffer.byteLength(content) > MAX_BYTES) {
      throw new Error('JOURNAL_TOO_LARGE');
    }

    const tmp = path.join(
      path.dirname(filePath),
      `.media-recovery-${crypto.randomUUID()}.tmp`
    );

    let fd;

    try {
      fd = fs.openSync(tmp, 'wx', 0o600);
      fs.writeFileSync(fd, content, 'utf8');
      fs.fsyncSync(fd);
      fs.closeSync(fd);
      fd = undefined;
      fs.renameSync(tmp, filePath);
    } finally {
      if (fd !== undefined) fs.closeSync(fd);
      try { fs.unlinkSync(tmp); } catch (_) {}
    }
  }

  function has(item) {
    const id = identity(item);
    return load().some(entry =>
      identity(entry) === id &&
      entry.status === 'active'
    );
  }

  function record(item) {
    const core = normalize(item);
    const entries = load();
    const id = identity(core);

    const previous = entries.find(
      entry => identity(entry) === id
    );

    if (previous) {
      // A retired proof can never be reactivated.
      if (previous.status === 'retired') {
        throw new Error('RECOVERY_PROOF_RETIRED');
      }

      return false;
    }

    persist([
      ...entries,
      { ...core, status: 'active' }
    ]);

    return true;
  }

  function retire(item) {
    const core = normalize(item);
    const entries = load();
    const id = identity(core);

    const index = entries.findIndex(
      entry => identity(entry) === id
    );

    if (index >= 0) {
      if (entries[index].status === 'retired') {
        return false;
      }

      entries[index] = {
        ...core,
        status: 'retired'
      };
    } else {
      // Tombstone also blocks an old operation from being
      // accepted after a later retry.
      entries.push({
        ...core,
        status: 'retired'
      });
    }

    persist(entries);
    return true;
  }

  return Object.freeze({
    record,
    has,
    retire
  });
}

module.exports = { createMediaRecoveryJournal };