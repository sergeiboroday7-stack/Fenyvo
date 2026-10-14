const assert = require('node:assert/strict');
const test = require('node:test');

const { readBoolean, readInteger } = require('../server_config');

function withEnvironment(name, value, callback) {
  const previous = process.env[name];
  if (value === undefined) delete process.env[name];
  else process.env[name] = value;
  try {
    callback();
  } finally {
    if (previous === undefined) delete process.env[name];
    else process.env[name] = previous;
  }
}

test('integer settings use defaults and reject unsafe ports', () => {
  withEnvironment('TEST_PORT', undefined, () => {
    assert.equal(readInteger('TEST_PORT', 8080, { max: 65535 }), 8080);
  });
  withEnvironment('TEST_PORT', '443', () => {
    assert.equal(readInteger('TEST_PORT', 8080, { max: 65535 }), 443);
  });
  withEnvironment('TEST_PORT', '70000', () => {
    assert.throws(() => readInteger('TEST_PORT', 8080, { max: 65535 }));
  });
});

test('WebSocket payload limits stay inside the configured safety range', () => {
  withEnvironment('TEST_PAYLOAD', '16777216', () => {
    assert.equal(
      readInteger('TEST_PAYLOAD', 1024, {
        min: 64 * 1024,
        max: 64 * 1024 * 1024,
      }),
      16777216,
    );
  });
  withEnvironment('TEST_PAYLOAD', '1073741824', () => {
    assert.throws(() =>
      readInteger('TEST_PAYLOAD', 1024, {
        min: 64 * 1024,
        max: 64 * 1024 * 1024,
      }),
    );
  });
});

test('boolean settings accept explicit safe values', () => {
  withEnvironment('TEST_BOOLEAN', 'true', () => {
    assert.equal(readBoolean('TEST_BOOLEAN'), true);
  });
  withEnvironment('TEST_BOOLEAN', 'off', () => {
    assert.equal(readBoolean('TEST_BOOLEAN', true), false);
  });
  withEnvironment('TEST_BOOLEAN', 'maybe', () => {
    assert.throws(() => readBoolean('TEST_BOOLEAN'));
  });
});
