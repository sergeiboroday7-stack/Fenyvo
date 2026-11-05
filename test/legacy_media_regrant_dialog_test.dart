import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/services/legacy_media_regrant_result.dart';
import '../lib/widgets/legacy_media_regrant_dialog.dart';

void main() {
  Widget host({
    required String language,
    required LegacyRegrantConfirm confirm,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => LegacyMediaRegrantDialog(
                recipient: 'bob',
                languageCode: language,
                onConfirm: confirm,
              ),
            ),
            child: const Text('OPEN'),
          ),
        ),
      ),
    );
  }

  testWidgets('no access request is sent when dialog is cancelled',
      (tester) async {
    var requests = 0;
    await tester.pumpWidget(host(
      language: 'ru',
      confirm: () async {
        requests++;
        return const LegacyMediaRegrantResult(
          approved: true,
          reason: '',
        );
      },
    ));

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Получатель: bob'), findsOneWidget);

    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();
    expect(requests, 0);
  });

  testWidgets('explicit confirmation sends only once and waits',
      (tester) async {
    var requests = 0;
    final completer = Completer<LegacyMediaRegrantResult>();

    await tester.pumpWidget(host(
      language: 'en',
      confirm: () {
        requests++;
        return completer.future;
      },
    ));

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('regrant-confirm')));
    await tester.pump();
    expect(requests, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const Key('regrant-confirm')), findsNothing);

    completer.complete(const LegacyMediaRegrantResult(
      approved: true,
      reason: '',
    ));
    await tester.pumpAndSettle();
    expect(find.text('File access granted.'), findsOneWidget);
  });

  testWidgets('server refusal displays Ukrainian explanation',
      (tester) async {
    await tester.pumpWidget(host(
      language: 'uk',
      confirm: () async => const LegacyMediaRegrantResult(
        approved: false,
        reason: 'RECIPIENT_NOT_ELIGIBLE',
      ),
    ));

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    expect(find.text('Надати доступ до файлу?'), findsOneWidget);

    await tester.tap(find.byKey(const Key('regrant-confirm')));
    await tester.pumpAndSettle();
    expect(find.textContaining('підтвердженим контактом'), findsOneWidget);
  });

  testWidgets('callback failure does not show success',
      (tester) async {
    await tester.pumpWidget(host(
      language: 'ru',
      confirm: () async => throw StateError('failure'),
    ));

    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('regrant-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Доступ к файлу предоставлен.'), findsNothing);
    expect(find.byKey(const Key('regrant-result')), findsOneWidget);
  });
}