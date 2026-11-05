/// Rejects events belonging to a replaced WebSocket connection.
///
/// This is a local connection identity check, not a server request ID.
/// It does not establish which account authored an untagged reply.
class SocketEventGenerationGuard {
  const SocketEventGenerationGuard._();

  static bool isCurrent({
    required int eventGeneration,
    required int currentGeneration,
    required Object? eventChannel,
    required Object? currentChannel,
  }) {
    return eventGeneration == currentGeneration &&
        eventChannel != null &&
        identical(eventChannel, currentChannel);
  }
}