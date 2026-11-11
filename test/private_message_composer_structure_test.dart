import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('composer is a separate registered Dart part', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final composer = File('lib/widgets/private_message_composer.dart')
        .readAsStringSync();

    expect(
      chat.contains("part '../widgets/private_message_composer.dart';"),
      isTrue,
    );
    expect(composer.contains("part of '../screens/chat_screen.dart';"), isTrue);
    expect(composer.contains('Widget _buildMessageInput()'), isTrue);
    expect(chat.contains('Widget _buildMessageInput()'), isFalse);
  });

  test('text, voice and attachment controls remain connected', () {
    final composer = File('lib/widgets/private_message_composer.dart')
        .readAsStringSync();

    for (final token in [
      '_sendMessage',
      '_messageController',
      '_handleTextChanged',
      '_togglePrivateVideoNoteMode',
      '_beginHexVideoHold',
      '_moveHexVideoHold',
      '_endHexVideoHold',
      '_handleVoiceLongPressStart',
      '_handleVoiceLongPressMove',
      '_handleVoiceLongPressEnd',
      '_finishVoiceRecording(',
      '_showPrivateAttachmentMenu(',
      '_openComposerEmoji',
      'PrivateVoiceRecordingComposer(',
      'PrivateComposerReplyPreview(',
      'PrivateVoiceRecordButton(',
      'LogicalKeyboardKey.enter',
      'LogicalKeyboardKey.escape',
    ]) {
      expect(composer.contains(token), isTrue, reason: token);
    }
  });

  test('identity and selected language are preserved', () {
    final composer = File('lib/widgets/private_message_composer.dart')
        .readAsStringSync();

    expect(composer.contains('SocketService.instance.currentUser'), isTrue);
    expect(composer.contains('AppLanguageService.instance.code.value'), isTrue);
  });

  test('emoji state is delegated to ChatScreen State', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final composer = File('lib/widgets/private_message_composer.dart')
        .readAsStringSync();

    expect(
      RegExp(r'void\s+_updateComposerState\s*\(\s*VoidCallback\s+update\s*\)')
          .hasMatch(chat),
      isTrue,
    );

    // Check behavior without depending on formatter line wrapping.
    expect(RegExp(r'_updateComposerState\s*\(').hasMatch(composer), isTrue);
    expect(RegExp(r'_emojiVisible\s*=\s*false').hasMatch(composer), isTrue);

    expect(RegExp(r'(?<![\w.])setState\s*\(').hasMatch(composer), isFalse);
    expect(composer.contains('StorageService.'), isFalse);
    expect(composer.contains('SocketService.instance.send'), isFalse);
  });
}
