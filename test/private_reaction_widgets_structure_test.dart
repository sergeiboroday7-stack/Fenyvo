import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reaction UI is extracted to a Dart part', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final module = File('lib/widgets/private_reaction_widgets.dart')
        .readAsStringSync();

    expect(
      chat.contains("part '../widgets/private_reaction_widgets.dart';"),
      isTrue,
    );
    expect(module.contains("part of '../screens/chat_screen.dart';"), isTrue);
    expect(module.contains('extension _PrivateReactionWidgets'), isTrue);
  });

  test('both reaction widget implementations are relocated', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final module = File('lib/widgets/private_reaction_widgets.dart')
        .readAsStringSync();

    for (final name in ['_buildReactionChip', '_buildQuickReactionButton']) {
      expect(RegExp(r'Widget\s+' + name + r'\s*\(').hasMatch(module), isTrue);
      expect(RegExp(r'Widget\s+' + name + r'\s*\(').hasMatch(chat), isFalse);
    }
  });

  test('message sending remains outside reaction UI widgets', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final module = File('lib/widgets/private_reaction_widgets.dart')
        .readAsStringSync();

    expect(chat.contains('void _sendReaction('), isTrue);
    expect(module.contains('void _sendReaction('), isFalse);
    expect(module.contains('SocketService.instance.send'), isFalse);
    expect(module.contains('StorageService.'), isFalse);
    expect(module.contains('setState('), isFalse);
  });
}
