import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/features/messages/data/hex_video_audio_levels.dart';

void main() {
  test('empty envelope remains silent', () {
    expect(
      HexVideoAudioLevels.atPosition(const [], const Duration(seconds: 2)),
      0,
    );
  });

  test('selects levels using video playback position', () {
    final levels = [0.01, 0.1, 0.7, 0.2];
    expect(
      HexVideoAudioLevels.atPosition(levels, const Duration(milliseconds: 250)),
      0.7,
    );
  });

  test('out-of-range position is silent', () {
    expect(
      HexVideoAudioLevels.atPosition([0.2], const Duration(seconds: 4)),
      0,
    );
  });
}
