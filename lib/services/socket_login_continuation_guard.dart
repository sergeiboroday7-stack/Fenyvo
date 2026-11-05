import 'socket_event_generation_guard.dart';

/// Validates that asynchronous login work still belongs to
/// the active authenticated account and WebSocket connection.
class SocketLoginContinuationGuard {
  const SocketLoginContinuationGuard._();

  static bool isCurrent({
    required int eventGeneration,
    required int currentGeneration,
    required Object? eventChannel,
    required Object? currentChannel,
    required bool isAuthenticated,
    required String expectedOwner,
    required String? activeOwner,
  }) {
    final expected = expectedOwner.trim();
    final active = activeOwner?.trim() ?? '';

    if (expected.isEmpty ||
        active.isEmpty ||
        !isAuthenticated ||
        expected != active) {
      return false;
    }

    return SocketEventGenerationGuard.isCurrent(
      eventGeneration: eventGeneration,
      currentGeneration: currentGeneration,
      eventChannel: eventChannel,
      currentChannel: currentChannel,
    );
  }
}
