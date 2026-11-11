import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('translation UI is extracted into a library part', () {
    final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
    final part = File('lib/widgets/private_translation_sheet.dart')
        .readAsStringSync();

    expect(
      chat.contains("part '../widgets/private_translation_sheet.dart';"),
      isTrue,
    );
    expect(part.contains("part of '../screens/chat_screen.dart';"), isTrue);
    expect(
      part.contains(
        'Future<void> _translateMessage(Map<String, dynamic> message)',
      ),
      isTrue,
    );
    expect(
      chat.contains(
        'Future<void> _translateMessage(Map<String, dynamic> message)',
      ),
      isFalse,
    );
  });

  test('translation retains both E2EE guards and qualified static color', () {
    final part = File('lib/widgets/private_translation_sheet.dart')
        .readAsStringSync();

    expect(
      RegExp(r'PrivateExternalTextPolicy\.canSendMessage\s*\(')
          .allMatches(part)
          .length,
      2,
    );

    expect(
      RegExp(r'_ChatScreenState\._gold\b').allMatches(part).length,
      greaterThanOrEqualTo(10),
    );

    expect(part.contains('SocketService.instance.isE2eeActiveWith('), isTrue);
    expect(part.contains('_requestTranslation('), isTrue);
  });
}
