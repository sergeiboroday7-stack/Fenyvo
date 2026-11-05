import 'package:flutter_test/flutter_test.dart';

import '../lib/features/messages/data/private_voice_temp_cleanup_policy.dart';

void main() {
  test('successful stop returns the original path', () {
    final paths = PrivateVoiceTempCleanupPolicy.pathsAfterStop(
      stopSucceeded: true,
      originalPath: 'original.m4a',
    );

    expect(paths, ['original.m4a']);
  });

  test('successful stop includes a distinct returned path', () {
    final paths = PrivateVoiceTempCleanupPolicy.pathsAfterStop(
      stopSucceeded: true,
      originalPath: 'original.m4a',
      stoppedPath: 'returned.m4a',
    );

    expect(paths, ['original.m4a', 'returned.m4a']);
  });

  test('identical paths are not duplicated', () {
    final paths = PrivateVoiceTempCleanupPolicy.pathsAfterStop(
      stopSucceeded: true,
      originalPath: 'same.m4a',
      stoppedPath: 'same.m4a',
    );

    expect(paths, ['same.m4a']);
  });

  test('failed stop never authorizes file deletion', () {
    final paths = PrivateVoiceTempCleanupPolicy.pathsAfterStop(
      stopSucceeded: false,
      originalPath: 'still_recording.m4a',
      stoppedPath: 'other.m4a',
    );

    expect(paths, isEmpty);
  });
  test('empty original path retains returned path', () {
    final paths = PrivateVoiceTempCleanupPolicy.pathsAfterStop(
      stopSucceeded: true,
      originalPath: '',
      stoppedPath: 'returned.m4a',
    );

    expect(paths, ['returned.m4a']);
  });

  test('successful stop with no paths has no cleanup candidates', () {
    final paths = PrivateVoiceTempCleanupPolicy.pathsAfterStop(
      stopSucceeded: true,
    );

    expect(paths, isEmpty);
  });
  test('shutdown skips all files if native stop failed', () {
    final paths = PrivateVoiceTempCleanupPolicy.pathsForShutdown(
      stopSucceeded: false,
      trackedPaths: ['pending.m4a', 'uploading.m4a'],
      recordingPath: 'active.m4a',
      stoppedPath: 'returned.m4a',
    );

    expect(paths, isEmpty);
  });

  test('shutdown includes each distinct path after successful stop', () {
    final paths = PrivateVoiceTempCleanupPolicy.pathsForShutdown(
      stopSucceeded: true,
      trackedPaths: ['pending.m4a', 'uploading.m4a'],
      recordingPath: 'pending.m4a',
      stoppedPath: 'returned.m4a',
    );

    expect(paths, ['pending.m4a', 'uploading.m4a', 'returned.m4a']);
  });

  test('shutdown excludes duplicate and empty paths', () {
    final paths = PrivateVoiceTempCleanupPolicy.pathsForShutdown(
      stopSucceeded: true,
      trackedPaths: ['', 'same.m4a', 'same.m4a'],
      recordingPath: 'same.m4a',
      stoppedPath: '',
    );

    expect(paths, ['same.m4a']);
  });
}
