/// Cleans up files left by a failed native recorder start.
///
/// The recorder must be stopped successfully before files are deleted.
/// If stopping fails, the caller retains its tracked path for shutdown.
class PrivateVoiceFailedStartCleanup {
  const PrivateVoiceFailedStartCleanup._();

  static Future<bool> run({
    required String path,
    required Future<String?> Function() stop,
    required Future<void> Function(String path) delete,
  }) async {
    final String? stoppedPath;

    try {
      stoppedPath = await stop();
    } catch (_) {
      return false;
    }

    final paths = <String>{
      if (path.isNotEmpty) path,
      if (stoppedPath != null && stoppedPath.isNotEmpty) stoppedPath,
    };

    for (final candidate in paths) {
      await delete(candidate);
    }

    return true;
  }
}
