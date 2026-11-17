const fs = require('fs');
const crypto = require('crypto');
const WebSocket = require('ws');

const sessionId = process.env.FENYVO_TEST_SESSION_ID || '';
const ownerUser = process.env.FENYVO_TEST_OWNER_USER || '';
const ownerPass = process.env.FENYVO_TEST_OWNER_PASS || '';
const guestUser = process.env.FENYVO_TEST_GUEST_USER || '';
const guestPass = process.env.FENYVO_TEST_GUEST_PASS || '';

if (!sessionId || !ownerUser || !ownerPass || !guestUser || !guestPass) {
  console.error('E2EE TEST: credentials/session missing');
  process.exit(1);
}

function makeSocket(username, password) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket('ws://127.0.0.1:8080');

    const timer = setTimeout(() => {
      reject(new Error('login timeout: ' + username));
      try { ws.close(); } catch (_) {}
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
        clearTimeout(timer);
        resolve(ws);
      }

      if (msg.type === 'login_error') {
        clearTimeout(timer);
        reject(new Error(msg.data?.reason || 'login failed'));
      }
    });
  });
}

function waitFor(ws, type, timeoutMs = 10000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      ws.off('message', handler);
      reject(new Error('timeout waiting for ' + type));
    }, timeoutMs);

    function handler(raw) {
      const msg = JSON.parse(raw.toString());

      if (msg.type === type) {
        clearTimeout(timer);
        ws.off('message', handler);
        resolve(msg);
      }
    }

    ws.on('message', handler);
  });
}

function fakeBundle() {
  const b64 = (n) => crypto.randomBytes(n).toString('base64');

  return {
    version: 2,
    protocol: 'signal-pqxdh-double-ratchet',
    deviceId: 1,
    registrationId: 12345,
    identityKey: b64(32),
    signedPreKey: {
      id: 1,
      publicKey: b64(32),
      signature: b64(64),
    },
    preKeys: [
      {
        id: 10,
        publicKey: b64(32),
      },
    ],
    kyberPreKeys: [
      {
        id: 20,
        publicKey: b64(64),
        signature: b64(64),
      },
    ],
  };
}

async function main() {
  const owner = await makeSocket(ownerUser, ownerPass);
  console.log('PASS 1: owner login');

  const guest = await makeSocket(guestUser, guestPass);
  console.log('PASS 2: guest login');

  const ownerPublished = waitFor(owner, 'temporary_e2ee_bundle_published');

  owner.send(JSON.stringify({
    type: 'temporary_e2ee_bundle_publish',
    data: {
      sessionId,
      ...fakeBundle(),
    },
  }));

  await ownerPublished;
  console.log('PASS 3: owner E2EE bundle published');

  const guestBundle = waitFor(guest, 'temporary_e2ee_prekey_bundle');

  guest.send(JSON.stringify({
    type: 'temporary_e2ee_bundle_get',
    data: { sessionId },
  }));

  const bundleMsg = await guestBundle;

  if (!bundleMsg.data?.available) {
    throw new Error('owner bundle not available');
  }

  if (
    bundleMsg.data?.protocol !== 'signal-pqxdh-double-ratchet' ||
    bundleMsg.data?.version !== 2
  ) {
    throw new Error('unexpected E2EE bundle protocol/version');
  }

  console.log('PASS 4: guest received owner prekey bundle');

  const receivedMessage = waitFor(guest, 'temporary_message');

  owner.send(JSON.stringify({
    type: 'temporary_message',
    data: {
      sessionId,
      messageId: 'e2ee_test_001',
      cipherType: 2,
      ciphertext: crypto.randomBytes(96).toString('base64'),
    },
  }));

  const incoming = await receivedMessage;

  if (
    incoming.data?.sessionId !== sessionId ||
    incoming.data?.messageId !== 'e2ee_test_001' ||
    incoming.data?.e2ee !== true ||
    incoming.data?.e2eeVersion !== 2 ||
    incoming.data?.e2eeProtocol !== 'signal'
  ) {
    throw new Error('unexpected temporary message envelope');
  }

  if ('username' in incoming.data || 'peer' in incoming.data) {
    throw new Error('identity leak in temporary message envelope');
  }

  console.log('PASS 5: encrypted temporary message routed');
  console.log('PASS 6: no permanent username leaked in message envelope');
  console.log('TEMPORARY CONTACT E2EE SERVER TEST: PASSED');

  owner.close();
  guest.close();
}

main().catch((error) => {
  console.error('');
  console.error('TEMPORARY CONTACT E2EE SERVER TEST: FAILED');
  console.error(error);
  process.exit(1);
});