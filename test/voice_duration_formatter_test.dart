import 'package:flutter_test/flutter_test.dart';
import '../lib/features/messages/domain/voice_duration_formatter.dart';

void main() {
  group('VoiceDurationFormatter', () {
    test('formats normal durations', () {
      expect(
        VoiceDurationFormatter.format(const Duration(seconds: 0)),
        '0:00',
      );
      expect(
        VoiceDurationFormatter.format(const Duration(seconds: 9)),
        '0:09',
      );
      expect(
        VoiceDurationFormatter.format(const Duration(seconds: 65)),
        '1:05',
      );
    });

    test('preserves duration boundaries', () {
      expect(
        VoiceDurationFormatter.format(const Duration(seconds: -5)),
        '0:00',
      );
      expect(
        VoiceDurationFormatter.format(const Duration(seconds: 360000)),
        '5999:59',
      );
    });

    test('reads integer, decimal and string durations', () {
      expect(
        VoiceDurationFormatter.milliseconds({'voiceDurationMs': 1234}),
        1234,
      );
      expect(
        VoiceDurationFormatter.milliseconds({'voiceDurationMs': 1250.9}),
        1250,
      );
      expect(
        VoiceDurationFormatter.milliseconds({'voiceDurationMs': '1450'}),
        1450,
      );
    });

    test('preserves invalid and negative stored values', () {
      expect(VoiceDurationFormatter.milliseconds({}), 0);
      expect(
        VoiceDurationFormatter.milliseconds({'voiceDurationMs': 'wrong'}),
        0,
      );
      expect(
        VoiceDurationFormatter.milliseconds({'voiceDurationMs': -200}),
        -200,
      );
    });
  });
}