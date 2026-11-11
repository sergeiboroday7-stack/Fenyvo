import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final methods = <String>[
    '_isMessagePinned',
    '_getPinnedMessages',
    '_togglePinnedMessage',
    '_jumpToPinnedMessage',
    '_buildPinnedMessageBanner',
  ];

  test('pinned methods are extracted', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();

    final module = File('lib/widgets/private_pinned_messages.dart')
        .readAsStringSync();

    expect(
      chat.contains("part '../widgets/private_pinned_messages.dart';"),
      isTrue,
    );

    expect(module.contains("part of '../screens/chat_screen.dart';"), isTrue);

    for (final name in methods) {
      expect(
        module.contains('$name('),
        isTrue,
        reason: 'Missing method: $name',
      );
    }
  });

  test('pinned state changes remain owned by ChatScreen', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();

    final module = File('lib/widgets/private_pinned_messages.dart')
        .readAsStringSync();

    expect(
      chat.contains('void _updatePinnedMessageState(VoidCallback update)'),
      isTrue,
    );

    expect(chat.contains('setState(update);'), isTrue);

    expect(
      RegExp(r'_updatePinnedMessageState\s*\(').allMatches(module).length,
      3,
    );

    expect(RegExp(r'(?<![\w.])setState\s*\(').hasMatch(module), isFalse);
  });

  test('durable storage and socket signaling remain', () {
    final module = File('lib/widgets/private_pinned_messages.dart')
        .readAsStringSync();

    expect(module.contains('StorageService.mutateMessagesDurably'), isTrue);

    expect(module.contains('StorageService.addPinnedMessage'), isTrue);

    expect(module.contains('StorageService.removePinnedMessage'), isTrue);

    expect(module.contains('SocketService.instance.setPinnedMessage'), isTrue);

    expect(module.contains('_pinnedHighlightTimer'), isTrue);

    expect(module.contains('_messageScrollController'), isTrue);
  });
}
