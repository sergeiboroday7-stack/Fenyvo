# FENYVO — E2EE modules

## Existing modules

- `signal_e2ee_service.dart` — main Signal E2EE implementation.
- `signal_secure_store.dart` — storage support for Signal cryptographic state.
- `e2ee_media_cipher.dart` — media encryption and decryption.
- `account_recovery_service.dart` — account recovery logic.
- `recovery_signature_service.dart` — recovery signatures.

## Related services

- `../encryption_service.dart`
- `../e2ee_settings_service.dart`

## Integration points

The main Signal E2EE service is imported by:
- `lib/screens/chat_screen.dart`
- `lib/services/socket_service.dart`

## Engineering rules

1. Keep encryption and decryption on the client.
2. Do not introduce plaintext message or key handling in `server.js`.
3. Preserve existing ciphertext formats, persistent keys and recovery data.
4. Do not migrate key storage merely to reorganize source files.
5. New encryption-related functionality requires automated tests.
6. New user-facing functionality must support RU, UK and EN.
7. Group E2EE and temporary E2EE require separate architecture and compatibility review before implementation.

## Pending work

- Verify group chat encryption architecture before introducing a dedicated group service.
- Locate and reconcile the earlier temporary E2EE implementation before restoring it.
- Run Android and Windows integration checks before publishing any crypto change.

This file documents existing boundaries. It does not certify that all
cryptographic security properties have been independently audited.