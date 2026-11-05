/// Determines temporary recording paths safe to delete after native stop.
///
/// No files are deleted by this class. The caller must wait until
/// recording has stopped and any upload using these paths is finished.
class PrivateVoiceTempCleanupPolicy {
  const PrivateVoiceTempCleanupPolicy._();

  /// Returns cleanup candidates only after a confirmed successful stop.
  ///
  /// Uploads must already be finished before the caller deletes these paths.
  static List<String> pathsForShutdown({
    required bool stopSucceeded,
    required Iterable<String> trackedPaths,
    String? recordingPath,
    String? stoppedPath,
  }) {
    if (!stopSucceeded) {
      return const <String>[];
    }

    final paths = <String>{
      ...trackedPaths.where((path) => path.isNotEmpty),
      if (recordingPath != null && recordingPath.isNotEmpty) recordingPath,
      if (stoppedPath != null && stoppedPath.isNotEmpty) stoppedPath,
    };

    return List<String>.unmodifiable(paths);
  }

  static List<String> pathsAfterStop({
    required bool stopSucceeded,
    String? originalPath,
    String? stoppedPath,
  }) {
    if (!stopSucceeded) {
      return const <String>[];
    }

    final paths = <String>{};

    if (originalPath != null && originalPath.isNotEmpty) {
      paths.add(originalPath);
    }

    if (stoppedPath != null && stoppedPath.isNotEmpty) {
      paths.add(stoppedPath);
    }

    return List<String>.unmodifiable(paths);
  }
}
