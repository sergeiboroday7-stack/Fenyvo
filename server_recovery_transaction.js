'use strict';

function createRecoveryTransactionLock() {
  const busy = new Set();

  async function run(username, operation) {
    if (typeof username !== 'string' || !username.trim()) {
      throw new TypeError('Invalid account identifier');
    }
    if (typeof operation !== 'function') {
      throw new TypeError('Invalid recovery operation');
    }
    const account = username.trim();
    if (busy.has(account)) {
      throw new Error('Recovery operation already in progress');
    }
    busy.add(account);
    try {
      return await operation();
    } finally {
      busy.delete(account);
    }
  }

  return { run };
}

module.exports = { createRecoveryTransactionLock };
