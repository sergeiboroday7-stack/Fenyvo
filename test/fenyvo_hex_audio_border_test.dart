import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/widgets/fenyvo_hex_audio_border.dart';

void main() {
  test('invalid and silent amplitudes normalize to zero', () {
    expect(FenyvoHexAudioLevel.normalize(double.nan), 0);
    expect(FenyvoHexAudioLevel.normalize(-0.5), 0);
    expect(FenyvoHexAudioLevel.normalize(0), 0);
  });

  test('amplitude is clamped to the valid interval', () {
    expect(FenyvoHexAudioLevel.normalize(0.5), 0.5);
    expect(FenyvoHexAudioLevel.normalize(4), 1);
  });

  test('silence does not generate artificial glow', () {
    expect(FenyvoHexAudioLevel.glow(0), 0);
    expect(FenyvoHexAudioLevel.glow(0.01), 0);
  });

  test('actual louder sound increases glow', () {
    final quiet = FenyvoHexAudioLevel.glow(0.04);
    final loud = FenyvoHexAudioLevel.glow(0.64);
    expect(quiet, greaterThan(0));
    expect(loud, greaterThan(quiet));
  });

  test('amplitude rises quickly and falls smoothly', () {
    final attack = FenyvoHexAudioLevel.smooth(0, 1);
    final release = FenyvoHexAudioLevel.smooth(attack, 0);
    expect(attack, greaterThan(0.5));
    expect(release, greaterThan(0));
    expect(release, lessThan(attack));
  });
}
