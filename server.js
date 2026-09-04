const WebSocket = require('ws');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const {
  initializeApp,
  cert,
} = require('firebase-admin/app');

const {
  getMessaging,
} = require('firebase-admin/messaging');

const PORT = 8080;

const USERS_FILE = path.join(
  __dirname,
  'users.json',
);

const AVATARS_DIR = path.join(
  __dirname,
  'avatars',
);

const FCM_TOKENS_FILE = path.join(
  __dirname,
  'fcm_tokens.json',
);

const OFFLINE_MESSAGES_FILE = path.join(
  __dirname,
  'offline_messages.json',
);

const OFFLINE_MESSAGE_STATUS_FILE = path.join(
  __dirname,
  'offline_message_status.json',
);

const FIREBASE_SERVICE_ACCOUNT_FILE = path.join(
  __dirname,
  'firebase-service-account.json',
);

// ========================================
// FIREBASE ADMIN
// ========================================

let firebaseMessaging = null;

try {
  if (
    !fs.existsSync(
      FIREBASE_SERVICE_ACCOUNT_FILE,
    )
  ) {
    throw new Error(
      'Не найден firebase-service-account.json',
    );
  }

  const serviceAccount =
    JSON.parse(
      fs.readFileSync(
        FIREBASE_SERVICE_ACCOUNT_FILE,
        'utf8',
      ),
    );

  const firebaseApp =
    initializeApp({
      credential:
        cert(serviceAccount),
    });

  firebaseMessaging =
    getMessaging(
      firebaseApp,
    );

  console.log(
    '🔥 Firebase Admin подключён',
  );
} catch (error) {
  console.error(
    '❌ Firebase Admin не запущен:',
    error.message,
  );
}

// ========================================
// ПАПКА АВАТАРОК
// ========================================

if (
  !fs.existsSync(
    AVATARS_DIR,
  )
) {
  fs.mkdirSync(
    AVATARS_DIR,
    {
      recursive: true,
    },
  );

  console.log(
    '📁 Создана папка avatars',
  );
}

// ========================================
// WEBSOCKET
// ========================================

const wss =
  new WebSocket.Server({
    host: '0.0.0.0',
    port: PORT,
  });

const onlineUsers =
  new Map();

const messageReactions =
  new Map();

// ========================================
// USERS
// ========================================

function loadUsers() {
  try {
    if (
      !fs.existsSync(
        USERS_FILE,
      )
    ) {
      fs.writeFileSync(
        USERS_FILE,
        JSON.stringify(
          {},
          null,
          2,
        ),
        'utf8',
      );

      return {};
    }

    return JSON.parse(
      fs.readFileSync(
        USERS_FILE,
        'utf8',
      ),
    );
  } catch (error) {
    console.error(
      '❌ Ошибка загрузки пользователей:',
      error,
    );

    return {};
  }
}

function saveUsers(
  users,
) {
  try {
    fs.writeFileSync(
      USERS_FILE,
      JSON.stringify(
        users,
        null,
        2,
      ),
      'utf8',
    );
  } catch (error) {
    console.error(
      '❌ Ошибка сохранения пользователей:',
      error,
    );
  }
}

// ========================================
// FCM TOKENS
// ========================================

function loadFcmTokens() {
  try {
    if (
      !fs.existsSync(
        FCM_TOKENS_FILE,
      )
    ) {
      fs.writeFileSync(
        FCM_TOKENS_FILE,
        JSON.stringify(
          {},
          null,
          2,
        ),
        'utf8',
      );

      return {};
    }

    return JSON.parse(
      fs.readFileSync(
        FCM_TOKENS_FILE,
        'utf8',
      ),
    );
  } catch (error) {
    console.error(
      '❌ Ошибка загрузки FCM токенов:',
      error,
    );

    return {};
  }
}

function saveFcmTokens(
  tokens,
) {
  try {
    fs.writeFileSync(
      FCM_TOKENS_FILE,
      JSON.stringify(
        tokens,
        null,
        2,
      ),
      'utf8',
    );
  } catch (error) {
    console.error(
      '❌ Ошибка сохранения FCM токенов:',
      error,
    );
  }
}

// ========================================
// OFFLINE MESSAGES
// ========================================

function loadOfflineMessages() {
  try {
    if (
      !fs.existsSync(
        OFFLINE_MESSAGES_FILE,
      )
    ) {
      fs.writeFileSync(
        OFFLINE_MESSAGES_FILE,
        JSON.stringify(
          {},
          null,
          2,
        ),
        'utf8',
      );

      return {};
    }

    const data =
      JSON.parse(
        fs.readFileSync(
          OFFLINE_MESSAGES_FILE,
          'utf8',
        ),
      );

    if (
      !data ||
      typeof data !==
        'object' ||
      Array.isArray(
        data,
      )
    ) {
      return {};
    }

    return data;
  } catch (error) {
    console.error(
      '❌ Ошибка загрузки офлайн-сообщений:',
      error,
    );

    return {};
  }
}

function saveOfflineMessages(
  messages,
) {
  try {
    fs.writeFileSync(
      OFFLINE_MESSAGES_FILE,
      JSON.stringify(
        messages,
        null,
        2,
      ),
      'utf8',
    );
  } catch (error) {
    console.error(
      '❌ Ошибка сохранения офлайн-сообщений:',
      error,
    );
  }
}

function queueOfflineMessage(
  username,
  messageData,
) {
  if (
    !Array.isArray(
      offlineMessages[
        username
      ],
    )
  ) {
    offlineMessages[
      username
    ] = [];
  }

  const alreadyQueued =
    offlineMessages[
      username
    ].some(
      (message) =>
        message?.id ===
        messageData.id,
    );

  if (
    alreadyQueued
  ) {
    return;
  }

  offlineMessages[
    username
  ].push(
    messageData,
  );

  saveOfflineMessages(
    offlineMessages,
  );

  console.log(
    `💾 Сообщение сохранено в офлайн-очередь для ${username}`,
  );
}

