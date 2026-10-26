'use strict';

const fs = require('node:fs');
const crypto = require('node:crypto');
const path = require('node:path');

function validateQueue(value) {
  if (
    !value ||
    typeof value !== 'object' ||
    Array.isArray(value)
  ) {
    throw new TypeError('Offline queue must be an object');
  }

  for (const [recipient, messages] of Object.entries(value)) {
    if (!recipient || !Array.isArray(messages)) {
      throw new TypeError('Invalid recipient queue');
    }
  }

  return value;
}

function createOfflineAtomicStore({
  filePath,
  fsImpl = fs,
} = {}) {
  if (typeof filePath !== 'string' || !filePath.trim()) {
    throw new TypeError('Offline store path required');
  }

  const destination = path.resolve(filePath);

  function load() {
    try {
      const content = fsImpl.readFileSync(
        destination,
        'utf8'
      );

      return validateQueue(JSON.parse(content));
    } catch (error) {
      if (error && error.code === 'ENOENT') {
        return {};
      }

      // Corrupted data must never silently become an empty queue.
      throw error;
    }
  }

  function save(messages) {
    validateQueue(messages);

    // Serialize before touching the existing file.
    const serialized = JSON.stringify(messages, null, 2);

    if (typeof serialized !== 'string') {
      throw new TypeError('Cannot serialize offline queue');
    }

    const temporary = path.join(
      path.dirname(destination),
      `.${path.basename(destination)}.${crypto.randomUUID()}.tmp`
    );

    let temporaryCreated = false;

    try {
      fsImpl.writeFileSync(temporary, serialized, {
        encoding: 'utf8',
        flag: 'wx',
        mode: 0o600,
      });

      temporaryCreated = true;

      // Rename within the same directory avoids replacing
      // the destination before the new data has been written.
      fsImpl.renameSync(temporary, destination);

      return true;
    } catch (error) {
      // A failed operation must remain visible to callers.
      throw error;
    } finally {
      if (
        temporaryCreated ||
        (typeof fsImpl.existsSync === 'function' &&
         fsImpl.existsSync(temporary))
      ) {
        try {
          fsImpl.unlinkSync(temporary);
        } catch (cleanupError) {
          if (cleanupError.code !== 'ENOENT') {
            // Preserve the primary write/rename failure.
          }
        }
      }
    }
  }

  return { load, save };
}

module.exports = {
  createOfflineAtomicStore,
  validateQueue,
};