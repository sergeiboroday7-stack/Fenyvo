/// Duration helpers for existing private voice messages.
class VoiceDurationFormatter {
  static String format(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 359999);
    final minutes = seconds ~/ 60;
    final rest = seconds % 60;

    return '${minutes.toString().padLeft(1, '0')}:'
        '${rest.toString().padLeft(2, '0')}';
  }

  static int milliseconds(Map<String, dynamic> message) {
    final raw = message['voiceDurationMs'];

    if (raw is int) {
      return raw;
    }

    if (raw is num) {
      return raw.toInt();
    }

    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }
}