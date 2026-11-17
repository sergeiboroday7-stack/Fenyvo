import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('calls reuse an existing Signal session', () {
    final socketSource = File('lib/services/socket_service.dart')
        .readAsStringSync();
    final cryptoSource = File('lib/services/crypto/signal_e2ee_service.dart')
        .readAsStringSync();

    expect(
      socketSource,
      contains('if (!await SignalE2eeService.instance.hasSession(peer))'),
    );
    expect(socketSource, contains('processRemoteBundleIfMissing('));
    expect(
      cryptoSource,
      contains('onlyIfMissing && await store.containsSession(address)'),
    );
    expect(socketSource, contains("_ratchetSessionMigration = 'reuse_4228'"));
    expect(socketSource, contains('resetAllRatchetSessions()'));
  });

  test('a locally undecipherable call answer stops ringback and refreshes', () {
    final socketSource = File('lib/services/socket_service.dart')
        .readAsStringSync();
    final callSource = File('lib/services/call_service.dart')
        .readAsStringSync();

    expect(socketSource, contains("'type': 'call_e2ee_answer_error'"));
    expect(callSource, contains("case 'call_e2ee_answer_error':"));
    expect(callSource, contains('Future<void> _recoverE2eeAnswer(String id)'));
    expect(callSource, contains("'Защита обновлена — позвоните ещё раз'"));
  });
}
