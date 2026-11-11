import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Signal private edit checks account and connection before dispatch', () {
    final source =
        File('lib/services/socket_service.dart').readAsStringSync();

    final start = source.indexOf(
      "if (decrypted['kind'] == 'private_edit_v1')",
    );

    expect(start, greaterThanOrEqualTo(0));

    final dispatch = source.indexOf(
      "'type': 'private_e2ee_edit'",
      start,
    );

    expect(dispatch, greaterThan(start));

    final section = source.substring(start, dispatch);

    expect(
      section,
      contains('SocketEventGenerationGuard.isCurrent('),
    );
    expect(section, contains('eventGeneration: generation'));
    expect(section, contains('currentGeneration: _connectionGeneration'));
    expect(section, contains('eventChannel: channel'));
    expect(section, contains('currentChannel: _channel'));
    expect(section, contains('!isAuthenticated'));
    expect(section, contains('currentUser?.trim() != outerTo.trim()'));
    expect(section, contains('return;'));
  });

  test('raw unverified edit still cannot reach general dispatch', () {
    final source =
        File('lib/services/socket_service.dart').readAsStringSync();

    final guard = source.indexOf(
      "if (type == 'private_e2ee_edit')",
    );
    final general = source.lastIndexOf(
      '_notifyHandlers(message);',
    );

    expect(guard, greaterThanOrEqualTo(0));
    expect(general, greaterThan(guard));
  });
}