function queueOfflineEvent(
  username,
  eventType,
  eventData,
) {
  if (
    !Array.isArray(
      offlineMessages[
        username
      ],
    )
  ) {
    offlineMessages[
      username
    ] = [];
  }

  const eventId =
    `${eventType}:${eventData.messageId || crypto.randomUUID()}`;

  const queuedEvent = {
    ...eventData,
    __eventType:
      eventType,
    __eventId:
      eventId,
  };

  const oldIndex =
    offlineMessages[
      username
    ].findIndex(
      (item) =>
        item?.__eventId ===
        eventId,
    );

  if (
    oldIndex >= 0
  ) {
    offlineMessages[
      username
    ][oldIndex] =
      queuedEvent;
  } else {
    offlineMessages[
      username
    ].push(
      queuedEvent,
    );
  }

  saveOfflineMessages(
    offlineMessages,
  );

  console.log(
    `💾 Событие ${eventType} сохранено для ${username}`,
  );
}

function deliverOfflineMessages(
  username,
  ws,
) {
  const queued =
    offlineMessages[
      username
    ];

  if (
    !Array.isArray(
      queued,
    ) ||
    queued.length === 0
  ) {
    console.log(
      `📭 Офлайн-сообщений для ${username} нет`,
    );

    send(
      ws,
      'offline_messages_complete',
      {
        count: 0,
      },
    );

    return;
  }

  if (
    !ws ||
    ws.readyState !==
      WebSocket.OPEN
  ) {
    return;
  }

  const pending = [
    ...queued,
  ];

  console.log(
    `📦 Офлайн-сообщений для ${username}: ${pending.length}`,
  );

  for (
    const queuedItem
    of pending
  ) {
    const eventType =
      queuedItem?.__eventType ||
      'message';

    const eventData = {
      ...queuedItem,
    };

    delete eventData.__eventType;
    delete eventData.__eventId;

    send(
      ws,
      eventType,
      eventData,
    );
  }

  delete offlineMessages[
    username
  ];

  saveOfflineMessages(
    offlineMessages,
  );

  send(
    ws,
    'offline_messages_complete',
    {
      count:
        pending.length,
    },
  );

  console.log(
    `✅ Офлайн-сообщения переданы ${username}: ${pending.length}`,
  );
}

// ========================================
// OFFLINE MESSAGE STATUS
// ========================================

function loadOfflineMessageStatus() {
  try {
    if (
      !fs.existsSync(
        OFFLINE_MESSAGE_STATUS_FILE,
      )
    ) {
      fs.writeFileSync(
        OFFLINE_MESSAGE_STATUS_FILE,
        JSON.stringify(
          {},
          null,
          2,
        ),
        'utf8',
      );

      return {};
    }

    const data =
      JSON.parse(
        fs.readFileSync(
          OFFLINE_MESSAGE_STATUS_FILE,
          'utf8',
        ),
      );

    if (
      !data ||
      typeof data !==
        'object' ||
      Array.isArray(
        data,
      )
    ) {
      return {};
    }

    return data;
  } catch (error) {
    console.error(
      '❌ Ошибка загрузки офлайн-статусов сообщений:',
      error,
    );

    return {};
  }
}

function saveOfflineMessageStatus(
  statuses,
) {
  try {
    fs.writeFileSync(
      OFFLINE_MESSAGE_STATUS_FILE,
      JSON.stringify(
        statuses,
        null,
        2,
      ),
      'utf8',
    );
  } catch (error) {
    console.error(
      '❌ Ошибка сохранения офлайн-статусов сообщений:',
      error,
    );
  }
}

function queueOfflineMessageStatus(
  username,
  type,
  data,
) {
  if (
    !Array.isArray(
      offlineMessageStatus[
        username
      ],
    )
  ) {
    offlineMessageStatus[
      username
    ] = [];
  }

  const messageId =
    data.messageId
      ?.toString()
      .trim();

  if (!messageId) {
    return;
  }

  if (
    type ===
      'message_read'
  ) {
    offlineMessageStatus[
      username
    ] = offlineMessageStatus[
      username
    ].filter(
      (item) =>
        item?.data?.messageId !==
          messageId,
    );
  } else {
    const alreadyRead =
      offlineMessageStatus[
        username
      ].some(
        (item) =>
          item?.type ===
            'message_read' &&
          item?.data?.messageId ===
            messageId,
      );

    if (alreadyRead) {
      return;
    }

    const alreadyQueued =
      offlineMessageStatus[
        username
      ].some(
        (item) =>
          item?.type ===
            type &&
          item?.data?.messageId ===
            messageId,
      );

    if (alreadyQueued) {
      return;
    }
  }

  offlineMessageStatus[
    username
  ].push({
    type,
    data,
  });

  saveOfflineMessageStatus(
    offlineMessageStatus,
  );

  console.log(
    `💾 Статус ${type} сохранён для ${username}: ${messageId}`,
  );
}

function sendOrQueueMessageStatus(
  username,
  type,
  data,
) {
  const targetSocket =
    onlineUsers.get(
      username,
    );

  if (
    targetSocket &&
    targetSocket.readyState ===
      WebSocket.OPEN
  ) {
    send(
      targetSocket,
      type,
      data,
    );

    return;
  }

  queueOfflineMessageStatus(
    username,
    type,
    data,
  );
}

function deliverOfflineMessageStatus(
  username,
  ws,
) {
  const queued =
    offlineMessageStatus[
      username
    ];

  if (
    !Array.isArray(
      queued,
    ) ||
    queued.length === 0
  ) {
    return;
  }

  if (
    !ws ||
    ws.readyState !==
      WebSocket.OPEN
  ) {
    return;
  }

  const pending = [
    ...queued,
  ];

  for (
    const item
    of pending
  ) {
    const type =
      item?.type
        ?.toString()
        .trim();

    const data =
      item?.data;

    if (
      !type ||
      !data ||
      typeof data !==
        'object' ||
      Array.isArray(
        data,
      )
    ) {
      continue;
    }

    send(
      ws,
      type,
      data,
    );
  }

  delete offlineMessageStatus[
    username
  ];

  saveOfflineMessageStatus(
    offlineMessageStatus,
  );

  console.log(
    `✅ Офлайн-статусы переданы ${username}: ${pending.length}`,
  );
}

