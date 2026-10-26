import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('mobile dock text scaling diagnostics', (tester) async {
    const screenWidth = 360.0;
    const outerPadding = 28.0;
    const innerPadding = 12.0;
    const commandWidth = 76.0;

    const availableWidth =
        screenWidth - outerPadding - innerPadding - commandWidth;
    const labelWidth = availableWidth / 4;

    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final scale in [1.0, 1.5, 2.0]) {
      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(
              size: const Size(360, 800),
              textScaler: TextScaler.linear(scale),
            ),
            child: const Scaffold(
              body: Center(child: Text('Scaling diagnostics')),
            ),
          ),
        ),
      );

      for (final label in [
        'Чаты',
        'Контакты',
        'Звонки',
        'Настройки',
      ]) {
        final painter = TextPainter(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: .8,
            ),
          ),
          textDirection: TextDirection.ltr,
          textScaler: TextScaler.linear(scale),
        );

        painter.layout(maxWidth: labelWidth);

        final lines = painter.computeLineMetrics().length;

        // ignore: avoid_print
        print(
          'SCALE=$scale LABEL=$label '
          'WIDTH=${labelWidth.toStringAsFixed(1)} '
          'LINES=$lines',
        );

        expect(lines, greaterThanOrEqualTo(1));
        painter.dispose();
      }
    }
  });
}