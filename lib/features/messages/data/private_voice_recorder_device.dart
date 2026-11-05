import 'package:record/record.dart';

abstract class PrivateVoiceRecorderBackend {
  Future<bool> hasPermission();
  Future<void> start(String path);
  Future<String?> stop();
  Future<void> dispose();
}

/// Native microphone access isolated from chat and message encryption.
class NativePrivateVoiceRecorderBackend implements PrivateVoiceRecorderBackend {
  NativePrivateVoiceRecorderBackend() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<void> start(String path) => _recorder.start(
    const RecordConfig(
      encoder: AudioEncoder.aacLc,
      bitRate: 64000,
      sampleRate: 44100,
      numChannels: 1,
    ),
    path: path,
  );

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> dispose() => _recorder.dispose();
}

class PrivateVoiceRecorderDevice {
  PrivateVoiceRecorderDevice({PrivateVoiceRecorderBackend? backend})
    : _backend = backend ?? NativePrivateVoiceRecorderBackend();

  final PrivateVoiceRecorderBackend _backend;

  Future<bool> hasPermission() => _backend.hasPermission();

  Future<void> start({required String path}) => _backend.start(path);

  Future<String?> stop() => _backend.stop();

  Future<void> dispose() => _backend.dispose();
}
