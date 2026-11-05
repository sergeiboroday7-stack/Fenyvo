/// Tracks temporary voice recording paths until cleanup succeeds.
///
/// Multiple paths may exist when an earlier recording is still finishing.
/// This class does not delete files or access the microphone.
class PrivateVoiceTempPathTracker {
  final Set<String> _tracked = <String>{};

  List<String> get paths => List<String>.unmodifiable(_tracked);

  int get count => _tracked.length;

  void track(String path) {
    if (path.isEmpty) {
      return;
    }
    _tracked.add(path);
  }

  void release(String path) {
    _tracked.remove(path);
  }

  void clear() {
    _tracked.clear();
  }
}
