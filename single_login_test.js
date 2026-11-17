const WebSocket = require('ws');

const user = process.env.FENYVO_TEST_USER || '';
const pass = process.env.FENYVO_TEST_PASS || '';

if (!user || !pass) {
  console.error('TEST ERROR: credentials missing');
  process.exit(1);
}

const ws = new WebSocket('ws://127.0.0.1:8080');

ws.on('open', () => {
  ws.send(JSON.stringify({
    type: 'login',
    data: {
      username: user,
      password: pass,
    },
  }));
});

ws.on('message', (raw) => {
  const msg = JSON.parse(raw.toString());

  if (msg.type === 'login_success') {
    console.log('LOGIN TEST: PASSED');
    ws.close();
    return;
  }

  if (msg.type === 'login_error') {
    console.log('LOGIN TEST: FAILED');
    console.log(msg.data?.reason || 'login_error');
    ws.close();
    process.exitCode = 1;
  }
});

setTimeout(() => {
  console.error('LOGIN TEST: TIMEOUT');
  try { ws.close(); } catch (_) {}
  process.exitCode = 1;
}, 10000);