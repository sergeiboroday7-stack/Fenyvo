import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../lib/services/message_deletion_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late Box box;
  late MessageDeletionGuard guard;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fenyvo_516_');
    Hive.init(directory.path);
    box = await Hive.openBox('deleted_messages_516');
    guard = MessageDeletionGuard(box);
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('marks a deleted message', () async {
    expect(
      await guard.markDeleted(chatKey: 'alice_bob', messageId: 'm1'),
      isTrue,
    );
    expect(
      guard.isDeleted(chatKey: 'alice_bob', messageId: 'm1'),
      isTrue,
    );
  });

  test('marker survives Hive reopen', () async {
    await guard.markDeleted(chatKey: 'alice_bob', messageId: 'm1');

    await box.close();
    box = await Hive.openBox('deleted_messages_516');
    guard = MessageDeletionGuard(box);

    expect(
      guard.isDeleted(chatKey: 'alice_bob', messageId: 'm1'),
      isTrue,
    );
  });

  test('same message ID in another chat is not blocked', () async {
    await guard.markDeleted(chatKey: 'alice_bob', messageId: 'm1');

    expect(
      guard.isDeleted(chatKey: 'alice_carol', messageId: 'm1'),
      isFalse,
    );
  });

  test('repeated deletion remains idempotent', () async {
    await guard.markDeleted(chatKey: 'alice_bob', messageId: 'm1');
    await guard.markDeleted(chatKey: 'alice_bob', messageId: 'm1');

    expect(
      guard.isDeleted(chatKey: 'alice_bob', messageId: 'm1'),
      isTrue,
    );
    expect(box.length, 1);
  });

  test('enumerates only distinct chats with markers', () async {
    await guard.markDeleted(chatKey: 'alice_bob', messageId: 'm1');
    await guard.markDeleted(chatKey: 'alice_bob', messageId: 'm2');
    await guard.markDeleted(chatKey: 'alice_carol', messageId: 'm3');

    expect(
      guard.markedChatKeys(),
      containsAll(<String>['alice_bob', 'alice_carol']),
    );
    expect(guard.markedChatKeys().length, 2);
  });

  test('ignores invalid and unrelated marker entries', () async {
    await box.put('deleted:not-valid-base64:m1', true);
    await box.put('other:key', true);
    await box.put('deleted::m1', true);
    await box.put('deleted:YWxpY2VfYm9i:bTE=', false);

    expect(guard.markedChatKeys(), isEmpty);

    await guard.markDeleted(chatKey: 'alice_bob', messageId: 'm2');

    expect(guard.markedChatKeys(), <String>{'alice_bob'});
  });
  test('invalid identity cannot create a marker', () async {
    expect(
      await guard.markDeleted(chatKey: '', messageId: 'm1'),
      isFalse,
    );
    expect(
      await guard.markDeleted(chatKey: 'alice_bob', messageId: ''),
      isFalse,
    );
    expect(box.isEmpty, isTrue);
  });
}