const registeredUsers =
  loadUsers();

const fcmTokens =
  loadFcmTokens();

const offlineMessages =
  loadOfflineMessages();

const offlineMessageStatus =
  loadOfflineMessageStatus();

// ========================================
// FIREBASE PUSH
// ========================================

async function sendFcmPush({
  username,
  title,
  body,
  data = {},
}) {
  if (
    !firebaseMessaging
  ) {
    console.log(
      '⚠️ Push не отправлен: Firebase Admin недоступен',
    );

    return false;
  }

  const token =
    fcmTokens[
      username
    ];

  if (!token) {
    console.log(
      `⚠️ Push не отправлен: нет FCM token для ${username}`,
    );

    return false;
  }

  try {
    const pushData =
      Object.fromEntries(
        Object.entries(
          data,
        ).map(
          (
            [
              key,
              value,
            ],
          ) => [
            key,
            String(
              value ?? '',
            ),
          ],
        ),
      );

    const firebaseMessageId =
      await firebaseMessaging.send({
        token,

        notification: {
          title:
            String(
              title,
            ),

          body:
            String(
              body,
            ),
        },

        data:
          pushData,

        android: {
          priority:
            'high',
        },
      });

    console.log(
      `📲 FCM push отправлен: ${username}`,
    );

    console.log(
      `🔥 Firebase message ID: ${firebaseMessageId}`,
    );

    return true;
  } catch (error) {
    console.error(
      `❌ Ошибка FCM для ${username}:`,
      error.code ||
        error.message,
    );

    if (
      error.code ===
        'messaging/registration-token-not-registered' ||
      error.code ===
        'messaging/invalid-registration-token'
    ) {
      delete fcmTokens[
        username
      ];

      saveFcmTokens(
        fcmTokens,
      );

      console.log(
        `🗑️ Недействительный FCM token удалён: ${username}`,
      );
    }

    return false;
  }
}

// ========================================
// PASSWORDS
// ========================================

function hashPassword(
  password,
) {
  return new Promise(
    (
      resolve,
      reject,
    ) => {
      const salt =
        crypto
          .randomBytes(
            16,
          )
          .toString(
            'hex',
          );

      crypto.scrypt(
        password,
        salt,
        64,
        (
          error,
          derivedKey,
        ) => {
          if (
            error
          ) {
            reject(
              error,
            );

            return;
          }

          resolve({
            salt,

            hash:
              derivedKey
                .toString(
                  'hex',
                ),
          });
        },
      );
    },
  );
}

function verifyPassword(
  password,
  salt,
  originalHash,
) {
  return new Promise(
    (
      resolve,
      reject,
    ) => {
      crypto.scrypt(
        password,
        salt,
        64,
        (
          error,
          derivedKey,
        ) => {
          if (
            error
          ) {
            reject(
              error,
            );

            return;
          }

          const newHash =
            derivedKey
              .toString(
                'hex',
              );

          try {
            resolve(
              crypto
                .timingSafeEqual(
                  Buffer.from(
                    newHash,
                    'hex',
                  ),

                  Buffer.from(
                    originalHash,
                    'hex',
                  ),
                ),
            );
          } catch (_) {
            resolve(
              false,
            );
          }
        },
      );
    },
  );
}

// ========================================
// SEND
// ========================================

function send(
  ws,
  type,
  data = {},
) {
  if (
    ws &&
    ws.readyState ===
      WebSocket.OPEN
  ) {
    ws.send(
      JSON.stringify({
        type,
        data,
      }),
    );
  }
}

function broadcast(
  type,
  data = {},
) {
  for (
    const client
    of wss.clients
  ) {
    if (
      client.readyState ===
        WebSocket.OPEN
    ) {
      send(
        client,
        type,
        data,
      );
    }
  }
}

// ========================================
// ONLINE USERS
// ========================================

function broadcastUsers() {
  const users =
    Array.from(
      onlineUsers.keys(),
    );

  console.log(
    '👥 Онлайн:',
    users,
  );

  broadcast(
    'users',
    {
      users,
    },
  );
}

// ========================================
// STATUS
// ========================================

function getUserStatusData(
  username,
) {
  const user =
    registeredUsers[
      username
    ];

  if (!user) {
    return null;
  }

  return {
    username,

    online:
      onlineUsers.has(
        username,
      ),

    lastSeen:
      user.lastSeen ||
      null,
  };
}

function broadcastUserStatus(
  username,
) {
  const status =
    getUserStatusData(
      username,
    );

  if (!status) {
    return;
  }

  broadcast(
    'user_status',
    status,
  );
}

// ========================================
// USERNAME
// ========================================

function isValidUsername(
  username,
) {
  const regex =
    /^[a-zA-Zа-яА-ЯёЁ0-9_]{3,30}$/;

  return regex.test(
    username,
  );
}

// ========================================
// AVATAR
// ========================================

function getAvatarPath(
  username,
) {
  return path.join(
    AVATARS_DIR,
    `${username}.jpg`,
  );
}

// ========================================
// REACTIONS
// ========================================

