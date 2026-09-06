/// Monotonic elapsed time; ringing is excluded and reconnect does not reset it.
class CallClock {
  final Stopwatch _watch = Stopwatch();
  bool connected = false;
  Duration get elapsed => _watch.elapsed;
  void connect() {
    if (connected) return;
    connected = true;
    _watch.start();
  }

  void stop() => _watch.stop();
  void reset() {
    _watch.stop();
    _watch.reset();
    connected = false;
  }

  String get label => format(elapsed);
  static String format(Duration duration) {
    String two(int n) => n.toString().padLeft(2, '0');
    final s = two(duration.inSeconds % 60);
    final m = two(duration.inMinutes % 60);
    return duration.inHours > 0 ? '${two(duration.inHours)}:$m:$s' : '$m:$s';
  }
}
