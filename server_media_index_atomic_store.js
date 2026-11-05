'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

function saveMediaIndexAtomic({
  filePath,
  index,
  fsImpl = fs
}) {
  if (typeof filePath !== 'string' || !filePath.trim()) {
    throw new TypeError('MEDIA_INDEX_PATH_REQUIRED');
  }
  if (!index || typeof index !== 'object' ||
      Array.isArray(index)) {
    throw new TypeError('MEDIA_INDEX_OBJECT_REQUIRED');
  }

  const serialized = JSON.stringify(index, null, 2);
  if (typeof serialized !== 'string') {
    throw new TypeError('MEDIA_INDEX_SERIALIZATION_FAILED');
  }

  const target = path.resolve(filePath);
  const temporary = path.join(
    path.dirname(target),
    '.' + path.basename(target) + '.' +
    crypto.randomUUID() + '.tmp'
  );

  let fd;
  let primaryError = null;

  try {
    fd = fsImpl.openSync(temporary, 'wx', 0o600);
    fsImpl.writeFileSync(fd, serialized, 'utf8');
    fsImpl.fsyncSync(fd);
    fsImpl.closeSync(fd);
    fd = undefined;

    fsImpl.renameSync(temporary, target);
    return true;
  } catch (error) {
    primaryError = error;
    throw error;
  } finally {
    if (fd !== undefined) {
      try {
        fsImpl.closeSync(fd);
      } catch (error) {
        if (!primaryError) throw error;
      }
    }

    try {
      fsImpl.unlinkSync(temporary);
    } catch (error) {
      if (error.code !== 'ENOENT' && !primaryError) {
        throw error;
      }
    }
  }
}

module.exports = { saveMediaIndexAtomic };