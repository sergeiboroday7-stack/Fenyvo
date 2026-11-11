import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy plaintext private edit is rejected before mutation', () {
    final source =
        File('lib/screens/chat_screen.dart').readAsStringSync();

    final start = source.indexOf(
      "if (type == 'message_edited') {",
    );
    final end = source.indexOf(
      "if (type == 'message_deleted') {",
      start,
    );

    expect(start, greaterThanOrEqualTo(0));
    expect(end, greaterThan(start));

    final handler = source.substring(start, end);

    expect(handler, contains('legacy private edits carry plaintext'));
    expect(handler, contains('return;'));
    expect(handler, isNot(contains("data['newText']")));
    expect(handler, isNot(contains('mutateMessagesDurably')));
    expect(handler, isNot(contains("message['text'] =")));
    expect(handler, isNot(contains("stored['text'] =")));
  });
}