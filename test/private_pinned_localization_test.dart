import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const keys = [
    'privatePinPinned',
    'privatePinUnpinned',
    'privatePinUnavailable',
  ];

  test('all pinned notices use per-user translations', () {
    final source = File('lib/widgets/private_pinned_messages.dart')
        .readAsStringSync();

    for (final key in keys) {
      expect(source.contains("_chatText('$key')"), isTrue);
    }
  });

  test('translations exist in RU UK EN', () {
    final source = File('lib/services/app_language_service.dart')
        .readAsStringSync();

    for (final key in keys) {
      expect(
        RegExp("'$key':").allMatches(source).length,
        3,
        reason: 'Missing translations for $key',
      );
    }
  });

  test('durable pin storage and signaling remain', () {
    final source = File('lib/widgets/private_pinned_messages.dart')
        .readAsStringSync();

    expect(source.contains('StorageService.mutateMessagesDurably'), isTrue);
    expect(source.contains('SocketService.instance.setPinnedMessage'), isTrue);
    expect(source.contains('_jumpToPinnedMessage('), isTrue);
  });
}
