import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Signal failure event is validated and never resets keys', () {
    final source =
        File('lib/services/socket_service.dart').readAsStringSync();

    final start = source.indexOf(
      "if (type == 'e2ee_decrypt_failure')",
    );
    final end = source.indexOf(
      "if (type == 'e2ee_prekey_bundle')", start,
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final handler = source.substring(start, end);

    expect(handler, contains('SocketEventGenerationGuard.isCurrent'));
    expect(handler, contains('!isAuthenticated'));
    expect(handler, contains('eventSender != owner'));
    expect(handler, contains('peer == owner'));
    expect(handler, contains("data['messageId']"));
    expect(handler, contains("'type': 'e2ee_decrypt_failure'"));

    expect(handler, isNot(contains('resetPeerSession(')));
    expect(handler, isNot(contains('deleteSession(')));
    expect(handler, isNot(contains('_sendE2eeMessage(')));
    expect(handler, contains('requestFreshE2eeSession(peer)'));
  });
}