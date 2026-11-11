import 'package:shared_preferences/shared_preferences.dart';

/// Persistent playback speed for short HEX video messages only.
///
/// Ordinary video attachments and voice messages do not use this setting.
class PrivateVideoNoteSpeedSettings {
  PrivateVideoNoteSpeedSettings._();

  static const String preferenceKey =
      'fenyvo.private_video_note.playback_speed';

  static const List<double> supportedSpeeds = <double>[1.0, 1.5, 2.0, 3.0];

  static double normalize(double speed) {
    return supportedSpeeds.contains(speed) ? speed : 1.0;
  }

  static Future<double> load() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.get(preferenceKey);

    if (value is num) {
      return normalize(value.toDouble());
    }

    return 1.0;
  }

  static Future<bool> save(double speed) async {
    if (!supportedSpeeds.contains(speed)) {
      return false;
    }

    final preferences = await SharedPreferences.getInstance();
    return preferences.setDouble(preferenceKey, speed);
  }

  static String label(double speed) {
    final valid = normalize(speed);
    return valid == valid.roundToDouble() ? '${valid.toInt()}x' : '${valid}x';
  }
}
