import 'package:flutter_test/flutter_test.dart';
import '../lib/services/temporary_recovery_store.dart';

void main() {
  final now = DateTime.utc(2026, 11, 22, 12);
  final session = 'a' * 48;
  final token = 'b' * 64;

  test('guest metadata roundtrip without plaintext history', () {
    final entry = TemporaryRecoveryEntry(
      sessionId: session, role: 'guest',
      invitationToken: token,
      expiresAt: now.add(const Duration(hours: 1)),
    );
    final encoded = TemporaryRecoveryCodec.encode([entry], now);
    expect(encoded, isNot(contains('messageText')));
    final restored = TemporaryRecoveryCodec.decode(encoded, now);
    expect(restored, hasLength(1));
    expect(restored.single.invitationToken, token);
  });

  test('owner metadata never includes invitation secret', () {
    final entry = TemporaryRecoveryEntry(
      sessionId: session, role: 'owner',
      expiresAt: now.add(const Duration(hours: 1)),
    );
    final result = TemporaryRecoveryCodec.decode(
      TemporaryRecoveryCodec.encode([entry], now), now,
    );
    expect(result.single.invitationToken, isNull);
  });

  test('expired and malformed identities fail closed', () {
    final expired = TemporaryRecoveryEntry(
      sessionId: session, role: 'guest', invitationToken: token,
      expiresAt: now.subtract(const Duration(seconds: 1)),
    );
    expect(TemporaryRecoveryCodec.encode([expired], now), contains('"entries":[]'));
    expect(TemporaryRecoveryCodec.decode('{"version":2,"entries":[]}', now), isEmpty);
    expect(TemporaryRecoveryCodec.decode('not json', now), isEmpty);
    expect(TemporaryRecoveryEntry.fromJson({'id': 'broken', 'role': 'guest', 'exp': now.add(const Duration(hours: 1)).toIso8601String(), 'token': token}, now), isNull);
  });

  test('guest must retain token and owner must not retain token', () {
    final expires = now.add(const Duration(hours: 1));
    expect(TemporaryRecoveryEntry(sessionId: session, role: 'guest', expiresAt: expires).validAt(now), false);
    expect(TemporaryRecoveryEntry(sessionId: session, role: 'owner', invitationToken: token, expiresAt: expires).validAt(now), false);
  });

  test('same session cannot be duplicated', () {
    final entry = TemporaryRecoveryEntry(
      sessionId: session, role: 'guest', invitationToken: token,
      expiresAt: now.add(const Duration(hours: 1)),
    );
    expect(() => TemporaryRecoveryCodec.encode([entry, entry], now), throwsStateError);
  });

  test('automatic guest candidate requires exactly one valid guest', () {
    final guest = TemporaryRecoveryEntry(
      sessionId: session, role: 'guest', invitationToken: token,
      expiresAt: now.add(const Duration(hours: 1)),
    );
    final owner = TemporaryRecoveryEntry(
      sessionId: 'c' * 48, role: 'owner',
      expiresAt: now.add(const Duration(hours: 1)),
    );
    final secondGuest = TemporaryRecoveryEntry(
      sessionId: 'd' * 48, role: 'guest', invitationToken: 'e' * 64,
      expiresAt: now.add(const Duration(hours: 1)),
    );
    expect(TemporaryRecoveryCodec.singleGuestCandidate([owner], now), isNull);
    expect(TemporaryRecoveryCodec.singleGuestCandidate([owner, guest], now), guest);
    expect(TemporaryRecoveryCodec.singleGuestCandidate([guest, secondGuest], now), isNull);
    expect(TemporaryRecoveryCodec.singleGuestCandidate([guest], now.add(const Duration(hours: 2))), isNull);
  });

  test('storage keys separated by account and require identity', () {
    expect(TemporaryRecoveryStore.keyForAccount('account-1'),
      isNot(TemporaryRecoveryStore.keyForAccount('account-2')));
    expect(() => TemporaryRecoveryStore.keyForAccount(' '), throwsFormatException);
  });
}
