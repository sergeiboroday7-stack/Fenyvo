import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final keys = <String>[
    'privateForwardVoice',
    'privateForwardPhoto',
    'privateForwardVideo',
    'privateForwardNoChats',
    'privateForwardTitle',
    'privateForwardSearchContact',
    'privateForwardAddComment',
    'privateForwardSelectRecipient',
    'privateForwardSend',
    'privateForwardSendCount',
  ];

  test('all forward labels use translation keys', () {
    final source = File('lib/widgets/private_forward_message_sheet.dart')
        .readAsStringSync();

    for (final key in keys) {
      expect(source.contains("'$key'"), isTrue, reason: 'Missing UI key: $key');
    }
  });

  test('each key exists in three languages', () {
    final source = File('lib/services/app_language_service.dart')
        .readAsStringSync();

    for (final key in keys) {
      expect(
        RegExp("'$key':").allMatches(source).length,
        3,
        reason: 'Missing translation: $key',
      );
    }
  });

  test('message sending stays outside forward UI', () {
    final source = File('lib/widgets/private_forward_message_sheet.dart')
        .readAsStringSync();

    expect(source.contains('_sendForwardedMessage('), isTrue);
    expect(source.contains('SocketService.instance.send'), isFalse);
  });
}
