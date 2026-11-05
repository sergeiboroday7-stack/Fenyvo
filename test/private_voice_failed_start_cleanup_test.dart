import 'package:flutter_test/flutter_test.dart';

import '../lib/features/messages/data/private_voice_failed_start_cleanup.dart';

void main() {
  test('stops recorder before deleting the pending file', () async {
    final events = <String>[];

    final cleaned = await PrivateVoiceFailedStartCleanup.run(
      path: 'pending.m4a',
      stop: () async {
        events.add('stop');
        return null;
      },
      delete: (path) async {
        events.add('delete:$path');
      },
    );

    expect(cleaned, isTrue);
    expect(events, ['stop', 'delete:pending.m4a']);
  });

  test('deletes both distinct paths after successful stop', () async {
    final deleted = <String>[];

    final cleaned = await PrivateVoiceFailedStartCleanup.run(
      path: 'pending.m4a',
      stop: () async => 'returned.m4a',
      delete: (path) async => deleted.add(path),
    );

    expect(cleaned, isTrue);
    expect(deleted, ['pending.m4a', 'returned.m4a']);
  });

  test('does not delete files when recorder stop fails', () async {
    final deleted = <String>[];

    final cleaned = await PrivateVoiceFailedStartCleanup.run(
      path: 'pending.m4a',
      stop: () async => throw StateError('stop failed'),
      delete: (path) async => deleted.add(path),
    );

    expect(cleaned, isFalse);
    expect(deleted, isEmpty);
  });

  test('does not report success if deletion fails', () async {
    await expectLater(
      PrivateVoiceFailedStartCleanup.run(
        path: 'pending.m4a',
        stop: () async => null,
        delete: (path) async => throw StateError('delete failed'),
      ),
      throwsStateError,
    );
  });
}
