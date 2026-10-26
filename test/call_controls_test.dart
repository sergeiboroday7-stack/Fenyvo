import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/widgets/call_controls.dart';

void main() {
  Widget controls({
    bool microphone = true,
    bool camera = true,
    bool video = true,
    bool switchCamera = true,
    double scale = 1,
    VoidCallback? onMicrophone,
    VoidCallback? onCamera,
    VoidCallback? onSwitchCamera,
    VoidCallback? onHangUp,
    VoidCallback? onSpeakerphone,
    bool speakerphone = false,
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: CallControls(
              microphoneEnabled: microphone,
              cameraEnabled: camera,
              isVideo: video,
              canSwitchCamera: switchCamera,
              onMicrophone: onMicrophone ?? () {},
              onCamera: onCamera ?? () {},
              onSwitchCamera: onSwitchCamera ?? () {},
              onHangUp: onHangUp ?? () {},
              onSpeakerphone: onSpeakerphone,
              speakerphoneEnabled: speakerphone,
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets('enabled devices have explicit states and action tooltips', (
    tester,
  ) async {
    await tester.pumpWidget(controls());
    expect(find.text('Включён'), findsOneWidget);
    expect(find.text('Включена'), findsOneWidget);
    expect(find.byTooltip('Выключить микрофон'), findsOneWidget);
    expect(find.byTooltip('Выключить камеру'), findsOneWidget);
    expect(find.text('Без звука'), findsNothing);
  });

  testWidgets('speaker button exposes route and only changes audio output', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      controls(video: false, onSpeakerphone: () => taps++),
    );
    await tester.tap(find.byTooltip('Включить громкую связь'));
    expect(taps, 1);
    expect(find.byIcon(Icons.hearing_rounded), findsOneWidget);
    await tester.pumpWidget(
      controls(video: false, speakerphone: true, onSpeakerphone: () => taps++),
    );
    expect(find.byTooltip('Выключить громкую связь'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_rounded), findsOneWidget);
  });

  testWidgets('five mobile video controls fit the narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(controls(onSpeakerphone: () {}));
    expect(find.byType(CallActionButton), findsNWidgets(5));
    expect(tester.takeException(), isNull);
    for (final action in find.byType(CallActionButton).evaluate()) {
      final rect = tester.getRect(find.byWidget(action.widget));
      expect(rect.left, greaterThanOrEqualTo(20));
      expect(rect.right, lessThanOrEqualTo(300));
      expect(rect.top, greaterThanOrEqualTo(0));
    }
  });

  testWidgets('disabled devices change color, icon, state and next action', (
    tester,
  ) async {
    await tester.pumpWidget(controls(microphone: false, camera: false));
    expect(find.text('Выключен'), findsOneWidget);
    expect(find.text('Выключена'), findsOneWidget);
    expect(find.byIcon(Icons.mic_off_rounded), findsOneWidget);
    expect(find.byIcon(Icons.videocam_off_rounded), findsOneWidget);
    expect(find.byTooltip('Включить микрофон'), findsOneWidget);
    expect(find.byTooltip('Включить камеру'), findsOneWidget);
    for (final name in ['microphone', 'camera']) {
      final circle = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byKey(ValueKey('call-$name-action')),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect(
        (circle.decoration! as BoxDecoration).color,
        const Color(0xFFD4AF37),
      );
    }
    await tester.pumpWidget(controls());
    await tester.pumpAndSettle();
    expect(find.text('Выключен'), findsNothing);
    expect(find.text('Включён'), findsOneWidget);
    final circle = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byKey(const ValueKey('call-microphone-action')),
        matching: find.byType(AnimatedContainer),
      ),
    );
    expect(
      (circle.decoration! as BoxDecoration).color,
      const Color(0xFF292929),
    );
  });

  testWidgets('labels and icons each invoke only their own action once', (
    tester,
  ) async {
    final counts = [0, 0, 0, 0];
    await tester.pumpWidget(
      controls(
        onMicrophone: () => counts[0]++,
        onCamera: () => counts[1]++,
        onSwitchCamera: () => counts[2]++,
        onHangUp: () => counts[3]++,
      ),
    );
    await tester.tap(find.text('Микрофон'));
    await tester.tap(find.byIcon(Icons.videocam_rounded));
    await tester.tap(find.text('Сменить\nкамеру'));
    await tester.tap(find.text('Завершить'));
    expect(counts, [1, 1, 1, 1]);
  });

  testWidgets('audio has no camera controls and desktop has no camera switch', (
    tester,
  ) async {
    await tester.pumpWidget(controls(video: false));
    expect(find.byType(CallActionButton), findsNWidgets(2));
    expect(find.byKey(const ValueKey('call-camera-action')), findsNothing);
    await tester.pumpWidget(controls(switchCamera: false));
    expect(find.byType(CallActionButton), findsNWidgets(3));
    expect(
      find.byKey(const ValueKey('call-switch-camera-action')),
      findsNothing,
    );
  });

  for (final width in [320.0, 390.0, 1280.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('controls fit width $width and text scale $scale', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 820);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          controls(scale: scale, microphone: false, camera: false),
        );
        expect(tester.takeException(), isNull);
        for (final action in find.byType(CallActionButton).evaluate()) {
          final rect = tester.getRect(find.byWidget(action.widget));
          expect(rect.left, greaterThanOrEqualTo(20));
          expect(rect.right, lessThanOrEqualTo(width - 19.9));
          expect(rect.top, greaterThanOrEqualTo(0));
          expect(rect.bottom, lessThanOrEqualTo(820));
        }
        if (width == 320 && scale == 1) {
          final mic = tester.getTopLeft(
            find.byKey(const ValueKey('call-microphone-action')),
          );
          final camera = tester.getTopLeft(
            find.byKey(const ValueKey('call-camera-action')),
          );
          final flip = tester.getTopLeft(
            find.byKey(const ValueKey('call-switch-camera-action')),
          );
          final end = tester.getTopLeft(
            find.byKey(const ValueKey('call-hang-up-action')),
          );
          expect(mic.dy, camera.dy);
          expect(flip.dy, end.dy);
          expect(flip.dy, greaterThan(mic.dy));
        }
      });
    }
  }

  testWidgets('keyboard can focus and activate a control', (tester) async {
    var presses = 0;
    await tester.pumpWidget(controls(onMicrophone: () => presses++));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(presses, 1);
  });

  testWidgets(
    'screen reader receives state and action without duplicate labels',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(controls(microphone: false));
      expect(find.bySemanticsLabel('Микрофон'), findsOneWidget);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Микрофон')),
        matchesSemantics(
          label: 'Микрофон',
          value: 'Выключен',
          isButton: true,
          hasToggledState: true,
          isToggled: false,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    },
  );
}
