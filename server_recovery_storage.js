'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

function saveRecoveryJsonAtomic(filePath, value) {
  const dir = path.dirname(filePath);
  const temp = path.join(dir, '.recovery-' + crypto.randomBytes(12).toString('hex') + '.tmp');
  let fd;
  try {
    const json = JSON.stringify(value, null, 2);
    fd = fs.openSync(temp, 'wx', 0o600);
    fs.writeFileSync(fd, json, 'utf8');
    fs.fsyncSync(fd);
    fs.closeSync(fd);
    fd = undefined;
    fs.renameSync(temp, filePath);
    return true;
  } catch (error) {
    if (fd !== undefined) { try { fs.closeSync(fd); } catch (_) {} }
    try { fs.unlinkSync(temp); } catch (_) {}
    throw error;
  }
}

module.exports = { saveRecoveryJsonAtomic };
