import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../lib/services/message_local_deletion_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late Box box;
  late MessageLocalDeletionGuard guard;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fenyvo_550_');
    Hive.init(directory.path);
    box = await Hive.openBox('local_deletions_550');
    guard = MessageLocalDeletionGuard(box);
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('marker persists after Hive reopen', () async {
    expect(
      await guard.markDeleted(
        owner: 'alice',
        peer: 'bob',
        messageId: 'm1',
      ),
      isTrue,
    );

    await box.close();
    box = await Hive.openBox('local_deletions_550');
    guard = MessageLocalDeletionGuard(box);

    expect(
      guard.isDeleted(
        owner: 'alice',
        peer: 'bob',
        messageId: 'm1',
      ),
      isTrue,
    );
  });

  test('other account is not affected', () async {
    await guard.markDeleted(
      owner: 'alice',
      peer: 'bob',
      messageId: 'm1',
    );

    expect(
      guard.isDeleted(
        owner: 'bob',
        peer: 'alice',
        messageId: 'm1',
      ),
      isFalse,
    );
  });

  test('other peer and message ID are not affected', () async {
    await guard.markDeleted(
      owner: 'alice',
      peer: 'bob',
      messageId: 'm1',
    );

    expect(
      guard.isDeleted(
        owner: 'alice',
        peer: 'carol',
        messageId: 'm1',
      ),
      isFalse,
    );

    expect(
      guard.isDeleted(
        owner: 'alice',
        peer: 'bob',
        messageId: 'm2',
      ),
      isFalse,
    );
  });

  test('invalid identities cannot create markers', () async {
    expect(
      await guard.markDeleted(
        owner: '',
        peer: 'bob',
        messageId: 'm1',
      ),
      isFalse,
    );

    expect(
      await guard.markDeleted(
        owner: 'alice',
        peer: 'alice',
        messageId: 'm1',
      ),
      isFalse,
    );

    expect(
      await guard.markDeleted(
        owner: 'alice',
        peer: 'bob',
        messageId: '',
      ),
      isFalse,
    );

    expect(box.isEmpty, isTrue);
  });

  test('repeated deletion marker is idempotent', () async {
    for (var i = 0; i < 2; i++) {
      expect(
        await guard.markDeleted(
          owner: 'alice',
          peer: 'bob',
          messageId: 'm1',
        ),
        isTrue,
      );
    }

    expect(box.length, 1);
    expect(box.values.single, isTrue);
  });

  test('marker key contains no plaintext user or ID', () async {
    await guard.markDeleted(
      owner: 'alice',
      peer: 'bob',
      messageId: 'secret-message-id',
    );

    final storedKey = box.keys.single.toString();
    expect(storedKey, startsWith('local_deleted:'));
    expect(storedKey, isNot(contains('alice')));
    expect(storedKey, isNot(contains('secret-message-id')));
  });
}
