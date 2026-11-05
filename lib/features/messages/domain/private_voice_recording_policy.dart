/// Pure validation rules for private voice message recording.
///
/// No camera, recorder, socket, storage or cryptography dependencies.
class PrivateVoiceRecordingPolicy {
  const PrivateVoiceRecordingPolicy._();

  static const Duration minimumDuration = Duration(milliseconds: 650);
  static const Duration maximumDuration = Duration(minutes: 5);
  static const int maximumFileBytes = 20 * 1024 * 1024;

  static bool shouldAutoFinish(Duration elapsed) {
    return elapsed >= maximumDuration;
  }

  static bool shouldDiscard({required bool send, required Duration duration}) {
    return !send || duration < minimumDuration;
  }

  static bool isTooLarge(int fileSize) {
    return fileSize > maximumFileBytes;
  }
}
