import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/private_voice_message_player.dart';

void main() {
  Widget makePlayer({
    String? selected,
    bool playing = false,
    double rate = 1.0,
    Future<void> Function()? onToggle,
    Future<void> Function(double)? onSeek,
    Future<void> Function()? onCycle,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: PrivateVoiceMessagePlayer(
            message: const {'voiceDurationMs': 65000},
            isMe: false,
            messageId: 'voice-1',
            playingVoiceMessageId: selected,
            playbackPosition: const Duration(seconds: 10),
            playbackDuration: const Duration(seconds: 65),
            playbackRate: rate,
            isPlaying: playing,
            gold: Colors.amber,
            onToggle: onToggle ?? () async {},
            onSeek: onSeek ?? (_) async {},
            onCycleRate: onCycle ?? () async {},
          ),
        ),
      ),
    );
  }

  testWidgets('shows paused message and duration', (tester) async {
    await tester.pumpWidget(makePlayer());

    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('0:00 / 1:05'), findsOneWidget);
    expect(find.text('1x'), findsOneWidget);
  });

  testWidgets('shows selected playing state', (tester) async {
    await tester.pumpWidget(
      makePlayer(selected: 'voice-1', playing: true, rate: 1.5),
    );

    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(find.text('0:10 / 1:05'), findsOneWidget);
    expect(find.text('1.5x'), findsOneWidget);
  });

  testWidgets('forwards play and speed actions', (tester) async {
    var toggles = 0;
    var rateChanges = 0;

    await tester.pumpWidget(
      makePlayer(
        onToggle: () async {
          toggles++;
        },
        onCycle: () async {
          rateChanges++;
        },
      ),
    );

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await tester.pump();

    await tester.tap(find.text('1x'));
    await tester.pump();

    expect(toggles, 1);
    expect(rateChanges, 1);
  });

  testWidgets('forwards seek gestures', (tester) async {
    double? seekFraction;

    await tester.pumpWidget(
      makePlayer(
        onSeek: (fraction) async {
          seekFraction = fraction;
        },
      ),
    );

    final waveform = find.byType(LayoutBuilder);
    expect(waveform, findsOneWidget);

    await tester.tapAt(tester.getCenter(waveform));
    await tester.pump();

    expect(seekFraction, isNotNull);
    expect(seekFraction!, closeTo(0.5, 0.1));
  });
}
