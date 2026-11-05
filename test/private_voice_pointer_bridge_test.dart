import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/widgets/private_voice_pointer_bridge.dart';

void main() {
  Widget buildBridge({
    required bool enabled,
    required ValueChanged<Offset> onMove,
    required VoidCallback onUp,
    required VoidCallback onCancel,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PrivateVoicePointerBridge(
          enabled: enabled,
          onMove: onMove,
          onPointerUp: onUp,
          onPointerCancel: onCancel,
          child: const SizedBox(
            width: 150,
            height: 100,
            child: ColoredBox(
              color: Colors.blue,
              child: Center(child: Text('Recorder')),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('disabled bridge preserves its child', (tester) async {
    await tester.pumpWidget(
      buildBridge(enabled: false, onMove: (_) {}, onUp: () {}, onCancel: () {}),
    );

    expect(find.text('Recorder'), findsOneWidget);

    final bridge = tester.widget<PrivateVoicePointerBridge>(
      find.byType(PrivateVoicePointerBridge),
    );

    expect(bridge.enabled, isFalse);
  });

  testWidgets('enabled bridge forwards move and pointer up', (tester) async {
    Offset? position;
    var releases = 0;

    await tester.pumpWidget(
      buildBridge(
        enabled: true,
        onMove: (value) => position = value,
        onUp: () => releases++,
        onCancel: () {},
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Recorder')),
    );

    await gesture.moveBy(const Offset(15, 8));
    await tester.pump();

    expect(position, isNotNull);

    await gesture.up();
    await tester.pump();

    expect(releases, 1);
  });

  testWidgets('enabled bridge forwards pointer cancel', (tester) async {
    var cancels = 0;

    await tester.pumpWidget(
      buildBridge(
        enabled: true,
        onMove: (_) {},
        onUp: () {},
        onCancel: () => cancels++,
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Recorder')),
    );

    await gesture.cancel();
    await tester.pump();

    expect(cancels, 1);
  });
}
