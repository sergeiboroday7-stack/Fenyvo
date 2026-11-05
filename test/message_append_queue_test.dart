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
  late MessageWriteCoordinator coordinator;

  const key = 'alice_bob';

  Map<String, dynamic> message(String id, String from, String to) =>
      <String, dynamic>{
        'id': id,
        'from': from,
        'to': to,
        'time': '2026-11-03T12:00:00Z',
        'text': 'hello',
        'status': 'sent',
      };

  Future<bool> append(Map<String, dynamic> item) =>
      coordinator.run<bool>(
        key,
        () => mutateMessagesInHive(
          box,
          key,
          (current) => appendMessageIfMissing(current, item),
        ),
      );

  List<Map<String, dynamic>> read() {
    final raw = box.get(key);
    if (raw is! List) return [];
    return [
      for (final item in raw) Map<String, dynamic>.from(item as Map),
    ];
  }

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fenyvo_512_');
    Hive.init(directory.path);
    box = await Hive.openBox('append_queue_512');
    coordinator = MessageWriteCoordinator();
  });

  tearDown(() async {
    await Hive.close();
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('both chat directions persist sequentially', () async {
    final first = append(message('m1', 'alice', 'bob'));
    final second = append(message('m2', 'bob', 'alice'));

    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(read().map((item) => item['id']), ['m1', 'm2']);
  });

  test('same ID from another sender is rejected', () async {
    expect(await append(message('m1', 'alice', 'bob')), isTrue);
    expect(await append(message('m1', 'bob', 'alice')), isFalse);

    expect(read().length, 1);
    expect(read().single['from'], 'alice');
  });

  test('invalid identity does not create an entry', () async {
    expect(await append(message('', '', 'bob')), isFalse);
    expect(read(), isEmpty);
    expect(box.containsKey(key), isFalse);
  });
}