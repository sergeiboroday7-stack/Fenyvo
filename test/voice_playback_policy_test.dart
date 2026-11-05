import 'package:flutter_test/flutter_test.dart';
import '../lib/features/messages/domain/voice_playback_policy.dart';

void main() {
  group('VoicePlaybackPolicy', () {
    test('clamps seek fractions', () {
      expect(VoicePlaybackPolicy.clampSeekFraction(-0.5), 0.0);
      expect(VoicePlaybackPolicy.clampSeekFraction(0.5), 0.5);
      expect(VoicePlaybackPolicy.clampSeekFraction(1.5), 1.0);
    });

    test('cycles playback speed', () {
      expect(VoicePlaybackPolicy.nextRate(1.0), 1.5);
      expect(VoicePlaybackPolicy.nextRate(1.5), 2.0);
      expect(VoicePlaybackPolicy.nextRate(2.0), 1.0);
    });

    test('preserves playback speed thresholds', () {
      expect(VoicePlaybackPolicy.nextRate(1.24), 1.5);
      expect(VoicePlaybackPolicy.nextRate(1.25), 2.0);
      expect(VoicePlaybackPolicy.nextRate(1.74), 2.0);
      expect(VoicePlaybackPolicy.nextRate(1.75), 1.0);
    });

    test('calculates and clamps playback progress', () {
      const duration = Duration(seconds: 100);

      expect(
        VoicePlaybackPolicy.progress(
          const Duration(seconds: 50),
          duration,
        ),
        0.5,
      );

      expect(
        VoicePlaybackPolicy.progress(
          const Duration(seconds: 150),
          duration,
        ),
        1.0,
      );

      expect(
        VoicePlaybackPolicy.progress(
          const Duration(seconds: -10),
          duration,
        ),
        0.0,
      );

      expect(
        VoicePlaybackPolicy.progress(Duration.zero, Duration.zero),
        0.0,
      );
    });
  });
}