const fs = require('fs');
const path = require('path');
const WebSocket = require('ws');

const expectedSessionId = process.env.FENYVO_TEST_SESSION_ID || '';
const username = process.env.FENYVO_TEST_GUEST_USER || '';
const password = process.env.FENYVO_TEST_GUEST_PASS || '';

const dataDirectory = process.env.SPARTAN_DATA_DIR?.trim()
  ? path.resolve(process.env.SPARTAN_DATA_DIR.trim())
  : __dirname;

const contacts = JSON.parse(
  fs.readFileSync(path.join(dataDirectory, 'temporary_contacts.json'), 'utf8')
);

const entry = Object.entries(contacts).find(
  ([, record]) => record.sessionId === expectedSessionId
);

if (!entry || !username || !password) {
  console.error('RESTART TEST: missing test data');
  process.exit(1);
}

const token = entry[0];
const ws = new WebSocket('ws://127.0.0.1:8080');

const timer = setTimeout(() => {
  console.error('RESTART TEST: TIMEOUT');
  try { ws.close(); } catch (_) {}
  process.exit(1);
}, 10000);

ws.on('open', () => {
  ws.send(JSON.stringify({
    type: 'login',
    data: { username, password },
  }));
});

ws.on('message', (raw) => {
  const msg = JSON.parse(raw.toString());

  if (msg.type === 'login_success') {
    console.log('PASS 1: guest login after restart');

    ws.send(JSON.stringify({
      type: 'temporary_contact_join',
      data: { token },
    }));
    return;
  }

  if (msg.type === 'login_error') {
    clearTimeout(timer);
    console.error('RESTART TEST: login failed');
    ws.close();
    process.exit(1);
  }

  if (msg.type === 'temporary_contact_joined') {
    const actual = msg.data?.sessionId;

    clearTimeout(timer);

    if (actual !== expectedSessionId) {
      console.error('RESTART TEST: SESSION ID CHANGED');
      console.error('expected:', expectedSessionId);
      console.error('actual:', actual);
      ws.close();
      process.exit(1);
    }

    console.log('PASS 2: persisted session restored');
    console.log('PASS 3: sessionId preserved after server restart');
    console.log('TEMPORARY CONTACT RESTART TEST: PASSED');

    ws.close();
  }
});
