import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../lib/features/messages/data/private_voice_recorder_shutdown.dart';

void main() {
  test('closing during microphone startup waits for start', () async {
    final start = Completer<void>();
    final events = <String>[];
    final shutdown = PrivateVoiceRecorderShutdown();

    final closing = shutdown.close(
      pendingStart: start.future,
      stop: () async => events.add('stop'),
      cleanup: () async => events.add('delete-temp'),
      dispose: () async => events.add('dispose'),
    );

    expect(shutdown.isClosing, isTrue);
    expect(events, isEmpty);

    start.complete();
    await closing;

    expect(events, ['stop', 'delete-temp', 'dispose']);
  });

  test('closing during voice send waits before deleting temp file', () async {
    final finish = Completer<void>();
    final events = <String>[];
    final shutdown = PrivateVoiceRecorderShutdown();

    final closing = shutdown.close(
      pendingFinish: finish.future,
      stop: () async => events.add('stop'),
      cleanup: () async => events.add('delete-temp'),
      dispose: () async => events.add('dispose'),
    );

    expect(events, isEmpty);

    events.add('send-complete');
    finish.complete();

    await closing;

    expect(events, ['send-complete', 'stop', 'delete-temp', 'dispose']);
  });
}
