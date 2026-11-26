import 'socket_event_generation_guard.dart';

/// Local account and socket scope check for temporary encrypted operations.
/// The server currently does not correlate temporary key responses by request ID.
class TemporaryE2eeScopeGuard {
  const TemporaryE2eeScopeGuard._();

  static bool isCurrent({
    required int eventGeneration,
    required int currentGeneration,
    required Object? eventChannel,
    required Object? currentChannel,
    required bool isAuthenticated,
    required String expectedOwner,
    required String? activeOwner,
    required String expectedAccountId,
    required String? activeAccountId,
  }) =>
      isAuthenticated &&
      expectedOwner.trim().isNotEmpty &&
      expectedOwner.trim() == activeOwner?.trim() &&
      expectedAccountId.trim().isNotEmpty &&
      expectedAccountId.trim() == activeAccountId?.trim() &&
      SocketEventGenerationGuard.isCurrent(
        eventGeneration: eventGeneration,
        currentGeneration: currentGeneration,
        eventChannel: eventChannel,
        currentChannel: currentChannel,
      );
}
