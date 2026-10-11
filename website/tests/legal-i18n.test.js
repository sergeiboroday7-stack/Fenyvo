const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const root = path.resolve(__dirname, '..');
const source = fs.readFileSync(path.join(root, 'assets', 'legal-i18n.js'), 'utf8');
new vm.Script(source);

for (const page of ['privacy', 'terms', 'acceptable', 'support']) {
  let handler;
  const stored = {};
  const article = { innerHTML: '<h1>Русский исходный текст</h1>' };
  const caption = { textContent: '' };
  const back = { textContent: '' };
  const brand = { setAttribute() {}, classList: { add() {} } };
  const link = { dataset: { link: 'support' }, textContent: '' };
  const selector = {
    value: '', options: [{ textContent: '' }],
    setAttribute() {}, addEventListener(type, callback) { if (type === 'change') handler = callback; }
  };
  const document = {
    body: { dataset: { page } }, documentElement: { lang: 'ru' }, title: '',
    getElementById(id) { return id === 'legal-content' ? article : selector; },
    querySelector(value) { return value === '.language-caption' ? caption : value === '.brand' ? brand : back; },
    querySelectorAll() { return [link]; }
  };
  vm.runInNewContext(source, {
    document, navigator: { languages: ['uk-UA'], language: 'uk-UA' },
    localStorage: { getItem(key) { return stored[key] || null; }, setItem(key, value) { stored[key] = value; } }
  });
  assert.equal(document.documentElement.lang, 'uk');
  assert.match(article.innerHTML, /[іїє]/i);
  selector.value = 'en'; handler();
  assert.equal(document.documentElement.lang, 'en');
  assert.match(document.title, /Fenyvo/);
  assert.equal(stored['fenyvo.website.language'], 'en');
}

console.log('Legal i18n tests passed for privacy, terms, acceptable use, and support.');
