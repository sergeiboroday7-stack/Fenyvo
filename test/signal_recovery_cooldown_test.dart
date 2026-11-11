import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Signal recovery requires cooldown and account-scoped peer', () {
    final source = File('lib/services/socket_service.dart')
        .readAsStringSync();

    final start = source.indexOf(
      "if (type == 'e2ee_decrypt_failure')",
    );
    final end = source.indexOf(
      "if (type == 'e2ee_prekey_bundle')",
      start,
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final handler = source.substring(start, end);

    expect(handler, contains("final recoveryKey = '\$owner:\$peer'"));
    expect(handler, contains('const Duration(minutes: 10)'));
    expect(handler, contains('!cooldownActive'));
    expect(handler, contains('_e2eeRecoveryPeers.add(peer)'));
    expect(handler, contains('_e2eeRecoveryAttempts[recoveryKey]'));
    expect(handler, contains('requestFreshE2eeSession(peer)'));
    expect(handler, contains('originalMessage.length != 1'));
    expect(handler, contains('_e2eeRecoveryAttempts.length > 128'));

    expect(handler, isNot(contains('resetPeerSession(')));
    expect(handler, isNot(contains('deleteSession(')));
    expect(handler, isNot(contains('_sendE2eeMessage(')));
    expect(handler, isNot(contains('removeOutboxMessage(')));
  });
}