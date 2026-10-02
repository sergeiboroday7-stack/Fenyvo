'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..', 'website');
const index = fs.readFileSync(path.join(root, 'index.html'), 'utf8');

for (const file of [
  'privacy.html',
  'terms.html',
  'acceptable-use.html',
  'support.html',
  'legal.css',
]) {
  assert.ok(fs.existsSync(path.join(root, file)), `${file} is missing`);
}

assert.match(index, /id="download-dialog"/);
assert.match(index, /id="legal-terms"/);
assert.match(index, /id="legal-age"/);
assert.match(index, /id="legal-download"[^>]*disabled/);
assert.equal(
  /href="\/download\/Fenyvo-1\.8\.0-arm64\.apk"/.test(index),
  false,
  'APK must not be linked directly from the landing page',
);
assert.equal(
  (index.match(/data-download-url="\/download\/Fenyvo-1\.8\.0-arm64\.apk"/g) || [])
    .length,
  2,
);

const scripts = [...index.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(
  (match) => match[1],
);
assert.ok(scripts.length > 0, 'landing page script is missing');
for (const script of scripts) {
  // Syntax validation only. DOM behavior is covered by the required element checks.
  new Function(script);
}

for (const file of [
  'privacy.html',
  'terms.html',
  'acceptable-use.html',
  'support.html',
]) {
  const html = fs.readFileSync(path.join(root, file), 'utf8');
  assert.match(html, /2026-10-01|Поддержка Fenyvo/);
  assert.doesNotMatch(
    html,
    /href="\/(?:privacy|terms|acceptable-use|support)"/,
    `${file} contains an unsupported clean URL`,
  );
}

const privacy = fs.readFileSync(path.join(root, 'privacy.html'), 'utf8');
const terms = fs.readFileSync(path.join(root, 'terms.html'), 'utf8');
const support = fs.readFileSync(path.join(root, 'support.html'), 'utf8');
assert.match(privacy, /Serhii Strilets/);
assert.match(privacy, /privacy@fenyvo\.com/);
assert.match(terms, /16 лет/);
assert.match(terms, /обязательные права потребителя/);
assert.match(support, /ИИ-помощник/);
assert.match(support, /support@fenyvo\.com/);

console.log('Website legal checks passed.');
