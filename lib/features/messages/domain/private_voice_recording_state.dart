/// Mutable state for the active private voice recording.
///
/// This class does not own the microphone, temporary files,
/// UI notifications, message sending or encryption.
class PrivateVoiceRecordingState {
  bool pressActive = false;
  bool starting = false;
  bool isRecording = false;
  bool locked = false;
  Duration duration = Duration.zero;
  String? recordingPath;

  /// Clears the visible recording session after the stop action begins.
  ///
  /// Pending startup, pointer state, microphone and temporary files
  /// have separate owners and are intentionally not reset here.
  void resetAfterFinish() {
    isRecording = false;
    locked = false;
    duration = Duration.zero;
    recordingPath = null;
  }

  void clearRecording() {
    pressActive = false;
    starting = false;
    isRecording = false;
    locked = false;
    duration = Duration.zero;
    recordingPath = null;
  }
}
