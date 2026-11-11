import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fenyvo/features/messages/data/private_video_note_speed_settings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('defaults to normal speed', () async {
    expect(await PrivateVideoNoteSpeedSettings.load(), 1.0);
  });

  test('supports the four agreed speeds', () {
    expect(PrivateVideoNoteSpeedSettings.supportedSpeeds, <double>[
      1.0,
      1.5,
      2.0,
      3.0,
    ]);
  });

  test('persists chosen speed between reads', () async {
    expect(await PrivateVideoNoteSpeedSettings.save(2.0), isTrue);
    expect(await PrivateVideoNoteSpeedSettings.load(), 2.0);

    expect(await PrivateVideoNoteSpeedSettings.save(1.5), isTrue);
    expect(await PrivateVideoNoteSpeedSettings.load(), 1.5);
  });

  test('rejects unsupported speeds', () async {
    expect(await PrivateVideoNoteSpeedSettings.save(2.0), isTrue);
    expect(await PrivateVideoNoteSpeedSettings.save(4.0), isFalse);
    expect(await PrivateVideoNoteSpeedSettings.load(), 2.0);
  });

  test('recovers safely from an invalid saved speed', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      PrivateVideoNoteSpeedSettings.preferenceKey: 9.0,
    });

    expect(await PrivateVideoNoteSpeedSettings.load(), 1.0);
  });

  test('provides compact speed labels', () {
    expect(PrivateVideoNoteSpeedSettings.label(1.0), '1x');
    expect(PrivateVideoNoteSpeedSettings.label(1.5), '1.5x');
    expect(PrivateVideoNoteSpeedSettings.label(2.0), '2x');
    expect(PrivateVideoNoteSpeedSettings.label(3.0), '3x');
  });
}
