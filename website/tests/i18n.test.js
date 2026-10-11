const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

const website = path.resolve(__dirname, '..');
const html = fs.readFileSync(path.join(website, 'index.html'), 'utf8');
const source = fs.readFileSync(path.join(website, 'assets', 'fenyvo-i18n.js'), 'utf8');

assert.match(html, /id="language-select"/);
assert.match(html, /value="auto"/);
assert.match(html, /value="ru"/);
assert.match(html, /value="uk"/);
assert.match(html, /value="en"/);
assert.match(html, /fenyvo-i18n\.js/);
assert.match(html, /download-counters\.js/);
assert.match(html, /id="download-count-android"/);
assert.match(html, /id="download-count-windows"/);
assert.match(html, /id="download-count-ios"/);
assert.match(html, /data-download-platform="android"/);
assert.match(html, /data-download-platform="windows"/);
assert.match(html, /class="brand notranslate" translate="no"/i);
assert.doesNotMatch(html, /<(?:html|body)[^>]*translate\s*=\s*["']no["']/i);
new vm.Script(source);

[
  'Не как у всех',
  'Функции, ради которых стоит попробовать Fenyvo',
  'Fenyvo Pulse',
  'Контакт без номера телефона',
  'Групповой эфир с ведущим',
  'Звонки остаются в контексте',
  'Фирменная звуковая система',
  'Помощь без чтения переписки'
].forEach((text) => assert.ok(html.includes(text), `Missing public feature text: ${text}`));

[
  "differentKicker: 'Не як у всіх'",
  "differentKicker: 'Beyond the usual'",
  "contactWithoutPhone: 'Контакт без номера телефону'",
  "contactWithoutPhone: 'Connect without a phone number'",
  "groupLive: 'Груповий ефір із ведучим'",
  "groupLive: 'Hosted group live sessions'"
].forEach((text) => assert.ok(source.includes(text), `Missing translation: ${text}`));

[
  "downloadsTitle: 'Завантаження застосунку'",
  "downloadsTitle: 'App downloads'",
  "iosPreparing: 'iPhone · версія готується'",
  "iosPreparing: 'iPhone · version in development'"
].forEach((text) => assert.ok(source.includes(text), `Missing download translation: ${text}`));

function load({ languages, saved }) {
  const textNode = {
    nodeValue: 'Возможности',
    parentElement: { tagName: 'DIV' }
  };
  let walked = false;
  let changeHandler;
  const stored = saved ? { 'fenyvo.website.language': saved } : {};
  const selector = {
    value: '',
    setAttribute() {},
    addEventListener(type, handler) {
      if (type === 'change') changeHandler = handler;
    }
  };
  const document = {
    body: {},
    documentElement: { lang: 'ru' },
    title: '',
    createTreeWalker() {
      return { nextNode: () => (walked ? null : ((walked = true), textNode)) };
    },
    querySelector() { return null; },
    getElementById(id) { return id === 'language-select' ? selector : null; }
  };
  const window = { dispatchEvent() {} };
  const context = {
    window,
    document,
    navigator: { languages, language: languages[0] },
    localStorage: {
      getItem(key) { return stored[key] || null; },
      setItem(key, value) { stored[key] = value; }
    },
    NodeFilter: { SHOW_TEXT: 4 },
    CustomEvent: class CustomEvent {}
  };
  vm.runInNewContext(source, context);
  return { document, textNode, selector, stored, change: () => changeHandler() };
}

const ukrainian = load({ languages: ['uk-UA', 'en-US'] });
assert.equal(ukrainian.document.documentElement.lang, 'uk');
assert.equal(ukrainian.textNode.nodeValue, 'Можливості');
assert.equal(ukrainian.selector.value, 'auto');

const fallback = load({ languages: ['de-DE'] });
assert.equal(fallback.document.documentElement.lang, 'en');
assert.equal(fallback.textNode.nodeValue, 'Features');

const savedRussian = load({ languages: ['en-US'], saved: 'ru' });
assert.equal(savedRussian.document.documentElement.lang, 'ru');
savedRussian.selector.value = 'en';
savedRussian.change();
assert.equal(savedRussian.document.documentElement.lang, 'en');
assert.equal(savedRussian.stored['fenyvo.website.language'], 'en');

console.log('Website i18n tests passed: auto uk, English fallback, saved/manual language, external translator compatibility.');
