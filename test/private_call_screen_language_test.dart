import 'package:fenyvo/screens/call_screen.dart';
import 'package:fenyvo/services/app_language_service.dart';
import 'package:fenyvo/services/call_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final language = AppLanguageService.instance;
  final service = CallService.instance;

  late String previousCode;

  setUp(() async {
    previousCode = language.code.value;
    await service.hangUp();
  });

  tearDown(() async {
    await service.hangUp();
    language.code.value = previousCode;
  });

  testWidgets('Ukrainian incoming audio call UI', (tester) async {
    language.code.value = 'uk';

    service.phase = CallPhase.incoming;
    service.callId = 'uk-incoming-language-test';
    service.peerUser = 'Test peer';
    service.isVideo = false;
    service.isIncoming = true;
    service.statusText = 'Входящий аудиозвонок';

    await tester.pumpWidget(const MaterialApp(home: CallScreen()));

    expect(find.text('Вхідний аудіодзвінок'), findsOneWidget);
    expect(find.text('Прийняти'), findsOneWidget);
    expect(find.text('Відхилити'), findsOneWidget);
    expect(find.byTooltip('Прийняти аудіодзвінок'), findsOneWidget);
    expect(find.byTooltip('Відхилити дзвінок'), findsOneWidget);

    expect(find.text('Входящий аудиозвонок'), findsNothing);
    expect(find.text('Принять'), findsNothing);
    expect(find.text('Отклонить'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('English incoming video call UI', (tester) async {
    language.code.value = 'en';

    service.phase = CallPhase.incoming;
    service.callId = 'en-incoming-language-test';
    service.peerUser = 'Test peer';
    service.isVideo = true;
    service.isIncoming = true;
    service.statusText = 'Входящий видеозвонок';

    await tester.pumpWidget(const MaterialApp(home: CallScreen()));

    expect(find.text('Incoming video call'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    expect(find.byTooltip('Accept video call'), findsOneWidget);
    expect(find.byTooltip('Decline call'), findsOneWidget);

    expect(find.text('Входящий видеозвонок'), findsNothing);
    expect(find.text('Принять'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Ukrainian outgoing call status and hang-up', (tester) async {
    language.code.value = 'uk';

    service.phase = CallPhase.outgoing;
    service.callId = 'uk-outgoing-language-test';
    service.peerUser = 'Test peer';
    service.isVideo = false;
    service.isIncoming = false;
    service.statusText = 'Ожидание ответа…';

    await tester.pumpWidget(const MaterialApp(home: CallScreen()));

    expect(find.text('Очікування відповіді…'), findsOneWidget);
    expect(find.text('Завершити'), findsOneWidget);
    expect(find.byTooltip('Завершити дзвінок'), findsOneWidget);
    expect(find.text('Ожидание ответа…'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('English outgoing call status and hang-up', (tester) async {
    language.code.value = 'en';

    service.phase = CallPhase.outgoing;
    service.callId = 'en-outgoing-language-test';
    service.peerUser = 'Test peer';
    service.isVideo = false;
    service.isIncoming = false;
    service.statusText = 'Ожидание ответа…';

    await tester.pumpWidget(const MaterialApp(home: CallScreen()));

    expect(find.text('Waiting for an answer…'), findsOneWidget);
    expect(find.text('End call'), findsOneWidget);
    expect(find.byTooltip('End the call'), findsOneWidget);
    expect(find.text('Ожидание ответа…'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
