import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../lib/services/message_append_mutation.dart';
import '../lib/services/message_persistence_service.dart';
import '../lib/services/message_write_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;
  late Box box;
  late MessageWriteCoordinator queue;

  const key = 'alice_bob';

  Map<String, dynamic> message(
    String id, {
    String text = 'hello',
    String status = 'sent',
  }) =>
      <String, dynamic>{
        'id': id,
        'from': 'alice',
        'to': 'bob',
        'time': '2026-11-03T12:00:00Z',
        'text': text,
        'status': status,
      };

  List<Map<String, dynamic>> read() {
    final raw = box.get(key);
    if (raw is! List) return [];
    return raw
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<bool> append(Map<String, dynamic> incoming) =>
      queue.run<bool>(
        key,
        () => mutateMessagesInHive(
          box,
          key,
          (current) => appendMessageIfMissing(current, incoming),
        ),
      );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fenyvo_511_');
    Hive.init(directory.path);
    box = await Hive.openBox('append_511');
    queue = MessageWriteCoordinator();

    await persistMessagesToHive(box, key, [
      message('m1', text: 'edited', status: 'read'),
    ]);
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('appends a new message without replacing history', () async {
    expect(await append(message('m2')), isTrue);
    expect(read().map((m) => m['id']), ['m1', 'm2']);
  });

  test('duplicate event does not append twice', () async {
    expect(await append(message('m2')), isTrue);
    expect(await append(message('m2')), isFalse);
    expect(read().length, 2);
  });

  test('existing read status is preserved', () async {
    await append(message('m2', status: 'sent'));

    expect(read().first['status'], 'read');
    expect(read().last['status'], 'sent');
  });

  test('existing edited text is preserved', () async {
    await append(message('m2'));

    expect(read().first['text'], 'edited');
  });

  test('two queued arrivals retain both messages', () async {
    final gate = Completer<void>();
    final started = Completer<void>();

    final first = queue.run<void>(key, () async {
      started.complete();
      await gate.future;
    });

    await started.future;

    final second = append(message('m2'));
    final third = append(message('m3'));

    gate.complete();

    await first;
    expect(await second, isTrue);
    expect(await third, isTrue);

    await box.close();
    box = await Hive.openBox('append_511');

    expect(read().map((m) => m['id']), ['m1', 'm2', 'm3']);
  });
}