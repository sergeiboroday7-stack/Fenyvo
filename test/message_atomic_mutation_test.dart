import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../lib/services/message_persistence_service.dart';
import '../lib/services/message_write_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late Box box;
  late MessageWriteCoordinator coordinator;

  const key = 'alice_bob';

  Map<String, dynamic> message(String status, {String text = 'old'}) =>
      <String, dynamic>{
        'id': 'm1',
        'from': 'alice',
        'to': 'bob',
        'isMe': true,
        'status': status,
        'text': text,
      };

  Future<bool> mutate(
    List<Map<String, dynamic>>? Function(
      List<Map<String, dynamic>> current,
    ) operation,
  ) =>
      coordinator.run<bool>(
        key,
        () => mutateMessagesInHive(box, key, operation),
      );

  List<Map<String, dynamic>> read() {
    final raw = box.get(key);
    if (raw is! List) return [];
    return raw
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('fenyvo_505_');
    Hive.init(sandbox.path);
    box = await Hive.openBox('atomic_mutation_505');
    coordinator = MessageWriteCoordinator();

    await persistMessagesToHive(
      box,
      key,
      [message('read')],
    );
  });

  tearDown(() async {
    await Hive.close();
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('edit keeps current read status', () async {
    final changed = await mutate((current) {
      current.single['text'] = 'edited';
      return current;
    });

    expect(changed, isTrue);
    expect(read().single['status'], 'read');
    expect(read().single['text'], 'edited');
  });

  test('delete does not restore removed message', () async {
    await mutate((current) {
      current.removeWhere((item) => item['id'] == 'm1');
      return current;
    });

    await mutate((current) {
      // A later operation reads the already-deleted history.
      if (current.isEmpty) return null;
      current.single['text'] = 'stale edit';
      return current;
    });

    expect(read(), isEmpty);
  });

  test('queued updates read the latest committed state', () async {
    final gate = Completer<void>();
    final entered = Completer<void>();

    final first = coordinator.run<void>(key, () async {
      entered.complete();
      await gate.future;
      await persistMessagesToHive(box, key, [message('delivered')]);
    });

    await entered.future;

    final second = mutate((current) {
      current.single['status'] = 'read';
      return current;
    });

    gate.complete();

    await first;
    expect(await second, isTrue);
    expect(read().single['status'], 'read');
  });

  test('null mutation skips writing', () async {
    final before = read();

    final changed = await mutate((current) => null);

    expect(changed, isFalse);
    expect(read(), before);
  });

  test('closed Hive box propagates an error', () async {
    await box.close();

    await expectLater(
      mutate((current) => current),
      throwsA(isA<HiveError>()),
    );
  });
}