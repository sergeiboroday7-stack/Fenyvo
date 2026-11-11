import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('validated failure triggers controlled recovery only', () {
    final code = File('lib/services/socket_service.dart')
        .readAsStringSync();
    final start = code.indexOf(
      "if (type == 'e2ee_decrypt_failure')",
    );
    final end = code.indexOf(
      "if (type == 'e2ee_prekey_bundle')", start,
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final handler = code.substring(start, end);
    final validation = handler.indexOf('originalMessage.length != 1');
    final status = handler.indexOf(
      "updateOutboxStatus(owner, messageId, 'decrypt_failed')",
    );
    final recovery = handler.indexOf('requestFreshE2eeSession(peer)');

    expect(validation, greaterThanOrEqualTo(0));
    expect(status, greaterThan(validation));
    expect(recovery, greaterThan(status));
    expect(handler, contains('_e2eeRecoveryPeers.add(peer)'));
    expect(handler, contains('_e2eeRecoveryPeers.remove(peer)'));
    expect(handler, contains('SocketEventGenerationGuard.isCurrent'));
    expect(handler, isNot(contains('resetPeerSession(')));
    expect(handler, isNot(contains('deleteSession(')));
    expect(handler, isNot(contains('removeOutboxMessage(')));
    expect(handler, isNot(contains('_sendE2eeMessage(')));
  });
}