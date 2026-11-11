import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reaction row and picker are extracted', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final module = File('lib/widgets/private_reaction_widgets.dart')
        .readAsStringSync();

    expect(module.contains('Widget _buildReactionRow('), isTrue);
    expect(module.contains('Future<void> _showReactionPicker('), isTrue);
    expect(chat.contains('Widget _buildReactionRow('), isFalse);
    expect(chat.contains('Future<void> _showReactionPicker('), isFalse);
  });

  test('reaction sending stays in main ChatScreen', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final module = File('lib/widgets/private_reaction_widgets.dart')
        .readAsStringSync();

    expect(chat.contains('void _sendReaction('), isTrue);
    expect(chat.contains('void _showReactionBurst('), isTrue);
    expect(module.contains('void _sendReaction('), isFalse);
    expect(module.contains('setState('), isFalse);
  });

  test('reaction UI retains selection and current-user checks', () {
    final module = File('lib/widgets/private_reaction_widgets.dart')
        .readAsStringSync();

    expect(module.contains('_getMessageReactions(message)'), isTrue);
    expect(module.contains('SocketService.instance.currentUser'), isTrue);
    expect(module.contains('_sendReaction(message, reaction)'), isTrue);
    expect(module.contains('StorageService.'), isFalse);
  });
}
