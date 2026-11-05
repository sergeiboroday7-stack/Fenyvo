/// Pure gesture thresholds for private voice recordings.
///
/// No Flutter widget, microphone, storage, socket or E2EE dependencies.
class PrivateVoiceRecordingGesturePolicy {
  const PrivateVoiceRecordingGesturePolicy._();

  static const double cancelDistance = 105;
  static const double lockDistance = 90;

  /// A leftward movement of at least 105 logical pixels cancels.
  static bool shouldCancel(double horizontalDelta) {
    return horizontalDelta <= -cancelDistance;
  }

  /// An upward movement of at least 90 logical pixels locks.
  static bool shouldLock(double verticalDelta) {
    return verticalDelta <= -lockDistance;
  }
}
