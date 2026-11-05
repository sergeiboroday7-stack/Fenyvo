import 'package:flutter_test/flutter_test.dart';

import '../lib/features/messages/data/private_voice_recorder_device.dart';

class FakeRecorderBackend implements PrivateVoiceRecorderBackend {
  final events = <String>[];
  String? recordedPath;
  bool permissionGranted = true;

  @override
  Future<bool> hasPermission() async {
    events.add('permission');
    return permissionGranted;
  }

  @override
  Future<void> start(String path) async {
    events.add('start');
    recordedPath = path;
  }

  @override
  Future<String?> stop() async {
    events.add('stop');
    return recordedPath;
  }

  @override
  Future<void> dispose() async {
    events.add('dispose');
  }
}

void main() {
  test('delegates permission and start', () async {
    final backend = FakeRecorderBackend();
    final device = PrivateVoiceRecorderDevice(backend: backend);

    expect(await device.hasPermission(), isTrue);

    await device.start(path: 'voice_test.m4a');

    expect(backend.recordedPath, 'voice_test.m4a');
    expect(backend.events, ['permission', 'start']);
  });

  test('delegates stop and dispose', () async {
    final backend = FakeRecorderBackend();
    final device = PrivateVoiceRecorderDevice(backend: backend);

    await device.start(path: 'voice_test.m4a');

    expect(await device.stop(), 'voice_test.m4a');

    await device.dispose();

    expect(backend.events, ['start', 'stop', 'dispose']);
  });

  test('preserves denied microphone permission', () async {
    final backend = FakeRecorderBackend()..permissionGranted = false;

    final device = PrivateVoiceRecorderDevice(backend: backend);

    expect(await device.hasPermission(), isFalse);
    expect(backend.events, ['permission']);
  });
}
