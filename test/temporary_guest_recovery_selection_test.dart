import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/temporary_recovery_store.dart';

void main() {
  final now = DateTime.utc(2026, 11, 23, 12);
  final id = 'a' * 48;
  final ownerId = 'b' * 48;
  final token = 'c' * 64;
  final exp = now.add(const Duration(hours: 2));
  TemporaryRecoveryEntry guest(String sessionId) => TemporaryRecoveryEntry(
    sessionId: sessionId, role: 'guest', expiresAt: exp,
    invitationToken: token,
  );
  Map<String, dynamic> record(String sessionId, String role,
      [DateTime? expiry]) => <String, dynamic>{
    'sessionId': sessionId, 'role': role,
    'expiresAt': (expiry ?? exp).toIso8601String(),
  };

  test('guest is recoverable while unrelated owner chat is active', () {
    final result = TemporaryRecoveryCodec.confirmedGuest(
      [guest(id)], [record(id, 'guest')], {ownerId}, now,
    );
    expect(result?.sessionId, id);
    expect(result?.invitationToken, token);
  });
  test('absent server guest or wrong role denies restoration', () {
    expect(TemporaryRecoveryCodec.confirmedGuest(
      [guest(id)], [record(id, 'owner')], {}, now,
    ), isNull);
    expect(TemporaryRecoveryCodec.confirmedGuest(
      [guest(id)], [], {}, now,
    ), isNull);
  });
  test('already active guest is not rejoined', () {
    expect(TemporaryRecoveryCodec.confirmedGuest(
      [guest(id)], [record(id, 'guest')], {id}, now,
    ), isNull);
  });
  test('expired server confirmation denies restoration', () {
    expect(TemporaryRecoveryCodec.confirmedGuest(
      [guest(id)], [record(id, 'guest', now.subtract(const Duration(seconds: 1)))], {}, now,
    ), isNull);
  });
  test('multiple eligible guests are not chosen arbitrarily', () {
    final otherId = 'd' * 48;
    expect(TemporaryRecoveryCodec.confirmedGuest(
      [guest(id), guest(otherId)],
      [record(id, 'guest'), record(otherId, 'guest')], {}, now,
    ), isNull);
  });
  test('server cannot extend expiration beyond local record', () {
    final result = TemporaryRecoveryCodec.confirmedGuest(
      [guest(id)], [record(id, 'guest', exp.add(const Duration(days: 1)))], {}, now,
    );
    expect(result?.expiresAt, exp);
  });
}
