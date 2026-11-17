const WebSocket = require('ws');

const ownerUser = process.env.FENYVO_TEST_OWNER_USER || '';
const ownerPass = process.env.FENYVO_TEST_OWNER_PASS || '';
const guestUser = process.env.FENYVO_TEST_GUEST_USER || '';
const guestPass = process.env.FENYVO_TEST_GUEST_PASS || '';

if (!ownerUser || !ownerPass || !guestUser || !guestPass) {
  console.error('TEST ERROR: credentials missing');
  process.exit(1);
}

function connect(name) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket('ws://127.0.0.1:8080');

    const timer = setTimeout(() => {
      reject(new Error(`${name}: connect timeout`));
    }, 10000);

    ws.once('open', () => {
      clearTimeout(timer);
      resolve(ws);
    });

    ws.once('error', reject);
  });
}

function send(ws, type, data = {}) {
  ws.send(JSON.stringify({ type, data }));
}

function waitFor(ws, expectedType, timeoutMs = 10000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error(`Timeout waiting for ${expectedType}`));
    }, timeoutMs);

    function cleanup() {
      clearTimeout(timer);
      ws.off('message', onMessage);
    }

    function onMessage(raw) {
      let msg;
      try {
        msg = JSON.parse(raw.toString());
      } catch (_) {
        return;
      }

      if (msg.type !== expectedType) return;

      cleanup();
      resolve(msg.data || {});
    }

    ws.on('message', onMessage);
  });
}

async function login(ws, username, password) {
  const success = waitFor(ws, 'login_success');
  const error = waitFor(ws, 'login_error').then((data) => {
    throw new Error(data.reason || 'login_error');
  });

  send(ws, 'login', { username, password });

  return Promise.race([success, error]);
}

async function main() {
  let owner;
  let guest;

  try {
    owner = await connect('owner');
    guest = await connect('guest');

    await login(owner, ownerUser, ownerPass);
    console.log('PASS 1: owner login');

    await login(guest, guestUser, guestPass);
    console.log('PASS 2: guest login');

    const createdPromise = waitFor(
      owner,
      'temporary_contact_created',
    );

    send(owner, 'temporary_contact_create', {
      expiresInMinutes: 15,
      allowMessages: true,
      allowCalls: false,
      allowFiles: false,
    });

    const created = await createdPromise;

    if (!created.success || !created.token) {
      throw new Error(
        `temporary_contact_create failed: ${JSON.stringify(created)}`,
      );
    }

    console.log('PASS 3: temporary token created');

    const ownerJoined1 = waitFor(
      owner,
      'temporary_contact_joined',
    );

    const guestJoined1 = waitFor(
      guest,
      'temporary_contact_joined',
    );

    send(guest, 'temporary_contact_join', {
      token: created.token,
    });

    const [ownerSession1, guestSession1] = await Promise.all([
      ownerJoined1,
      guestJoined1,
    ]);

    if (
      !ownerSession1.success ||
      !guestSession1.success ||
      !ownerSession1.sessionId ||
      ownerSession1.sessionId !== guestSession1.sessionId
    ) {
      throw new Error(
        'owner/guest sessionId mismatch',
      );
    }

    const firstSessionId = guestSession1.sessionId;

    console.log(
      'PASS 4: owner and guest received same sessionId',
    );

    const ownerJoined2 = waitFor(
      owner,
      'temporary_contact_joined',
    );

    const guestJoined2 = waitFor(
      guest,
      'temporary_contact_joined',
    );

    send(guest, 'temporary_contact_join', {
      token: created.token,
    });

    const [ownerSession2, guestSession2] = await Promise.all([
      ownerJoined2,
      guestJoined2,
    ]);

    if (
      !guestSession2.success ||
      guestSession2.sessionId !== firstSessionId ||
      ownerSession2.sessionId !== firstSessionId
    ) {
      throw new Error(
        'sessionId changed on repeated join',
      );
    }

    console.log(
      'PASS 5: repeated join preserved sessionId',
    );

    console.log('');
    console.log('TEMPORARY CONTACT SERVER TEST: PASSED');
    console.log(`sessionId: ${firstSessionId}`);
  } finally {
    try { owner?.close(); } catch (_) {}
    try { guest?.close(); } catch (_) {}
  }
}

main().catch((error) => {
  console.error('');
  console.error('TEMPORARY CONTACT SERVER TEST: FAILED');
  console.error(error?.stack || error);
  process.exitCode = 1;
});