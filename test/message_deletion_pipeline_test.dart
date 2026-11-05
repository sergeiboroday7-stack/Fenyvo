import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../lib/services/message_deletion_guard.dart';
import '../lib/services/message_deletion_pipeline.dart';
import '../lib/services/message_persistence_service.dart';
import '../lib/services/message_write_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late Box messages;
  late Box markers;
  late MessageDeletionPipeline pipeline;

  const key = 'alice_bob';

  Map<String, dynamic> message(
    String id, {
    Map<String, dynamic>? replyTo,
  }) =>
      <String, dynamic>{
        'id': id,
        'from': 'alice',
        'to': 'bob',
        'time': '2026-11-03T12:00:00Z',
        'text': 'text-$id',
        'status': 'sent',
        if (replyTo != null) 'replyTo': replyTo,
      };

  List<Map<String, dynamic>> read() {
    final raw = messages.get(key);
    if (raw is! List) return [];
    return [
      for (final item in raw) Map<String, dynamic>.from(item as Map),
    ];
  }

  void createPipeline() {
    pipeline = MessageDeletionPipeline(
      messagesBox: messages,
      guard: MessageDeletionGuard(markers),
      coordinator: MessageWriteCoordinator(),
    );
  }

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('fenyvo_519_');
    Hive.init(sandbox.path);
    messages = await Hive.openBox('history_519');
    markers = await Hive.openBox('deleted_519');
    createPipeline();

    await persistMessagesToHive(messages, key, [
      message('m1'),
      message('m2', replyTo: {'id': 'm1', 'text': 'text-m1'}),
    ]);
  });

  tearDown(() async {
    await Hive.close();
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('delete removes message and reply reference', () async {
    expect(
      await pipeline.deleteForEveryone(chatKey: key, messageId: 'm1'),
      isTrue,
    );

    expect(read().map((m) => m['id']), ['m2']);
    expect(read().single.containsKey('replyTo'), isFalse);
  });

  test('deleted message cannot be appended again', () async {
    await pipeline.deleteForEveryone(chatKey: key, messageId: 'm1');

    expect(
      await pipeline.append(chatKey: key, incoming: message('m1')),
      isFalse,
    );
    expect(read().map((m) => m['id']), ['m2']);
  });

  test('marker survives restart and prevents replay', () async {
    await pipeline.deleteForEveryone(chatKey: key, messageId: 'm1');

    await messages.close();
    await markers.close();

    messages = await Hive.openBox('history_519');
    markers = await Hive.openBox('deleted_519');
    createPipeline();

    expect(
      await pipeline.append(chatKey: key, incoming: message('m1')),
      isFalse,
    );
    expect(read().map((m) => m['id']), ['m2']);
  });

  test('reconcile completes interrupted deletion', () async {
    final guard = MessageDeletionGuard(markers);

    // Simulate a crash after marker persistence but before removal.
    await guard.markDeleted(chatKey: key, messageId: 'm1');

    expect(read().map((m) => m['id']), ['m1', 'm2']);

    expect(await pipeline.reconcile(chatKey: key), isTrue);

    expect(read().map((m) => m['id']), ['m2']);
    expect(read().single.containsKey('replyTo'), isFalse);
  });

  test('duplicate arrival still persists interrupted deletion repair', () async {
    final guard = MessageDeletionGuard(markers);

    // Marker committed, but the process stopped before history deletion.
    await guard.markDeleted(chatKey: key, messageId: 'm1');

    // An already-present message arrives again.
    final changed = await pipeline.append(
      chatKey: key,
      incoming: message('m2'),
    );

    // A repair occurred, but no new incoming message was appended.
    expect(changed, isFalse);
    expect(read().map((m) => m['id']), ['m2']);
    expect(read().single.containsKey('replyTo'), isFalse);

    await messages.close();
    messages = await Hive.openBox('history_519');
    createPipeline();

    expect(read().map((m) => m['id']), ['m2']);
  });

  test('reconcile clears orphan reply after original was removed', () async {
    final guard = MessageDeletionGuard(markers);

    await guard.markDeleted(chatKey: key, messageId: 'm1');

    // Simulate history where original is gone but its reply remains.
    await persistMessagesToHive(messages, key, [
      message('m2', replyTo: {'id': 'm1', 'text': 'text-m1'}),
    ]);

    expect(await pipeline.reconcile(chatKey: key), isTrue);
    expect(read().single.containsKey('replyTo'), isFalse);
  });
  test('legacy ID-less message appends once', () async {
    final legacy = message('');
    legacy.remove('id');

    expect(
      await pipeline.append(chatKey: key, incoming: legacy),
      isTrue,
    );
    expect(
      await pipeline.append(chatKey: key, incoming: legacy),
      isFalse,
    );

    expect(read().length, 3);
  });

  test('legacy append repairs interrupted deletion', () async {
    final guard = MessageDeletionGuard(markers);

    await guard.markDeleted(chatKey: key, messageId: 'm1');

    final legacy = message('');
    legacy.remove('id');

    expect(
      await pipeline.append(chatKey: key, incoming: legacy),
      isTrue,
    );

    final stored = read();
    expect(stored.any((m) => m['id'] == 'm1'), isFalse);
    expect(stored.any((m) => m['id'] == 'm2'), isTrue);
    expect(stored.any((m) => !m.containsKey('id')), isTrue);

    final remainingReply = stored.firstWhere((m) => m['id'] == 'm2');
    expect(remainingReply.containsKey('replyTo'), isFalse);
  });
  test('unrelated messages remain available', () async {
    await pipeline.deleteForEveryone(chatKey: key, messageId: 'm1');

    expect(
      await pipeline.append(chatKey: key, incoming: message('m3')),
      isTrue,
    );

    expect(read().map((m) => m['id']), ['m2', 'm3']);
  });
}