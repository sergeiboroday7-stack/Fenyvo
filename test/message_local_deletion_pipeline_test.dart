import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../lib/services/message_local_deletion_guard.dart';
import '../lib/services/message_local_deletion_pipeline.dart';
import '../lib/services/message_write_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late Box messages;
  late Box markers;
  late MessageLocalDeletionPipeline pipeline;

  const chatKey = 'alice_bob';

  Map<String, dynamic> item(String id) => <String, dynamic>{
    'id': id,
    'from': 'alice',
    'to': 'bob',
    'text': 'content-$id',
    'time': '2026-11-03T12:00:00Z',
  };

  List<Map<String, dynamic>> readHistory() {
    final raw = messages.get(chatKey);
    if (raw is! List) return <Map<String, dynamic>>[];

    return [
      for (final entry in raw)
        Map<String, dynamic>.from(entry as Map),
    ];
  }

  void createPipeline() {
    pipeline = MessageLocalDeletionPipeline(
      messagesBox: messages,
      guard: MessageLocalDeletionGuard(markers),
      coordinator: MessageWriteCoordinator(),
    );
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fenyvo_552_');
    Hive.init(directory.path);

    messages = await Hive.openBox('history_552');
    markers = await Hive.openBox('markers_552');

    await messages.put(chatKey, [item('m1'), item('m2')]);
    createPipeline();
  });

  tearDown(() async {
    await Hive.close();

    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('hiding for one owner preserves shared history', () async {
    expect(
      await pipeline.hideForOwner(
        chatKey: chatKey,
        owner: 'alice',
        peer: 'bob',
        messageId: 'm1',
      ),
      isTrue,
    );

    expect(readHistory().map((m) => m['id']), ['m1', 'm2']);

    final alice = pipeline.visibleForOwner(
      owner: 'alice',
      peer: 'bob',
      messages: readHistory(),
    );

    final bob = pipeline.visibleForOwner(
      owner: 'bob',
      peer: 'alice',
      messages: readHistory(),
    );

    expect(alice.map((m) => m['id']), ['m2']);
    expect(bob.map((m) => m['id']), ['m1', 'm2']);
  });

  test('marker survives restart and filters replay', () async {
    await pipeline.hideForOwner(
      chatKey: chatKey,
      owner: 'alice',
      peer: 'bob',
      messageId: 'm1',
    );

    await messages.close();
    await markers.close();

    messages = await Hive.openBox('history_552');
    markers = await Hive.openBox('markers_552');
    createPipeline();

    final replayed = [...readHistory(), item('m1')];

    final visible = pipeline.visibleForOwner(
      owner: 'alice',
      peer: 'bob',
      messages: replayed,
    );

    expect(visible.map((m) => m['id']), ['m2']);
  });

  test('invalid or unrelated request creates no marker', () async {
    expect(
      await pipeline.hideForOwner(
        chatKey: chatKey,
        owner: 'alice',
        peer: 'bob',
        messageId: 'missing',
      ),
      isFalse,
    );

    expect(
      await pipeline.hideForOwner(
        chatKey: chatKey,
        owner: 'carol',
        peer: 'bob',
        messageId: 'm1',
      ),
      isFalse,
    );

    expect(
      await pipeline.hideForOwner(
        chatKey: 'wrong_chat',
        owner: 'alice',
        peer: 'bob',
        messageId: 'm1',
      ),
      isFalse,
    );

    expect(markers.isEmpty, isTrue);
  });

  test('repeated hide is idempotent', () async {
    for (var i = 0; i < 2; i++) {
      expect(
        await pipeline.hideForOwner(
          chatKey: chatKey,
          owner: 'alice',
          peer: 'bob',
          messageId: 'm1',
        ),
        isTrue,
      );
    }

    expect(markers.length, 1);
    expect(readHistory().length, 2);
  });

  test('simultaneous hides use the shared queue', () async {
    final results = await Future.wait([
      pipeline.hideForOwner(
        chatKey: chatKey,
        owner: 'alice',
        peer: 'bob',
        messageId: 'm1',
      ),
      pipeline.hideForOwner(
        chatKey: chatKey,
        owner: 'alice',
        peer: 'bob',
        messageId: 'm2',
      ),
    ]);

    expect(results, [true, true]);
    expect(markers.length, 2);

    final visible = pipeline.visibleForOwner(
      owner: 'alice',
      peer: 'bob',
      messages: readHistory(),
    );

    expect(visible, isEmpty);
  });

  test('invalid owner exposes no messages', () {
    expect(
      pipeline.visibleForOwner(
        owner: '',
        peer: 'bob',
        messages: readHistory(),
      ),
      isEmpty,
    );
  });

  test('unmarked legacy message without ID remains visible', () {
    final legacy = <String, dynamic>{
      'from': 'bob',
      'to': 'alice',
      'time': '2026-11-03T12:00:00Z',
      'text': 'legacy',
    };

    final visible = pipeline.visibleForOwner(
      owner: 'alice',
      peer: 'bob',
      messages: [legacy],
    );

    expect(visible, [legacy]);
  });

  test('unrelated participants are excluded from filtered view', () {
    final unrelated = <String, dynamic>{
      'id': 'other',
      'from': 'carol',
      'to': 'bob',
    };

    final visible = pipeline.visibleForOwner(
      owner: 'alice',
      peer: 'bob',
      messages: [item('m1'), unrelated],
    );

    expect(visible.map((m) => m['id']), ['m1']);
  });
}
