import 'package:flutter_test/flutter_test.dart';
import '../lib/services/temporary_recovery_store.dart';

void main() {
  final now = DateTime.utc(2026, 11, 23, 12);
  final id = 'a' * 48;
  final other = 'b' * 48;
  final future = now.add(const Duration(days: 1));
  TemporaryRecoveryEntry owner(String session) => TemporaryRecoveryEntry(
    sessionId: session, role: 'owner', expiresAt: future,
  );
  Map<String, dynamic> record(String session, String role, DateTime expiration) => {
    'sessionId': session, 'role': role, 'expiresAt': expiration.toIso8601String(),
  };

  test('only matching locally saved owner can be recovered', () {
    final records = TemporaryRecoveryCodec.confirmedOwners(
      [owner(id)], [record(id, 'owner', future),record(other,'owner',future)], now,
    );
    expect(records.map((e)=>e.sessionId).toList(), [id]);
  });
  test('server session absent fails closed', () {
    expect(TemporaryRecoveryCodec.confirmedOwners([owner(id)], [], now), isEmpty);
  });
  test('local session absent fails closed', () {
    expect(TemporaryRecoveryCodec.confirmedOwners([], [record(id,'owner',future)], now), isEmpty);
  });
  test('guest cannot be imported as owner', () {
    expect(TemporaryRecoveryCodec.confirmedOwners([owner(id)], [record(id,'guest',future)], now), isEmpty);
  });
  test('revoked or expired server session is excluded from owner recovery', () {
    expect(TemporaryRecoveryCodec.confirmedOwners([owner(id)], [record(id,'owner',now.subtract(const Duration(seconds:1)))], now),isEmpty);
  });
  test('multiple owners remain independent and duplicate is rejected', () {
    final records = TemporaryRecoveryCodec.confirmedOwners(
      [owner(id),owner(id),owner(other)],
      [record(id,'owner',future),record(other,'owner',future)],now);
    expect(records.length,2);
  });
  test('malformed server data cannot create recovery', () {
    expect(TemporaryRecoveryCodec.confirmedOwners([owner(id)], [
      {'sessionId':'evil','role':'owner','expiresAt':future.toIso8601String()},
    ],now),isEmpty);
  });
  test('server expiry takes precedence over local metadata', () {
    final expiration = now.add(const Duration(hours:2));
    final records = TemporaryRecoveryCodec.confirmedOwners([owner(id)],
      [record(id,'owner',expiration)], now);
    expect(records.single.expiresAt,expiration);
  });
}
