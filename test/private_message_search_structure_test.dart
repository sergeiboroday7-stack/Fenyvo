import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final methods = <String>[
    '_recalculateSearchMatches',
    '_openMessageSearch',
    '_closeMessageSearch',
    '_onMessageSearchChanged',
    '_jumpToCurrentSearchMatch',
    '_nextMessageSearchMatch',
    '_buildMessageSearchBar',
  ];

  test('search methods are extracted', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final part = File('lib/widgets/private_message_search.dart')
        .readAsStringSync();

    expect(
      chat.contains("part '../widgets/private_message_search.dart';"),
      isTrue,
    );

    expect(part.contains("part of '../screens/chat_screen.dart';"), isTrue);

    for (final name in methods) {
      expect(
        RegExp('(void|Future<void>|Widget)\\s+' + name + r'\s*\(')
            .hasMatch(part),
        isTrue,
        reason: 'Missing method: $name',
      );
    }
  });

  test('search uses a State-owned update wrapper', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final part = File('lib/widgets/private_message_search.dart')
        .readAsStringSync();

    expect(
      chat.contains('void _updateMessageSearchState(VoidCallback update)'),
      isTrue,
    );
    expect(chat.contains('setState(update);'), isTrue);

    expect(
      RegExp(r'_updateMessageSearchState\s*\(').allMatches(part).length,
      4,
    );

    expect(RegExp(r'(?<![\w.])setState\s*\(').hasMatch(part), isFalse);
  });

  test('existing search behavior remains connected', () {
    final part = File('lib/widgets/private_message_search.dart')
        .readAsStringSync();

    expect(part.contains('MessageSearchService.matches'), isTrue);
    expect(part.contains('_jumpToPinnedMessage('), isTrue);
    expect(part.contains('searchConversationHint'), isTrue);
    expect(part.contains('previousMatch'), isTrue);
    expect(part.contains('nextMatch'), isTrue);
    expect(part.contains('closeSearch'), isTrue);
    expect(part.contains('SocketService.instance.send'), isFalse);
  });
}
