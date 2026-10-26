'use strict';

const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

const DIR = '/var/lib/fenyvo/support-tickets';

function ticketPath(user, requestId) {
  const key = crypto
    .createHash('sha256')
    .update(JSON.stringify([user, requestId]))
    .digest('hex');
  return path.join(DIR, `${key}.json`);
}

function loadTicket(user, requestId) {
  const file = ticketPath(user, requestId);
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw error;
  }
}

function createTicket(user, requestId) {
  const file = ticketPath(user, requestId);
  const record = {
    requestId,
    user,
    ticketId: `FEN-${Date.now()}-${crypto.randomBytes(6).toString('hex').toUpperCase()}`,
    status: 'pending',
    createdAt: new Date().toISOString(),
  };

  try {
    fs.writeFileSync(file, JSON.stringify(record), {
      flag: 'wx',
      mode: 0o600,
    });
    return { created: true, record };
  } catch (error) {
    if (error.code === 'EEXIST') {
      return { created: false, record: loadTicket(user, requestId) };
    }
    throw error;
  }
}

function updateTicket(user, requestId, status, fields = {}) {
  const file = ticketPath(user, requestId);
  const record = loadTicket(user, requestId);
  if (!record) throw new Error('Ticket not found');

  const allowed = {
    pending: ['sending'],
    sending: ['accepted', 'unknown'],
    accepted: [],
    unknown: [],
  };

  if (!allowed[record.status]?.includes(status)) {
    throw new Error('Invalid ticket status transition');
  }

  const updated = {
    ...record,
    ...fields,
    status,
    updatedAt: new Date().toISOString(),
  };

  const temp = `${file}.${process.pid}.${crypto.randomBytes(6).toString('hex')}.tmp`;
  fs.writeFileSync(temp, JSON.stringify(updated), {
    flag: 'wx',
    mode: 0o600,
  });
  fs.renameSync(temp, file);
  return updated;
}

function claimTicket(user, requestId) {
  const file = ticketPath(user, requestId);
  const lock = `${file}.lock`;

  const fd = fs.openSync(lock, 'wx', 0o600);
  try {
    const record = loadTicket(user, requestId);
    if (!record || record.status !== 'pending') {
      throw new Error('Ticket cannot be sent again');
    }
    updateTicket(user, requestId, 'sending');
    return true;
  } finally {
    fs.closeSync(fd);
  }
}

module.exports = { loadTicket, createTicket, updateTicket, claimTicket };
