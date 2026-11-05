import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../lib/services/message_deletion_guard.dart';
import '../lib/services/message_deletion_pipeline.dart';
import '../lib/services/message_write_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late Box messages;
  late Box deleted;
  late MessageWriteCoordinator coordinator;
  late MessageDeletionPipeline pipeline;

  const chatKey = 'alice_bob';

  Map<String, dynamic> incoming(String id) => {
    'id': id,
    'from': 'bob',
    'to': 'alice',
    'text': 'test',
    'time': '2026-11-04T10:00:00',
  };

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fenyvo_block_race_');
    Hive.init(directory.path);

    messages = await Hive.openBox('messages_race');
    deleted = await Hive.openBox('deleted_race');

    coordinator = MessageWriteCoordinator();
    pipeline = MessageDeletionPipeline(
      messagesBox: messages,
      guard: MessageDeletionGuard(deleted),
      coordinator: coordinator,
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('blocked while queued: append is rejected', () async {
    var blocked = false;
    var checks = 0;
    final release = Completer<void>();

    final earlierOperation = coordinator.run<void>(
      chatKey,
      () async => release.future,
    );

    final pendingAppend = pipeline.append(
      chatKey: chatKey,
      incoming: incoming('queued-blocked'),
      allowAppend: () async {
        checks++;
        return !blocked;
      },
    );

    // The message is waiting behind an earlier operation.
    blocked = true;
    release.complete();
    await earlierOperation;

    expect(await pendingAppend, isFalse);
    expect(checks, 1);
    expect(messages.get(chatKey), isNull);
  });

  test('allowed when queued: message is saved', () async {
    var blocked = false;
    final release = Completer<void>();

    final earlierOperation = coordinator.run<void>(
      chatKey,
      () async => release.future,
    );

    final pendingAppend = pipeline.append(
      chatKey: chatKey,
      incoming: incoming('queued-allowed'),
      allowAppend: () async => !blocked,
    );

    release.complete();
    await earlierOperation;

    expect(await pendingAppend, isTrue);
    final stored = messages.get(chatKey) as List;
    expect(stored.length, 1);
    expect((stored.single as Map)['id'], 'queued-allowed');
  });

  test('existing callers without callback remain compatible', () async {
    final appended = await pipeline.append(
      chatKey: chatKey,
      incoming: incoming('legacy-caller'),
    );

    expect(appended, isTrue);

    final stored = messages.get(chatKey) as List;
    expect(stored.length, 1);
  });

  test('replayed message is not duplicated', () async {
    expect(
      await pipeline.append(
        chatKey: chatKey,
        incoming: incoming('duplicate'),
        allowAppend: () async => true,
      ),
      isTrue,
    );

    expect(
      await pipeline.append(
        chatKey: chatKey,
        incoming: incoming('duplicate'),
        allowAppend: () async => true,
      ),
      isFalse,
    );

    expect((messages.get(chatKey) as List).length, 1);
  });
}
