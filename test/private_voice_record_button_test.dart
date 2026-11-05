import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/private_voice_record_button.dart';

void main() {
  Widget makeButton({
    String tooltip = 'Record voice',
    VoidCallback? onTap,
    GestureLongPressStartCallback? onStart,
    GestureLongPressMoveUpdateCallback? onMove,
    GestureLongPressEndCallback? onEnd,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: PrivateVoiceRecordButton(
            tooltip: tooltip,
            onTap: onTap ?? () {},
            onLongPressStart: onStart ?? (_) {},
            onLongPressMoveUpdate: onMove ?? (_) {},
            onLongPressEnd: onEnd ?? (_) {},
          ),
        ),
      ),
    );
  }

  testWidgets('shows microphone and supplied tooltip', (tester) async {
    await tester.pumpWidget(makeButton(tooltip: 'Записати голосове'));

    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(find.byTooltip('Записати голосове'), findsOneWidget);
  });

  testWidgets('tap invokes recording callback', (tester) async {
    var taps = 0;

    await tester.pumpWidget(makeButton(onTap: () => taps++));

    await tester.tap(find.byIcon(Icons.mic_rounded));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('long press forwards start and end', (tester) async {
    var starts = 0;
    var ends = 0;

    await tester.pumpWidget(
      makeButton(onStart: (_) => starts++, onEnd: (_) => ends++),
    );

    await tester.longPress(find.byIcon(Icons.mic_rounded));
    await tester.pump();

    expect(starts, 1);
    expect(ends, 1);
  });
}
