import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../lib/services/message_persistence_service.dart';
import '../lib/services/message_write_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late Box box;
  late MessageWriteCoordinator queue;

  const key = 'alice_bob';

  Map<String, dynamic> message(
    String id, {
    String status = 'sent',
    Map<String, dynamic>? replyTo,
  }) =>
      <String, dynamic>{
        'id': id,
        'from': 'alice',
        'to': 'bob',
        'status': status,
        'text': id,
        if (replyTo != null) 'replyTo': replyTo,
      };

  Future<bool> delete(String id) => queue.run<bool>(
        key,
        () => mutateMessagesInHive(box, key, (current) {
          final before = current.length;
          current.removeWhere(
            (item) => item['id']?.toString().trim() == id,
          );

          var changed = current.length != before;

          for (final item in current) {
            final reply = item['replyTo'];
            if (reply is Map &&
                reply['id']?.toString().trim() == id) {
              item.remove('replyTo');
              changed = true;
            }
          }

          return changed ? current : null;
        }),
      );

  List<Map<String, dynamic>> read() {
    final raw = box.get(key);
    if (raw is! List) return [];
    return raw
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('fenyvo_509_');
    Hive.init(sandbox.path);
    box = await Hive.openBox('delete_509');
    queue = MessageWriteCoordinator();

    await persistMessagesToHive(box, key, [
      message('m1', status: 'read'),
      message('m2', replyTo: {'id': 'm1', 'text': 'm1'}),
      message('m3'),
    ]);
  });

  tearDown(() async {
    await Hive.close();
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('deletes the target and preserves other messages', () async {
    expect(await delete('m1'), isTrue);

    final remaining = read();
    expect(remaining.map((m) => m['id']), ['m2', 'm3']);
    expect(remaining.first.containsKey('replyTo'), isFalse);
  });

  test('repeated deletion performs no additional write', () async {
    expect(await delete('m1'), isTrue);
    expect(await delete('m1'), isFalse);
    expect(read().length, 2);
  });

  test('deletion persists after reopening Hive', () async {
    await delete('m1');
    await box.close();
    box = await Hive.openBox('delete_509');

    expect(read().map((m) => m['id']), ['m2', 'm3']);
  });

  test('other message statuses remain unchanged', () async {
    await delete('m2');

    final remaining = read();
    expect(remaining.first['id'], 'm1');
    expect(remaining.first['status'], 'read');
    expect(remaining.last['id'], 'm3');
  });

  test('missing message does not change history', () async {
    final before = read();

    expect(await delete('missing'), isFalse);
    expect(read(), before);
  });
}