function sendReactionState(
  messageId,
  reactionData,
  changedBy,
  reactionAdded,
) {
  const reactions =
    Object.fromEntries(
      reactionData.reactions,
    );

  const users =
    Object.keys(reactions);

  const selectedReaction =
    reactions[changedBy] || '';

  const payload = {
    messageId,

    from:
      reactionData.from,

    to:
      reactionData.to,

    users,

    reactions,

    count:
      users.length,

    changedBy,

    reactionAdded,

    reaction:
      selectedReaction,
  };

  const senderSocket =
    onlineUsers.get(
      reactionData.from,
    );

  const receiverSocket =
    onlineUsers.get(
      reactionData.to,
    );

  send(
    senderSocket,
    'reaction_update',
    payload,
  );

  if (
    receiverSocket &&
    receiverSocket !==
      senderSocket
  ) {
    send(
      receiverSocket,
      'reaction_update',
      payload,
    );
  }

  if (
    reactionAdded
  ) {
    const reactionRecipient =
      changedBy ===
      reactionData.from
        ? reactionData.to
        : reactionData.from;

    if (
      reactionRecipient &&
      reactionRecipient !==
        changedBy &&
      !onlineUsers.has(
        reactionRecipient,
      )
    ) {
      void sendFcmPush({
        username:
          reactionRecipient,

        title:
          `Новая реакция ${selectedReaction}`,

        body:
          `${changedBy} отреагировал(а) ${selectedReaction}`,

        data: {
          type:
            'reaction',

          sender:
            changedBy,

          recipient:
            reactionRecipient,

          messageId,
        },
      });
    }
  }
}

// ========================================
// SERVER START
// ========================================

console.log('');

console.log(
  '⚔️ SPARTAN CHAT SERVER',
);

console.log('');

console.log(
  `🚀 Сервер запущен на порту ${PORT}`,
);

console.log('');

console.log(
  '📁 Папка аватарок:',
  AVATARS_DIR,
);

console.log('');

console.log(
  '⏳ Ожидание подключений...',
);

console.log('');

// ========================================
// CONNECTION
// ========================================

