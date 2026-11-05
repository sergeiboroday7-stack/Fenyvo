import 'package:flutter_test/flutter_test.dart';

import '../lib/features/messages/domain/private_voice_recording_state.dart';

void main() {
  test('initial recording state is idle', () {
    final state = PrivateVoiceRecordingState();

    expect(state.pressActive, isFalse);
    expect(state.starting, isFalse);
    expect(state.isRecording, isFalse);
    expect(state.locked, isFalse);
    expect(state.duration, Duration.zero);
    expect(state.recordingPath, isNull);
  });

  test('recording properties are independently mutable', () {
    final state = PrivateVoiceRecordingState();

    state.pressActive = true;
    state.starting = true;
    state.isRecording = true;
    state.locked = true;
    state.duration = const Duration(seconds: 12);
    state.recordingPath = 'voice_123.m4a';

    expect(state.pressActive, isTrue);
    expect(state.starting, isTrue);
    expect(state.isRecording, isTrue);
    expect(state.locked, isTrue);
    expect(state.duration, const Duration(seconds: 12));
    expect(state.recordingPath, 'voice_123.m4a');
  });

  test('clearRecording restores idle state', () {
    final state = PrivateVoiceRecordingState()
      ..pressActive = true
      ..starting = true
      ..isRecording = true
      ..locked = true
      ..duration = const Duration(seconds: 5)
      ..recordingPath = 'temporary.m4a';

    state.clearRecording();

    expect(state.pressActive, isFalse);
    expect(state.starting, isFalse);
    expect(state.isRecording, isFalse);
    expect(state.locked, isFalse);
    expect(state.duration, Duration.zero);
    expect(state.recordingPath, isNull);
  });

  test('separate chats have isolated recording state', () {
    final first = PrivateVoiceRecordingState();
    final second = PrivateVoiceRecordingState();

    first.isRecording = true;
    first.recordingPath = 'first.m4a';

    expect(second.isRecording, isFalse);
    expect(second.recordingPath, isNull);
  });
  test('resetAfterFinish clears visible recording data', () {
    final state = PrivateVoiceRecordingState()
      ..pressActive = false
      ..isRecording = true
      ..locked = true
      ..duration = const Duration(seconds: 9)
      ..recordingPath = 'session.m4a';

    state.resetAfterFinish();

    expect(state.isRecording, isFalse);
    expect(state.locked, isFalse);
    expect(state.duration, Duration.zero);
    expect(state.recordingPath, isNull);
  });

  test('resetAfterFinish preserves pending startup state', () {
    final state = PrivateVoiceRecordingState()
      ..pressActive = true
      ..starting = true
      ..isRecording = true
      ..recordingPath = 'pending.m4a';

    state.resetAfterFinish();

    expect(state.pressActive, isTrue);
    expect(state.starting, isTrue);
    expect(state.isRecording, isFalse);
    expect(state.recordingPath, isNull);
  });
}
