import 'package:fenyvo/services/app_language_service.dart';
import 'package:fenyvo/widgets/call_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final language = AppLanguageService.instance;
  late String previousCode;

  setUp(() {
    previousCode = language.code.value;
  });

  tearDown(() {
    language.code.value = previousCode;
  });

  Widget screen() => MaterialApp(
    home: Scaffold(
      body: CallControls(
        microphoneEnabled: true,
        cameraEnabled: true,
        isVideo: true,
        canSwitchCamera: true,
        onMicrophone: () {},
        onCamera: () {},
        onSwitchCamera: () {},
        onHangUp: () {},
      ),
    ),
  );

  testWidgets('Ukrainian controls and accessibility tooltips', (tester) async {
    language.code.value = 'uk';

    await tester.pumpWidget(screen());

    expect(find.text('Мікрофон'), findsOneWidget);
    expect(find.text('Увімкнений'), findsOneWidget);
    expect(find.text('Камера'), findsOneWidget);
    expect(find.text('Увімкнена'), findsOneWidget);
    expect(find.text('Змінити\nкамеру'), findsOneWidget);
    expect(find.text('Завершити'), findsOneWidget);
    expect(find.byTooltip('Вимкнути мікрофон'), findsOneWidget);
    expect(find.byTooltip('Вимкнути камеру'), findsOneWidget);
    expect(find.byTooltip('Завершити дзвінок'), findsOneWidget);
    expect(find.text('Микрофон'), findsNothing);
  });

  testWidgets('English controls and accessibility tooltips', (tester) async {
    language.code.value = 'en';

    await tester.pumpWidget(screen());

    expect(find.text('Microphone'), findsOneWidget);
    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Switch\ncamera'), findsOneWidget);
    expect(find.text('End call'), findsOneWidget);
    expect(find.byTooltip('Mute microphone'), findsOneWidget);
    expect(find.byTooltip('Turn camera off'), findsOneWidget);
    expect(find.byTooltip('End the call'), findsOneWidget);
    expect(find.text('Микрофон'), findsNothing);
  });
}
