import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('E2EE core modules remain individually discoverable', () {
    final expected = [
      'signal_e2ee_service.dart',
      'signal_secure_store.dart',
      'e2ee_media_cipher.dart',
      'account_recovery_service.dart',
      'recovery_signature_service.dart',
    ];

    for (final name in expected) {
      final file = File('lib/services/crypto/$name');
      expect(file.existsSync(), isTrue, reason: name);
    }
  });

  test('main Signal E2EE integration points remain present', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final socket = File('lib/services/socket_service.dart').readAsStringSync();

    expect(chat, contains('signal_e2ee_service'));
    expect(socket, contains('signal_e2ee_service'));
  });

  test('crypto module map remains available', () {
    expect(
      File('lib/services/crypto/README_E2EE_MODULES.md').existsSync(),
      isTrue,
    );
  });
}