'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { saveRecoveryJsonAtomic } = require('../server_recovery_storage');

test('successfully replaces existing JSON', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fenyvo-recovery-test-'));
  try {
    const file = path.join(dir, 'users.json');
    fs.writeFileSync(file, JSON.stringify({alice:{version:1}}));
    assert.equal(saveRecoveryJsonAtomic(file, {alice:{version:2}}), true);
    assert.deepEqual(JSON.parse(fs.readFileSync(file, 'utf8')), {alice:{version:2}});
  } finally { fs.rmSync(dir, {recursive:true,force:true}); }
});

test('serialization failure preserves previous data', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fenyvo-recovery-test-'));
  try {
    const file = path.join(dir, 'users.json');
    const original = '{old:true}';
    fs.writeFileSync(file, original);
    assert.throws(() => saveRecoveryJsonAtomic(file, {bad:BigInt(1)}));
    assert.equal(fs.readFileSync(file, 'utf8'), original);
    assert.deepEqual(fs.readdirSync(dir), ['users.json']);
  } finally { fs.rmSync(dir, {recursive:true,force:true}); }
});

test('successful write leaves no temporary files', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fenyvo-recovery-test-'));
  try {
    const file = path.join(dir, 'users.json');
    saveRecoveryJsonAtomic(file, {test:true});
    assert.deepEqual(fs.readdirSync(dir), ['users.json']);
  } finally { fs.rmSync(dir, {recursive:true,force:true}); }
});


test('rename failure preserves original JSON', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'fenyvo-recovery-test-'));
  const originalRename = fs.renameSync;
  try {
    const file = path.join(dir, 'users.json');
    fs.writeFileSync(file, JSON.stringify({alice:{version:1}}));
    fs.renameSync = () => { throw new Error('simulated rename failure'); };
    assert.throws(() => saveRecoveryJsonAtomic(file, {alice:{version:2}}), /simulated rename failure/);
    assert.deepEqual(JSON.parse(fs.readFileSync(file, 'utf8')), {alice:{version:1}});
    assert.deepEqual(fs.readdirSync(dir), ['users.json']);
  } finally {
    fs.renameSync = originalRename;
    fs.rmSync(dir, {recursive:true,force:true});
  }
});
