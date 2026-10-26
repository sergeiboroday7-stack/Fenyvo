import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/call_connection_quality.dart';

void main() {
  test('marks healthy mobile call stats as good', () {
    expect(
      evaluateCallConnectionQuality(
        packetLossPercent: 1.5,
        roundTripTimeMs: 180,
        jitterMs: 24,
      ),
      CallConnectionQuality.good,
    );
  });

  test('marks high loss, latency or jitter as poor', () {
    expect(
      evaluateCallConnectionQuality(packetLossPercent: 9),
      CallConnectionQuality.poor,
    );
    expect(
      evaluateCallConnectionQuality(roundTripTimeMs: 850),
      CallConnectionQuality.poor,
    );
    expect(
      evaluateCallConnectionQuality(jitterMs: 90),
      CallConnectionQuality.poor,
    );
  });

  test('reconnecting takes priority over sampled stats', () {
    expect(
      evaluateCallConnectionQuality(packetLossPercent: 0, reconnecting: true),
      CallConnectionQuality.reconnecting,
    );
  });
}
