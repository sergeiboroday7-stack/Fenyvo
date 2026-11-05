import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../lib/features/messages/domain/private_voice_recording_operations.dart';

void main() {
  test('concurrent starts invoke the action once', () async {
    final operations = PrivateVoiceRecordingOperations();
    final ready = Completer<void>();
    var calls = 0;

    Future<void> action() {
      calls++;
      return ready.future;
    }

    final first = operations.start(isClosing: false, action: action);

    final second = operations.start(isClosing: false, action: action);

    expect(calls, 1);
    expect(operations.pendingStart, isNotNull);

    ready.complete();
    await Future.wait([first, second]);

    expect(operations.pendingStart, isNull);
  });

  test('concurrent finishes invoke the action once', () async {
    final operations = PrivateVoiceRecordingOperations();
    final ready = Completer<void>();
    var calls = 0;

    Future<void> action() {
      calls++;
      return ready.future;
    }

    final first = operations.finish(isClosing: false, action: action);

    final second = operations.finish(isClosing: false, action: action);

    expect(calls, 1);
    expect(operations.pendingFinish, isNotNull);

    ready.complete();
    await Future.wait([first, second]);

    expect(operations.pendingFinish, isNull);
  });

  test('pending finish prevents another start', () async {
    final operations = PrivateVoiceRecordingOperations();
    final ready = Completer<void>();
    var starts = 0;

    final finish = operations.finish(
      isClosing: false,
      action: () => ready.future,
    );

    await operations.start(isClosing: false, action: () async => starts++);

    expect(starts, 0);

    ready.complete();
    await finish;
  });

  test('closing blocks both start and finish', () async {
    final operations = PrivateVoiceRecordingOperations();
    var calls = 0;

    await operations.start(isClosing: true, action: () async => calls++);

    await operations.finish(isClosing: true, action: () async => calls++);

    expect(calls, 0);
    expect(operations.pendingStart, isNull);
    expect(operations.pendingFinish, isNull);
  });
  test('synchronous start failure allows a later retry', () async {
    final operations = PrivateVoiceRecordingOperations();
    var attempts = 0;

    await expectLater(
      operations.start(
        isClosing: false,
        action: () {
          attempts++;
          throw StateError('start failed');
        },
      ),
      throwsStateError,
    );

    expect(operations.pendingStart, isNull);

    await operations.start(isClosing: false, action: () async => attempts++);

    expect(attempts, 2);
    expect(operations.pendingStart, isNull);
  });

  test('synchronous finish failure allows a later retry', () async {
    final operations = PrivateVoiceRecordingOperations();
    var attempts = 0;

    await expectLater(
      operations.finish(
        isClosing: false,
        action: () {
          attempts++;
          throw StateError('finish failed');
        },
      ),
      throwsStateError,
    );

    expect(operations.pendingFinish, isNull);

    await operations.finish(isClosing: false, action: () async => attempts++);

    expect(attempts, 2);
    expect(operations.pendingFinish, isNull);
  });

  test('asynchronous failure clears pending operation', () async {
    final operations = PrivateVoiceRecordingOperations();
    final pending = Completer<void>();
    var attempts = 0;

    final first = operations.start(
      isClosing: false,
      action: () {
        attempts++;
        return pending.future;
      },
    );

    expect(operations.pendingStart, isNotNull);

    pending.completeError(StateError('microphone unavailable'));

    await expectLater(first, throwsStateError);

    expect(operations.pendingStart, isNull);

    await operations.start(isClosing: false, action: () async => attempts++);

    expect(attempts, 2);
  });
}
