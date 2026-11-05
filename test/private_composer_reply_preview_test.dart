import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/private_composer_reply_preview.dart';

void main() {
  Widget preview({
    Map<String, dynamic>? reply,
    String currentUser = 'me',
    String language = 'ru',
    VoidCallback? onCancel,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PrivateComposerReplyPreview(
          replyMessage: reply,
          currentUser: currentUser,
          languageCode: language,
          onCancel: onCancel ?? () {},
        ),
      ),
    );
  }

  testWidgets('empty reply does not display preview', (tester) async {
    await tester.pumpWidget(preview());

    expect(find.byIcon(Icons.close_rounded), findsNothing);
  });

  testWidgets('shows replied message and cancel action', (tester) async {
    var cancels = 0;

    await tester.pumpWidget(
      preview(
        reply: {'from': 'Anna', 'text': 'Hello'},
        onCancel: () => cancels++,
      ),
    );

    expect(find.text('Anna'), findsOneWidget);
    expect(find.text('Hello'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();

    expect(cancels, 1);
  });

  testWidgets('localizes own author RU UK EN', (tester) async {
    const labels = {'ru': 'Вы', 'uk': 'Ви', 'en': 'You'};

    for (final entry in labels.entries) {
      await tester.pumpWidget(
        preview(reply: {'from': 'me', 'text': 'Message'}, language: entry.key),
      );

      expect(find.text(entry.value), findsOneWidget);
    }
  });

  testWidgets('localizes missing author RU UK EN', (tester) async {
    const labels = {'ru': 'Ответ', 'uk': 'Відповідь', 'en': 'Reply'};

    for (final entry in labels.entries) {
      await tester.pumpWidget(
        preview(reply: {'from': '', 'text': 'Message'}, language: entry.key),
      );

      expect(find.text(entry.value), findsOneWidget);
    }
  });
}
