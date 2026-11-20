import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('offline delivery completion must not erase existing E2EE sessions', () {
    final socketSource = File('lib/services/socket_service.dart').readAsStringSync();

    expect(socketSource, contains("if (type == 'offline_messages_complete')"));
    expect(socketSource, isNot(contains('_migrateLegacyRatchetSessionsOnce(')));
    expect(socketSource, isNot(contains('resetAllRatchetSessions(')));
    expect(socketSource, isNot(contains('deleteEverySession(')));
  });

  test('processing a remote pre-key bundle preserves an existing session', () {
    final signalSource = File('lib/services/crypto/signal_e2ee_service.dart')
        .readAsStringSync();
    final methodStart = signalSource.indexOf('Future<void> processRemoteBundle(');
    expect(methodStart, greaterThanOrEqualTo(0));

    final methodBody = signalSource.substring(methodStart);
    final existingSessionGuard =
        methodBody.indexOf('if (await store.containsSession(address)) return;');
    final bundleCreation = methodBody.indexOf('final bundle = PreKeyBundle(');

    expect(existingSessionGuard, greaterThanOrEqualTo(0));
    expect(bundleCreation, greaterThan(existingSessionGuard));
  });
}