wss.on(
  'connection',
  (
    ws,
    request,
  ) => {
    console.log(
      '🟢 Новое подключение:',
      request.socket
        .remoteAddress,
    );

    let currentUser =
      null;

    send(
      ws,
      'connected',
      {
        message:
          'Connected to Spartan Chat server',
      },
    );

    ws.on(
      'message',
      async (
        rawMessage,
      ) => {
        try {
          const msg =
            JSON.parse(
              rawMessage
                .toString(),
            );

          const type =
            msg.type;

          const data =
            msg.data ||
            {};

          console.log(
            '📨 Получено:',
            type,
          );

          // ====================================
          // REGISTER
          // ====================================

          if (
            type ===
            'register'
          ) {
            const username =
              data.username
                ?.trim();

            const password =
              data.password;

            if (
              !username ||
              !password
            ) {
              send(
                ws,
                'register_error',
                {
                  reason:
                    'Введите логин и пароль',
                },
              );

              return;
            }

            if (
              !isValidUsername(
                username,
              )
            ) {
              send(
                ws,
                'register_error',
                {
                  reason:
                    'Имя должно содержать от 3 до 30 символов',
                },
              );

              return;
            }

            if (
              password.length <
              4
            ) {
              send(
                ws,
                'register_error',
                {
                  reason:
                    'Пароль должен содержать минимум 4 символа',
                },
              );

              return;
            }

            if (
              registeredUsers[
                username
              ]
            ) {
              send(
                ws,
                'register_error',
                {
                  reason:
                    'Такой пользователь уже существует',
                },
              );

              return;
            }

            const passwordData =
              await hashPassword(
                password,
              );

            registeredUsers[
              username
            ] = {
              salt:
                passwordData
                  .salt,

              passwordHash:
                passwordData
                  .hash,

              createdAt:
                new Date()
                  .toISOString(),

              lastSeen:
                null,
            };

            saveUsers(
              registeredUsers,
            );

            console.log(
              `🆕 Зарегистрирован: ${username}`,
            );

            send(
              ws,
              'register_success',
              {
                username,
              },
            );

            return;
          }

          // ====================================
          // LOGIN
          // ====================================

          if (
            type ===
            'login'
          ) {
            const username =
              data.username
                ?.trim();

            const password =
              data.password;

            if (
              !username ||
              !password
            ) {
              send(
                ws,
                'login_error',
                {
                  reason:
                    'Введите логин и пароль',
                },
              );

              return;
            }

            const user =
              registeredUsers[
                username
              ];

            if (!user) {
              send(
                ws,
                'login_error',
                {
                  reason:
                    'Пользователь не зарегистрирован',
                },
              );

              return;
            }

            const passwordCorrect =
              await verifyPassword(
                password,
                user.salt,
                user.passwordHash,
              );

            if (
              !passwordCorrect
            ) {
              send(
                ws,
                'login_error',
                {
                  reason:
                    'Неверный пароль',
                },
              );

              return;
            }

            const oldWs =
              onlineUsers.get(
                username,
              );

            if (
              oldWs &&
              oldWs !==
                ws
            ) {
              console.log(
                `⚠️ ${username} вошёл с другого устройства`,
              );

              send(
                oldWs,
                'disconnected',
                {
                  reason:
                    'Вход выполнен с другого устройства',
                },
              );

              try {
                oldWs.close();
              } catch (_) {}
            }

            currentUser =
              username;

            onlineUsers.set(
              username,
              ws,
            );

            console.log(
              `👤 Вошёл пользователь: ${username}`,
            );

            send(
              ws,
              'login_success',
              {
                username,
              },
            );

            // ВАЖНО:
            // Здесь офлайн-сообщения
            // больше НЕ отправляем.
            // Клиент запросит их сам,
            // когда экран будет готов.

            broadcastUsers();

            broadcastUserStatus(
              username,
            );

            return;
          }

          // ====================================
          // GET OFFLINE MESSAGES
          // ====================================

          if (
            type ===
            'get_offline_messages'
          ) {
            if (
              !currentUser
            ) {
              send(
                ws,
                'error',
                {
                  reason:
                    'Сначала необходимо войти',
                },
              );

              return;
            }

            console.log(
              `📥 ${currentUser} запросил офлайн-сообщения`,
            );

            deliverOfflineMessages(
              currentUser,
              ws,
            );

            deliverOfflineMessageStatus(
              currentUser,
              ws,
            );

            return;
          }

          // ====================================
          // REGISTER FCM TOKEN
          // ====================================

          if (
            type ===
            'register_fcm_token'
          ) {
            if (
              !currentUser
            ) {
              send(
                ws,
                'error',
                {
                  reason:
                    'Сначала необходимо войти',
                },
              );

              return;
            }

            const token =
              data.token
                ?.toString()
                .trim();

            if (!token) {
              send(
                ws,
                'error',
                {
                  reason:
                    'FCM token отсутствует',
                },
              );

              return;
            }

            fcmTokens[
              currentUser
            ] = token;

            saveFcmTokens(
              fcmTokens,
            );

            console.log(
              `🔥 FCM token сохранён: ${currentUser}`,
            );

            send(
              ws,
              'fcm_token_registered',
              {
                username:
                  currentUser,
              },
            );

            return;
          }

          // ====================================
          // GET USERS
          // ====================================

          if (
            type ===
            'get_users'
          ) {
            const users =
              Array.from(
                onlineUsers.keys(),
              );

            send(
              ws,
              'users',
              {
                users,
              },
            );

            return;
          }

          // ====================================
          // GET USER STATUS
          // ====================================

          if (
            type ===
            'get_user_status'
          ) {
            const username =
              data.username
                ?.trim();

            if (!username) {
              send(
                ws,
                'error',
                {
                  reason:
                    'Не указано имя пользователя',
                },
              );

              return;
            }

            const status =
              getUserStatusData(
                username,
              );

            if (!status) {
              send(
                ws,
                'error',
                {
                  reason:
                    'Пользователь не найден',
                },
              );

              return;
            }

            send(
              ws,
              'user_status',
              status,
            );

            return;
          }

          // ====================================
          // TYPING
          // ====================================

          if (
            type ===
            'typing'
          ) {
            if (
              !currentUser
            ) {
              send(
                ws,
                'error',
                {
                  reason:
                    'Сначала необходимо войти',
                },
              );

              return;
            }

            const to =
              data.to
                ?.trim();

            const isTyping =
              data.isTyping ===
              true;

            if (!to) {
              send(
                ws,
                'error',
                {
                  reason:
                    'Не указан получатель статуса печати',
                },
              );

              return;
            }

            if (
              to ===
              currentUser
            ) {
              return;
            }

            if (
              !registeredUsers[
                to
              ]
            ) {
              return;
            }

            const receiver =
              onlineUsers.get(
                to,
              );

            if (
              receiver
            ) {
              send(
                receiver,
                'typing',
                {
                  from:
                    currentUser,

                  to,

                  isTyping,
                },
              );
            }

            return;
          }

          // ====================================
          // MESSAGE
          // ====================================

          if (
            type ===
            'message'
          ) {
            if (
              !currentUser
            ) {
              send(
                ws,
                'error',
                {
                  reason:
                    'Сначала необходимо войти',
                },
              );

              return;
            }

            const to =
              data.to
                ?.trim();

            const text =
              data.text
                ?.trim();

            if (
              !to ||
              !text
            ) {
              send(
                ws,
                'error',
                {
                  reason:
                    'Получатель или текст отсутствует',
                },
              );

              return;
            }

            const messageData = {
              id:
                data.id ||
                crypto.randomUUID(),

              from:
                currentUser,

              to,

              text,

              time:
                data.time ||
                new Date()
                  .toISOString(),

              replyTo:
                data.replyTo &&
                typeof data.replyTo ===
                  'object' &&
                !Array.isArray(
                  data.replyTo,
                )
                  ? {
                      id:
                        data.replyTo.id
                          ?.toString() ||
                        '',

                      from:
                        data.replyTo.from
                          ?.toString() ||
                        '',

                      text:
                        data.replyTo.text
                          ?.toString() ||
                        '',
                    }
                  : null,

              forwardedFrom:
                typeof data.forwardedFrom ===
                  'string' &&
                data.forwardedFrom.trim()
                  ? data.forwardedFrom.trim()
                  : null,

              forwardComment:
                typeof data.forwardComment ===
                  'string' &&
                data.forwardComment.trim()
                  ? data.forwardComment.trim()
                  : null,
            };

            messageReactions.set(
              messageData.id,
              {
                from:
                  currentUser,

                to,

                reactions:
                  new Map(),
              },
            );

            console.log(
              `💬 ${currentUser} → ${to}: ${text}`,
            );

            const receiver =
              onlineUsers.get(
                to,
              );

            if (
              receiver
            ) {
              send(
                receiver,
                'message',
                messageData,
              );

              console.log(
                `✅ Сообщение доставлено ${to}`,
              );
            } else {
              console.log(
                `⚠️ ${to} сейчас офлайн`,
              );

              queueOfflineMessage(
                to,
                messageData,
              );

              void sendFcmPush({
                username:
                  to,

                title:
                  currentUser,

                body:
                  text,

                data: {
                  type:
                    'message',

                  sender:
                    currentUser,

                  recipient:
                    to,

                  messageId:
                    messageData.id,
                },
              });
            }

            send(
              ws,
              'message_sent',
              messageData,
            );

            return;
          }

          // ====================================
          // PIN / UNPIN MESSAGE
          // ====================================

          if (
            type === 'pin_message' ||
            type === 'unpin_message'
          ) {
            if (!currentUser) {
              send(ws, 'error', {
                reason: 'Сначала необходимо войти',
              });
              return;
            }

            const messageId =
              data.messageId?.toString().trim();
            const to =
              data.to?.toString().trim();

            if (
              !messageId ||
              !to ||
              to === currentUser ||
              !registeredUsers[to]
            ) {
              send(ws, 'error', {
                reason: 'Недостаточно данных закрепления',
              });
              return;
            }

            const knownMessage =
              messageReactions.get(messageId);

            if (
              knownMessage &&
              !(
                (knownMessage.from === currentUser &&
                  knownMessage.to === to) ||
                (knownMessage.from === to &&
                  knownMessage.to === currentUser)
              )
            ) {
              send(ws, 'error', {
                reason: 'Нет доступа к этому сообщению',
              });
              return;
            }

            let messageFrom =
              knownMessage?.from ||
              data.messageFrom?.toString() ||
              '';
            let text =
              data.text?.toString() || '';

            const queues = [
              offlineMessages[currentUser],
              offlineMessages[to],
            ];

            for (const queue of queues) {
              if (!Array.isArray(queue)) {
                continue;
              }

              const queuedMessage = queue.find(
                (item) =>
                  !item?.__eventType &&
                  item?.id === messageId,
              );

              if (queuedMessage) {
                messageFrom = queuedMessage.from ||
                  messageFrom;
                text = queuedMessage.text || text;
                break;
              }
            }

            const eventType =
              type === 'pin_message'
                ? 'message_pinned'
                : 'message_unpinned';

            const pinData = {
              messageId,
              from: currentUser,
              to,
              messageFrom,
              text,
              changedAt: new Date().toISOString(),
            };

            const receiver = onlineUsers.get(to);

            if (
              receiver &&
              receiver.readyState === WebSocket.OPEN
            ) {
              send(receiver, eventType, pinData);
            } else {
              queueOfflineEvent(to, eventType, pinData);
            }

            send(ws, eventType, pinData);

            console.log(
              type === 'pin_message'
                ? `📌 ${currentUser} закрепил сообщение ${messageId}`
                : `📌 ${currentUser} открепил сообщение ${messageId}`,
            );

            return;
          }

          // ====================================
          // DELETE MESSAGE FOR EVERYONE
          // ====================================

          if (
            type ===
            'delete_message'
          ) {
            if (
              !currentUser
            ) {
              send(
                ws,
                'error',
                {
                  reason:
                    'Сначала необходимо войти',
                },
              );

              return;
            }

            const messageId =
              data.messageId
                ?.toString()
                .trim();

            const to =
              data.to
                ?.toString()
                .trim();

            if (
              !messageId ||
              !to ||
              to === currentUser ||
              !registeredUsers[to]
            ) {
              send(
                ws,
                'error',
                {
                  reason:
                    'Недостаточно данных для удаления',
                },
              );

              return;
            }

            const knownMessage =
              messageReactions.get(
                messageId,
              );

            const queued =
              offlineMessages[to];

            const queuedMessage =
              Array.isArray(queued)
                ? queued.find(
                    (item) =>
                      !item?.__eventType &&
                      item?.id === messageId,
                  )
                : null;

            const wrongOwner =
              knownMessage &&
              (
                knownMessage.from !==
                  currentUser ||
                knownMessage.to !== to
              );

            const wrongQueuedOwner =
              queuedMessage &&
              (
                queuedMessage.from !==
                  currentUser ||
                queuedMessage.to !== to
              );

            if (
              wrongOwner ||
              wrongQueuedOwner
            ) {
              send(
                ws,
                'error',
                {
                  reason:
                    'Нельзя удалить чужое сообщение',
                },
              );

              return;
            }

            const deleteData = {
              messageId,
              from:
                currentUser,
              to,
              deletedAt:
                new Date()
                  .toISOString(),
            };

            let removedQueuedMessage =
              false;

            if (
              Array.isArray(queued)
            ) {
              const before =
                queued.length;

              offlineMessages[to] =
                queued.filter(
                  (item) => {
                    const sameMessage =
                      item?.id === messageId &&
                      !item?.__eventType &&
                      item?.from === currentUser &&
                      item?.to === to;

                    const relatedEvent =
                      item?.__eventType &&
                      item?.messageId === messageId;

                    if (sameMessage) {
                      removedQueuedMessage =
                        true;
                    }

                    return !sameMessage &&
                      !relatedEvent;
                  },
                );

              if (
                offlineMessages[to]
                  .length !== before
              ) {
                saveOfflineMessages(
                  offlineMessages,
                );
              }
            }

            for (
              const username
              of [currentUser, to]
            ) {
              if (
                !Array.isArray(
                  offlineMessageStatus[
                    username
                  ],
                )
              ) {
                continue;
              }

              offlineMessageStatus[
                username
              ] =
                offlineMessageStatus[
                  username
                ].filter(
                  (item) =>
                    item?.data?.messageId !==
                      messageId,
                );
            }

            saveOfflineMessageStatus(
              offlineMessageStatus,
            );

            messageReactions.delete(
              messageId,
            );

            const receiver =
              onlineUsers.get(to);

            if (
              receiver &&
              receiver.readyState ===
                WebSocket.OPEN
            ) {
              send(
                receiver,
                'message_deleted',
                deleteData,
              );
            } else if (
              !removedQueuedMessage
            ) {
              queueOfflineEvent(
                to,
                'message_deleted',
                deleteData,
              );
            }

            send(
              ws,
              'message_deleted',
              deleteData,
            );

            console.log(
              `🧹 ${currentUser} удалил сообщение ${messageId} для всех`,
            );

            return;
          }

          // ====================================
          // EDIT MESSAGE
          // ====================================

          if (
            type ===
            'edit_message'
          ) {
            if (
              !currentUser
            ) {
              send(
                ws,
                'error',
                {
                  reason:
                    'Сначала необходимо войти',
                },
              );

              return;
            }

            const messageId =
              data.messageId
                ?.toString()
                .trim();

            const to =
              data.to
                ?.toString()
                .trim();

            const newText =
              data.newText
                ?.toString()
                .trim();

            if (
              !messageId ||
              !to ||
              !newText
            ) {
              send(
                ws,
                'error',
                {
                  reason:
                    'Недостаточно данных для редактирования',
                },
              );

              return;
            }

            const knownMessage =
              messageReactions.get(
                messageId,
              );

            if (
              knownMessage &&
              (
                knownMessage.from !==
                  currentUser ||
                knownMessage.to !==
                  to
              )
            ) {
              send(
                ws,
                'error',
                {
                  reason:
                    'Нельзя изменить чужое сообщение',
                },
              );

              return;
            }

            const editedAt =
              new Date()
                .toISOString();

            const editData = {
              messageId,
              from:
                currentUser,
              to,
              newText,
              editedAt,
              isEdited:
                true,
            };

            const receiver =
              onlineUsers.get(
                to,
              );

            if (
              receiver
            ) {
              send(
                receiver,
                'message_edited',
                editData,
              );
            } else {
              const queued =
                offlineMessages[
                  to
                ];

              const queuedIndex =
                Array.isArray(
                  queued,
                )
                  ? queued.findIndex(
                      (item) =>
                        !item?.__eventType &&
                        item?.id ===
                          messageId &&
                        item?.from ===
                          currentUser,
                    )
                  : -1;

              if (
                queuedIndex >= 0
              ) {
                queued[
                  queuedIndex
                ] = {
                  ...queued[
                    queuedIndex
                  ],
                  text:
                    newText,
                  editedAt,
                  isEdited:
                    true,
                };

                saveOfflineMessages(
                  offlineMessages,
                );
              } else {
                queueOfflineEvent(
                  to,
                  'message_edited',
                  editData,
                );
              }
            }

            send(
              ws,
              'message_edited',
              editData,
            );

            console.log(
              `✏️ ${currentUser} изменил сообщение ${messageId}`,
            );

            return;
          }

          // ====================================
          // MESSAGE DELIVERED
          // ====================================

          if (
            type ===
            'message_delivered'
          ) {
            if (
              !currentUser
            ) {
              send(
                ws,
                'error',
                {
                  reason:
                    'Сначала необходимо войти',
                },
              );

              return;
            }

            const messageId =
              data.messageId
                ?.toString()
                .trim();

            const messageFrom =
              data.from
                ?.toString()
                .trim();

            const messageTo =
              data.to
                ?.toString()
                .trim();

            if (
              !messageId ||
              !messageFrom ||
              !messageTo
            ) {
              return;
            }

            if (
              currentUser !==
                messageTo ||
              !registeredUsers[
                messageFrom
              ] ||
              !registeredUsers[
                messageTo
              ]
            ) {
              return;
            }

            const statusData = {
              messageId,
              from:
                messageFrom,
              to:
                messageTo,
              deliveredAt:
                new Date()
                  .toISOString(),
            };

            sendOrQueueMessageStatus(
              messageFrom,
              'message_delivered',
              statusData,
            );

            console.log(
              `✓✓ Доставлено: ${messageId} → ${messageTo}`,
            );

            return;
          }

          // ====================================
          // MESSAGE READ
          // ====================================

          if (
            type ===
            'message_read'
          ) {
            if (
              !currentUser
            ) {
              send(
                ws,
                'error',
                {
                  reason:
                    'Сначала необходимо войти',
                },
              );

              return;
            }

            const messageId =
              data.messageId
                ?.toString()
                .trim();

            const messageFrom =
              data.from
                ?.toString()
                .trim();

            const messageTo =
              data.to
                ?.toString()
                .trim();

            if (
              !messageId ||
              !messageFrom ||
              !messageTo
            ) {
              return;
            }

            if (
              currentUser !==
                messageTo ||
              !registeredUsers[
                messageFrom
              ] ||
              !registeredUsers[
                messageTo
              ]
            ) {
              return;
            }

            const statusData = {
              messageId,
              from:
                messageFrom,
              to:
                messageTo,
              readAt:
                new Date()
                  .toISOString(),
            };

            sendOrQueueMessageStatus(
              messageFrom,
              'message_read',
              statusData,
            );

            console.log(
              `👁️ Прочитано: ${messageId} → ${messageTo}`,
            );

            return;
          }

          // ====================================
          // MESSAGE REACTION
          // ====================================

          if (
            type ===
            'message_reaction'
          ) {
            if (
              !currentUser
            ) {
              send(
                ws,
                'error',
                {
                  reason:
                    'Сначала необходимо войти',
                },
              );

              return;
            }

            const messageId =
              data.messageId
                ?.toString()
                .trim();

            const messageFrom =
              data.from
                ?.toString()
                .trim();

            const messageTo =
              data.to
                ?.toString()
                .trim();

            const reaction =
              data.reaction
                ?.toString()
                .trim();

            const supportedReactions =
              new Set([
                '❤️',
                '😂',
                '😮',
                '😢',
                '😡',
                '👍',
                '🔥',
                '🎉',
                '👏',
                '🙏',
                '💯',
                '🤣',
                '😊',
                '😍',
                '🤔',
                '😎',
                '😭',
                '😱',
                '🤝',
                '👀',
                '💪',
                '✅',
                '⭐',
                '💔',
              ]);

            if (
              !messageId ||
              !messageFrom ||
              !messageTo ||
              !reaction ||
              !supportedReactions.has(
                reaction,
              )
            ) {
              send(
                ws,
                'error',
                {
                  reason:
                    'Недостаточно данных реакции',
                },
              );

              return;
            }

            const allowed =
              currentUser ===
                messageFrom ||
              currentUser ===
                messageTo;

            if (
              !allowed
            ) {
              send(
                ws,
                'error',
                {
                  reason:
                    'Нет доступа к этой реакции',
                },
              );

              return;
            }

            let reactionData =
              messageReactions.get(
                messageId,
              );

            if (
              !reactionData
            ) {
              reactionData = {
                from:
                  messageFrom,

                to:
                  messageTo,

                reactions:
                  new Map(),
              };

              messageReactions.set(
                messageId,
                reactionData,
              );
            }

            if (
              !(reactionData.reactions
                instanceof Map)
            ) {
              reactionData.reactions =
                new Map();

              if (
                reactionData.users
                  instanceof Set
              ) {
                for (
                  const user of
                    reactionData.users
                ) {
                  reactionData.reactions.set(
                    user,
                    '❤️',
                  );
                }
              }

              delete reactionData.users;
            }

            const sameParticipants =
              reactionData.from ===
                messageFrom &&
              reactionData.to ===
                messageTo;

            if (
              !sameParticipants
            ) {
              send(
                ws,
                'error',
                {
                  reason:
                    'Данные сообщения не совпадают',
                },
              );

              return;
            }

            let reactionAdded =
              false;

            const previousReaction =
              reactionData.reactions.get(
                currentUser,
              );

            if (
              previousReaction === reaction
            ) {
              reactionData.reactions.delete(
                currentUser,
              );

              reactionAdded =
                false;

              console.log(
                `♡ ${currentUser} снял ${reaction} с ${messageId}`,
              );
            } else {
              reactionData.reactions.set(
                currentUser,
                reaction,
              );

              reactionAdded =
                true;

              console.log(
                `${reaction} ${currentUser} отреагировал на ${messageId}`,
              );
            }

            sendReactionState(
              messageId,
              reactionData,
              currentUser,
              reactionAdded,
            );

            return;
          }

          // ====================================
          // UPLOAD AVATAR
          // ====================================

          if (
            type ===
            'upload_avatar'
          ) {
            if (
              !currentUser
            ) {
              send(
                ws,
                'avatar_error',
                {
                  reason:
                    'Сначала необходимо войти',
                },
              );

              return;
            }

            const avatar =
              data.avatar;

            if (
              !avatar ||
              typeof avatar !==
                'string'
            ) {
              send(
                ws,
                'avatar_error',
                {
                  reason:
                    'Аватарка отсутствует',
                },
              );

              return;
            }

            try {
              const avatarBuffer =
                Buffer.from(
                  avatar,
                  'base64',
                );

              const maxSize =
                5 *
                1024 *
                1024;

              if (
                avatarBuffer.length >
                maxSize
              ) {
                send(
                  ws,
                  'avatar_error',
                  {
                    reason:
                      'Аватарка слишком большая',
                  },
                );

                return;
              }

              const avatarPath =
                getAvatarPath(
                  currentUser,
                );

              fs.writeFileSync(
                avatarPath,
                avatarBuffer,
              );

              console.log(
                `🖼️ Аватарка сохранена: ${currentUser}`,
              );

              send(
                ws,
                'avatar_uploaded',
                {
                  username:
                    currentUser,
                },
              );

              broadcast(
                'avatar_updated',
                {
                  username:
                    currentUser,
                },
              );
            } catch (
              error
            ) {
              console.error(
                '❌ Ошибка сохранения аватарки:',
                error,
              );

              send(
                ws,
                'avatar_error',
                {
                  reason:
                    'Не удалось сохранить аватарку',
                },
              );
            }

            return;
          }

          // ====================================
          // GET AVATAR
          // ====================================

          if (
            type ===
            'get_avatar'
          ) {
            const username =
              data.username
                ?.trim();

            if (
              !username
            ) {
              send(
                ws,
                'avatar_error',
                {
                  reason:
                    'Не указано имя пользователя',
                },
              );

              return;
            }

            const avatarPath =
              getAvatarPath(
                username,
              );

            if (
              !fs.existsSync(
                avatarPath,
              )
            ) {
              send(
                ws,
                'avatar_data',
                {
                  username,

                  avatar:
                    null,
                },
              );

              return;
            }

            try {
              const avatarBuffer =
                fs.readFileSync(
                  avatarPath,
                );

              const avatarBase64 =
                avatarBuffer
                  .toString(
                    'base64',
                  );

              send(
                ws,
                'avatar_data',
                {
                  username,

                  avatar:
                    avatarBase64,
                },
              );

              console.log(
                `🖼️ Аватарка отправлена: ${username}`,
              );
            } catch (
              error
            ) {
              console.error(
                '❌ Ошибка чтения аватарки:',
                error,
              );

              send(
                ws,
                'avatar_error',
                {
                  reason:
                    'Не удалось загрузить аватарку',
                },
              );
            }

            return;
          }

          // ====================================
          // DELETE AVATAR
          // ====================================

          if (
            type ===
            'delete_avatar'
          ) {
            if (
              !currentUser
            ) {
              send(
                ws,
                'avatar_error',
                {
                  reason:
                    'Сначала необходимо войти',
                },
              );

              return;
            }

            try {
              const avatarPath =
                getAvatarPath(
                  currentUser,
                );

              if (
                fs.existsSync(
                  avatarPath,
                )
              ) {
                fs.unlinkSync(
                  avatarPath,
                );
              }

              console.log(
                `🗑️ Аватарка удалена: ${currentUser}`,
              );

              send(
                ws,
                'avatar_deleted',
                {
                  username:
                    currentUser,
                },
              );

              broadcast(
                'avatar_updated',
                {
                  username:
                    currentUser,
                },
              );
            } catch (
              error
            ) {
              console.error(
                '❌ Ошибка удаления аватарки:',
                error,
              );
            }

            return;
          }

          // ====================================
          // PING
          // ====================================

          if (
            type ===
            'ping'
          ) {
            send(
              ws,
              'pong',
              {
                time:
                  new Date()
                    .toISOString(),
              },
            );

            return;
          }

          // ====================================
          // UNKNOWN
          // ====================================

          send(
            ws,
            'error',
            {
              reason:
                `Неизвестная команда: ${type}`,
            },
          );
        } catch (
          error
        ) {
          console.error(
            '❌ Ошибка обработки:',
            error,
          );

          send(
            ws,
            'error',
            {
              reason:
                'Ошибка обработки сообщения',
            },
          );
        }
      },
    );

    // ========================================
    // CLOSE
    // ========================================

    ws.on(
      'close',
      () => {
        if (
          currentUser &&
          onlineUsers.get(
            currentUser,
          ) === ws
        ) {
          onlineUsers.delete(
            currentUser,
          );

          if (
            registeredUsers[
              currentUser
            ]
          ) {
            registeredUsers[
              currentUser
            ].lastSeen =
              new Date()
                .toISOString();

            saveUsers(
              registeredUsers,
            );
          }

          console.log(
            `🔴 Отключился: ${currentUser}`,
          );

          broadcastUsers();

          broadcastUserStatus(
            currentUser,
          );
        }
      },
    );

    // ========================================
    // ERROR
    // ========================================

    ws.on(
      'error',
      (
        error,
      ) => {
        console.log(
          '❌ WebSocket ошибка:',
          error.message,
        );
      },
    );
  },
);
