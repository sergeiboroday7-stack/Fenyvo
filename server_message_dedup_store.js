'use strict';

const fs = require('node:fs');
const path = require('node:path');

function createDedupStore(filePath, { filesystem = fs } = {}) {
  if (typeof filePath !== 'string' || !filePath.trim()) {
    throw new TypeError('filePath is required');
  }

  function load() {
    if (!filesystem.existsSync(filePath)) {
      return {};
    }

    const parsed = JSON.parse(filesystem.readFileSync(filePath, 'utf8'));

    if (
      !parsed ||
      typeof parsed !== 'object' ||
      Array.isArray(parsed)
    ) {
      throw new TypeError('Invalid dedup store format');
    }

    return parsed;
  }

  function save(records) {
    if (
      !records ||
      typeof records !== 'object' ||
      Array.isArray(records)
    ) {
      throw new TypeError('Invalid dedup records');
    }

    const dir = path.dirname(filePath);
    const temp = path.join(
      dir,
      `.${path.basename(filePath)}.${process.pid}.${require('node:crypto').randomUUID()}.tmp`
    );

    try {
      const payload = JSON.stringify(records);
      filesystem.writeFileSync(temp, payload, { encoding: 'utf8', flag: 'wx' });
      filesystem.renameSync(temp, filePath);
    } catch (error) {
      try {
        filesystem.unlinkSync(temp);
      } catch (_) {
        // Cleanup is best effort. The original error is preserved.
      }
      throw error;
    }
  }

  return { load, save };
}

module.exports = { createDedupStore };