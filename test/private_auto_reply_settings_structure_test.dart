import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
  final part = File('lib/widgets/private_auto_reply_settings.dart')
      .readAsStringSync();

  test('auto reply settings extracted with State bridge', () {
    expect(
      chat.contains("part '../widgets/private_auto_reply_settings.dart';"),
      isTrue,
    );
    expect(part.contains("part of '../screens/chat_screen.dart';"), isTrue);
    expect(
      part.contains('Future<void> _showAutoReplySettings() async'),
      isTrue,
    );
    expect(
      chat.contains('Future<void> _showAutoReplySettings() async'),
      isFalse,
    );
    expect(
      chat.contains('void _autoReplyApplyState(VoidCallback update)'),
      isTrue,
    );
    expect(RegExp(r'_autoReplyApplyState\s*\(').allMatches(part).length, 2);
  });

  test('all nine user settings and server operations survive', () {
    for (final field in [
      '_autoReplyBoundaries',
      '_autoReplyContext',
      '_autoReplyDelaySeconds',
      '_autoReplyEnabled',
      '_autoReplyGoal',
      '_autoReplyIdleSeconds',
      '_autoReplyLoading',
      '_autoReplyMode',
      '_autoReplyPrompt',
    ]) {
      expect(part.contains(field), isTrue, reason: field);
    }

    expect(
      RegExp(r'SocketService\.instance\.setAutoReplySettings\s*\(')
          .allMatches(part)
          .length,
      2,
    );
    expect(
      RegExp(r'SocketService\.instance\.clearAutoReplyHistory\s*\(')
          .allMatches(part)
          .length,
      1,
    );
  });

  test('localization, colors and controller cleanup remain', () {
    expect(RegExp(r'_chatText\s*\(').allMatches(part).length, 37);
    expect(RegExp(r'_ChatScreenState\._gold\b').allMatches(part).length, 12);

    for (final name in [
      'goalController',
      'promptController',
      'contextController',
      'boundariesController',
    ]) {
      expect(part.contains('$name.dispose()'), isTrue);
    }
  });
}
