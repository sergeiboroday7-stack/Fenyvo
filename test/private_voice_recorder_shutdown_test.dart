import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../lib/features/messages/data/private_voice_recorder_shutdown.dart';

void main() {
  test('waits for startup before stopping and disposing', () async {
    final start = Completer<void>();
    final order = <String>[];
    final shutdown = PrivateVoiceRecorderShutdown();

    final future = shutdown.close(
      pendingStart: start.future,
      stop: () async => order.add('stop'),
      cleanup: () async => order.add('cleanup'),
      dispose: () async => order.add('dispose'),
    );

    expect(shutdown.isClosing, isTrue);
    expect(order, isEmpty);

    start.complete();
    await future;

    expect(order, ['stop', 'cleanup', 'dispose']);
  });

  test('waits for ongoing finish before closing recorder', () async {
    final finish = Completer<void>();
    final order = <String>[];
    final shutdown = PrivateVoiceRecorderShutdown();

    final future = shutdown.close(
      pendingFinish: finish.future,
      stop: () async => order.add('stop'),
      cleanup: () async => order.add('cleanup'),
      dispose: () async => order.add('dispose'),
    );

    expect(order, isEmpty);

    finish.complete();
    await future;

    expect(order, ['stop', 'cleanup', 'dispose']);
  });

  test('shutdown is idempotent', () async {
    final shutdown = PrivateVoiceRecorderShutdown();
    var stops = 0;
    var disposals = 0;

    Future<void> close() => shutdown.close(
      stop: () async => stops++,
      cleanup: () async {},
      dispose: () async => disposals++,
    );

    await Future.wait([close(), close()]);

    expect(stops, 1);
    expect(disposals, 1);
  });

  test('cleanup and dispose still run if stop fails', () async {
    final shutdown = PrivateVoiceRecorderShutdown();
    final order = <String>[];

    await expectLater(
      shutdown.close(
        stop: () async {
          order.add('stop');
          throw StateError('stop failed');
        },
        cleanup: () async => order.add('cleanup'),
        dispose: () async => order.add('dispose'),
      ),
      throwsStateError,
    );

    expect(order, ['stop', 'cleanup', 'dispose']);
  });
}
