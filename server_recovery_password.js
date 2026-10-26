'use strict';

function prepareRecoveryPasswordUpdate(user, passwordData) {
  if (!user || typeof user !== 'object' || Array.isArray(user)) {
    throw new TypeError('Invalid account record');
  }
  if (!passwordData || typeof passwordData !== 'object' ||
      typeof passwordData.salt !== 'string' || !/^[0-9a-f]{32}$/.test(passwordData.salt) ||
      typeof passwordData.hash !== 'string' || !/^[0-9a-f]{128}$/.test(passwordData.hash)) {
    throw new TypeError('Invalid password hash data');
  }
  return { ...user, salt: passwordData.salt, passwordHash: passwordData.hash };
}

module.exports = { prepareRecoveryPasswordUpdate };
