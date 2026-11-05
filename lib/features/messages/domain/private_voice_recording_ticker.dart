import 'dart:async';

/// Periodic ticks for an active private voice recording.
///
/// The owner controls UI state, elapsed duration and sending.
/// This class does not access the microphone, files, network or E2EE.
class PrivateVoiceRecordingTicker {
  static const Duration interval = Duration(milliseconds: 250);

  Timer? _timer;

  bool get isRunning => _timer?.isActive ?? false;

  void start({required void Function(Duration delta) onTick}) {
    stop();
    _timer = Timer.periodic(interval, (_) => onTick(interval));
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => stop();
}
