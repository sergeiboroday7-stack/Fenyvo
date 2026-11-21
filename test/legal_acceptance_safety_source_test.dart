import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final auth = File('lib/screens/auth_screen.dart').readAsStringSync();
  final socket = File('lib/services/socket_service.dart').readAsStringSync();

  test('legal consent ignores unsolicited and stale acknowledgements', () {
    expect(auth, contains('if (!_legalPromptOpen ||'));
    expect(auth, contains('!_legalAcceptancePending ||'));
    expect(auth, contains('!SocketService.instance.isAuthenticated'));
    expect(auth, contains("if (_legalPromptOpen && type == 'disconnected')"));
  });

  test('legal consent prevents duplicate submission and handles timeouts', () {
    expect(auth, contains('!_legalAcceptancePending;'));
    expect(auth, contains('if (!sent) {'));
    expect(auth, contains('const Duration(seconds: 15)'));
    expect(auth, contains('canPop: false'));
    expect(socket, contains('bool acceptLegal({'));
    expect(socket, contains('if (!isAuthenticated) return false;'));
    expect(socket, contains("return _send('accept_legal', {"));
  });
}
