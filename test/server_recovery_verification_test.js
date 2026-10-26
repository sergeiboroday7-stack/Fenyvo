'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { createRecoveryChallengeStore } = require('../server_recovery_challenge_store');
const { createRecoveryVerifier } = require('../server_recovery_verification');

test('valid signature succeeds once', () => {
  const pair = crypto.generateKeyPairSync('ed25519');
  const key = pair.publicKey.export({format:'der',type:'spki'}).subarray(-32);
  const store = createRecoveryChallengeStore();
  const verifier = createRecoveryVerifier(store, name => name === 'alice' ? key : null);
  const request = store.issue('alice');
  const msg = Buffer.from('FENYVO/account-password-recovery/v1:alice:' + request.challengeId);
  const signatureBytes = crypto.sign(null,msg,pair.privateKey);
  const args = {username:'alice',challengeId:request.challengeId,signatureBytes};
  assert.equal(verifier.verifyAndConsume(args),true);
  assert.equal(verifier.verifyAndConsume(args),false);
});

test('wrong signature does not consume challenge', () => {
  const owner = crypto.generateKeyPairSync('ed25519');
  const attacker = crypto.generateKeyPairSync('ed25519');
  const key = owner.publicKey.export({format:'der',type:'spki'}).subarray(-32);
  const store = createRecoveryChallengeStore();
  const verifier = createRecoveryVerifier(store, name => name === 'alice' ? key : null);
  const request = store.issue('alice');
  const msg = Buffer.from('FENYVO/account-password-recovery/v1:alice:' + request.challengeId);
  const wrong = crypto.sign(null,msg,attacker.privateKey);
  assert.equal(verifier.verifyAndConsume({username:'alice',challengeId:request.challengeId,signatureBytes:wrong}),false);
  const correct = crypto.sign(null,msg,owner.privateKey);
  assert.equal(verifier.verifyAndConsume({username:'alice',challengeId:request.challengeId,signatureBytes:correct}),true);
});
