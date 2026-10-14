const fs = require('fs');
const path = require('path');

function loadEnvironment(projectDirectory) {
  const envFile = process.env.SPARTAN_ENV_FILE?.trim()
    ? path.resolve(process.env.SPARTAN_ENV_FILE.trim())
    : path.join(projectDirectory, '.env');

  if (!fs.existsSync(envFile)) return;
  if (typeof process.loadEnvFile !== 'function') {
    throw new Error('Для загрузки .env требуется Node.js 20.12 или новее');
  }
  process.loadEnvFile(envFile);
}

function readInteger(name, fallback, { min = 1, max = Number.MAX_SAFE_INTEGER } = {}) {
  const rawValue = process.env[name]?.trim();
  if (!rawValue) return fallback;
  const value = Number(rawValue);
  if (!Number.isSafeInteger(value) || value < min || value > max) {
    throw new Error(`${name} должен быть целым числом от ${min} до ${max}`);
  }
  return value;
}

function readBoolean(name, fallback = false) {
  const rawValue = process.env[name]?.trim().toLowerCase();
  if (!rawValue) return fallback;
  if (['1', 'true', 'yes', 'on'].includes(rawValue)) return true;
  if (['0', 'false', 'no', 'off'].includes(rawValue)) return false;
  throw new Error(`${name} должен иметь значение true или false`);
}

function loadServerConfig(projectDirectory = __dirname) {
  loadEnvironment(projectDirectory);

  const dataDirectory = path.resolve(
    process.env.SPARTAN_DATA_DIR?.trim() || projectDirectory,
  );

  return Object.freeze({
    wsHost: process.env.SPARTAN_WS_HOST?.trim() || '0.0.0.0',
    wsPort: readInteger('SPARTAN_WS_PORT', 8080, { max: 65535 }),
    mediaHost: process.env.SPARTAN_MEDIA_HOST?.trim() || '0.0.0.0',
    mediaPort: readInteger('SPARTAN_MEDIA_PORT', 8081, { max: 65535 }),
    turnHost: process.env.SPARTAN_TURN_HOST?.trim() || '',
    turnPort: readInteger('SPARTAN_TURN_PORT', 3478, { max: 65535 }),
    turnSecret: process.env.SPARTAN_TURN_SECRET?.trim() || '',
    turnCredentialTtlSeconds: readInteger(
      'SPARTAN_TURN_TTL_SECONDS',
      3600,
      { min: 300, max: 86400 },
    ),    maxMediaBytes: readInteger('SPARTAN_MAX_MEDIA_BYTES', 1024 * 1024 * 1024, {
      min: 1024,
      max: 2 * 1024 * 1024 * 1024,
    }),
    dataDirectory,
    firebaseServiceAccountFile: path.resolve(
      process.env.FIREBASE_SERVICE_ACCOUNT_PATH?.trim() ||
        path.join(dataDirectory, 'firebase-service-account.json'),
    ),
    logMessageContent: readBoolean('SPARTAN_LOG_MESSAGE_CONTENT', false),
    logClientIp: readBoolean('SPARTAN_LOG_CLIENT_IP', false),
    trustProxy: readBoolean('SPARTAN_TRUST_PROXY', false),
    authMaxAttempts: readInteger('SPARTAN_AUTH_MAX_ATTEMPTS', 10, {
      min: 5,
      max: 1000,
    }),
    authIpMaxAttempts: readInteger('SPARTAN_AUTH_IP_MAX_ATTEMPTS', 120, {
      min: 10,
      max: 10000,
    }),
    authWindowMs: readInteger('SPARTAN_AUTH_WINDOW_MS', 15 * 60 * 1000, {
      min: 10 * 1000,
      max: 24 * 60 * 60 * 1000,
    }),
  });
}

module.exports = {
  loadServerConfig,
  readBoolean,
  readInteger,
};
