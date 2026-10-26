'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { verifyRecoverySignature } = require('../server_account_recovery');

test('valid Ed25519 signature is accepted', () => {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  const message = Buffer.from('fenyvo-recovery-test-123');
  const signature = crypto.sign(null, message, privateKey);
  const rawPublicKey = publicKey.export({ type: 'spki', format: 'der' }).subarray(-32);
  assert.equal(verifyRecoverySignature(rawPublicKey, message, signature), true);
});

test('modified message is rejected', () => {
  const { publicKey, privateKey } = crypto.generateKeyPairSync('ed25519');
  const signature = crypto.sign(null, Buffer.from('original'), privateKey);
  const rawPublicKey = publicKey.export({ type: 'spki', format: 'der' }).subarray(-32);
  assert.equal(verifyRecoverySignature(rawPublicKey, Buffer.from('modified'), signature), false);
});

test('wrong public key is rejected', () => {
  const first = crypto.generateKeyPairSync('ed25519');
  const second = crypto.generateKeyPairSync('ed25519');
  const message = Buffer.from('test-challenge');
  const signature = crypto.sign(null, message, first.privateKey);
  const wrongKey = second.publicKey.export({ type: 'spki', format: 'der' }).subarray(-32);
  assert.equal(verifyRecoverySignature(wrongKey, message, signature), false);
});

test('malformed inputs are rejected', () => {
  assert.equal(verifyRecoverySignature(Buffer.alloc(31), Buffer.from('test'), Buffer.alloc(64)), false);
  assert.equal(verifyRecoverySignature(Buffer.alloc(32), Buffer.alloc(0), Buffer.alloc(64)), false);
  assert.equal(verifyRecoverySignature(Buffer.alloc(32), Buffer.from('test'), Buffer.alloc(63)), false);
});
