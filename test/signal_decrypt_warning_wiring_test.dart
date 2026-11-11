import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('decryption error surfaces a safe user verification prompt', () {
    final socket = File('lib/services/socket_service.dart').readAsStringSync();
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    expect(socket, contains("'type': 'e2ee_local_decrypt_failure'"));
    expect(socket, contains("'data': {'peer': from}"));
    expect(chat, contains("type == 'e2ee_local_decrypt_failure'"));
    expect(chat, contains('data[\'peer\']?.toString().trim() == widget.targetUser'));
    expect(chat, contains('_showE2eeDecryptWarning()'));
    expect(chat, contains("value: 'e2ee_recovery'"));
    expect(chat, contains('await _showVerifiedE2eeRecovery()'));
    expect(chat, contains('await SignalE2eeService.instance.acceptVerifiedRemoteBundle('));
  });
}
