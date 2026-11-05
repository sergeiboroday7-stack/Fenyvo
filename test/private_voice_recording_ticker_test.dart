import 'package:flutter_test/flutter_test.dart';

import '../lib/features/messages/domain/private_voice_recording_ticker.dart';

void main() {
  testWidgets('emits 250 millisecond increments', (tester) async {
    final ticker = PrivateVoiceRecordingTicker();
    var elapsed = Duration.zero;

    ticker.start(onTick: (delta) => elapsed += delta);

    await tester.pump(const Duration(milliseconds: 750));

    expect(elapsed, const Duration(milliseconds: 750));
    expect(ticker.isRunning, isTrue);

    ticker.dispose();
  });

  testWidgets('stop prevents further duration updates', (tester) async {
    final ticker = PrivateVoiceRecordingTicker();
    var ticks = 0;

    ticker.start(onTick: (_) => ticks++);

    await tester.pump(const Duration(milliseconds: 250));
    expect(ticks, 1);

    ticker.stop();

    await tester.pump(const Duration(seconds: 1));

    expect(ticks, 1);
    expect(ticker.isRunning, isFalse);

    ticker.dispose();
  });

  testWidgets('restart does not leave a second timer running', (tester) async {
    final ticker = PrivateVoiceRecordingTicker();
    var first = 0;
    var second = 0;

    ticker.start(onTick: (_) => first++);

    await tester.pump(const Duration(milliseconds: 250));
    expect(first, 1);

    ticker.start(onTick: (_) => second++);

    await tester.pump(const Duration(milliseconds: 500));

    expect(first, 1);
    expect(second, 2);

    ticker.dispose();
  });
}
