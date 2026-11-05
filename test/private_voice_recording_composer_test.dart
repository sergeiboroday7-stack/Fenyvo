import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/private_voice_recording_composer.dart';

void main() {
  Widget makeComposer({
    Duration duration = const Duration(seconds: 5),
    Future<void> Function()? onCancel,
    Future<void> Function()? onSend,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PrivateVoiceRecordingComposer(
          replyPreview: const Text('Reply preview'),
          duration: duration,
          onCancel: onCancel ?? () async {},
          onSend: onSend ?? () async {},
        ),
      ),
    );
  }

  testWidgets('shows duration and preserves reply preview', (tester) async {
    await tester.pumpWidget(makeComposer());

    expect(find.text('Reply preview'), findsOneWidget);
    expect(find.text('0:05'), findsOneWidget);
  });

  testWidgets('displays the recording waveform', (tester) async {
    await tester.pumpWidget(makeComposer());

    expect(find.byType(AnimatedContainer), findsNWidgets(18));
    expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
    expect(find.byIcon(Icons.send_rounded), findsOneWidget);
  });

  testWidgets('cancel and send invoke separate callbacks', (tester) async {
    var cancelled = 0;
    var sent = 0;

    await tester.pumpWidget(
      makeComposer(
        onCancel: () async {
          cancelled++;
        },
        onSend: () async {
          sent++;
        },
      ),
    );

    await tester.tap(find.byIcon(Icons.delete_outline_rounded));
    await tester.pump();
    expect(cancelled, 1);
    expect(sent, 0);

    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pump();
    expect(cancelled, 1);
    expect(sent, 1);
  });

  testWidgets('rebuilds with updated recording duration', (tester) async {
    await tester.pumpWidget(makeComposer(duration: const Duration(seconds: 9)));
    expect(find.text('0:09'), findsOneWidget);

    await tester.pumpWidget(
      makeComposer(duration: const Duration(seconds: 65)),
    );
    expect(find.text('1:05'), findsOneWidget);
  });

  testWidgets('Ukrainian recorder actions use Ukrainian tooltips', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrivateVoiceRecordingComposer(
            replyPreview: const SizedBox.shrink(),
            duration: const Duration(seconds: 3),
            languageCode: 'uk',
            onCancel: () async {},
            onSend: () async {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Скасувати'), findsOneWidget);
    expect(find.byTooltip('Надіслати'), findsOneWidget);
  });

  testWidgets('English recorder actions use English tooltips', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PrivateVoiceRecordingComposer(
            replyPreview: const SizedBox.shrink(),
            duration: const Duration(seconds: 3),
            languageCode: 'en',
            onCancel: () async {},
            onSend: () async {},
          ),
        ),
      ),
    );

    expect(find.byTooltip('Cancel'), findsOneWidget);
    expect(find.byTooltip('Send'), findsOneWidget);
  });
}
