# Device transfer - implementation status

Foundation only. NOT connected to runtime.

The module proposes a permanent opaque account ID without changing accounts, credentials, contacts or Signal trust. The proposal must be persisted atomically before the ID is exposed. Persistence and runtime wiring are pending.

A new ordinary login currently disconnects the old device. Old-device approval must happen before replacement login or through a separately authenticated transfer channel.

Keep existing username routing and chat keys compatible. accountId is not proof of trusted replacement keys. Do not upload private Signal keys or recovery phrases. Lost-device recovery still requires trusted-channel verification of replacement keys.

Future checks: persistence failure and restart, replay, expiration, substituted keys, account isolation, offline contacts and retained history. New UI must support RU/UK/EN.

STEP 42: isolated account ID persistence added with atomic JSON writer. Tests cover reload, write failure, stale state and unchanged credentials/contacts. Runtime wiring remains disabled. Hardware power-loss and multi-process durability are not claimed.

STEP 43: local login adapter added behind FENYVO_ACCOUNT_ID_ENABLED=true. Default off. Runs after password verification and before old-device disconnection. Persistence errors return localized temporary failure. Adapter and source-placement tests passed; full WebSocket integration and production deployment remain pending.

STEP 44: 7 isolated real WebSocket login tests passed; full server bootstrap was not tested. STEP 45: optional authenticated client account ID support passed analyzer and 25 tests; chat and Signal storage addressing unchanged.
STEP 47: isolated one-time challenge lifecycle added. Binds current old session, password-verified pending new session, account ID and candidate digest through required providers. Expiry, cancellation, capacity and replay checks tested. takeForVerification only consumes a request and returns data; it is NOT authorization and does NOT verify a signature or trust replacement keys. Runtime providers, proof verification, contact propagation and history transfer remain pending.
