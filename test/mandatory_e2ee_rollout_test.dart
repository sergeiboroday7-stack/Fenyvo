import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final socketSource = File('lib/services/socket_service.dart')
      .readAsStringSync();
  final serverSource = File('server.js').readAsStringSync();

  test('login success reaches UI before E2EE bootstrap', () {
    final loginStart = socketSource.indexOf("if (type == 'login_success')");
    final loginEnd = socketSource.indexOf(
      "if (type == 'communication_state')",
      loginStart,
    );
    final login = socketSource.substring(loginStart, loginEnd);

    expect(login.indexOf('_notifyHandlers(message);'), greaterThan(-1));
    expect(login.indexOf('_prepareE2ee(username)'), greaterThan(-1));
    expect(
      login.indexOf('_notifyHandlers(message);'),
      lessThan(login.indexOf('_prepareE2ee(username)')),
    );
    expect(login, contains('unawaited(() async'));
  });

  test('missing peer keys queue ciphertext without plaintext fallback', () {
    expect(
      socketSource,
      contains("data['code']?.toString() == 'e2ee_keys_pending'"),
    );
    expect(
      socketSource,
      contains("final status = retryable ? 'queued' : 'failed'"),
    );
    expect(socketSource, contains("'waitingForE2ee': true"));
    expect(serverSource, contains("code: 'e2ee_keys_pending'"));
    expect(serverSource, contains('retryable: true'));
    expect(socketSource, isNot(contains("_send('message', payload)")));
  });
}
