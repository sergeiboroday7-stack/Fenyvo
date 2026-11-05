import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../lib/services/message_persistence_service.dart';
import '../lib/services/message_status_hive_writer.dart';
import '../lib/services/message_status_persistence_service.dart';
import '../lib/services/message_write_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late Box box;
  late MessageWriteCoordinator coordinator;
  late MessageStatusHiveWriter writer;

  const key = 'alice_bob';

  Map<String, dynamic> message(String status) =>
      <String, dynamic>{
        'id': 'm1',
        'from': 'alice',
        'to': 'bob',
        'isMe': true,
        'status': status,
        'text': 'hello',
      };

  Future<StatusPersistenceOutcome> apply(
    String type, {
    String from = 'alice',
    String to = 'bob',
    String id = 'm1',
  }) =>
      writer.apply(
        key: key,
        currentUser: 'alice',
        peer: 'bob',
        messageId: id,
        eventType: type,
        from: from,
        to: to,
      );

  String? status() {
    final raw = box.get(key);
    if (raw is! List || raw.isEmpty) return null;
    return (raw.single as Map)['status']?.toString();
  }

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('fenyvo_502_');
    Hive.init(sandbox.path);
    box = await Hive.openBox('status_hive_502');
    coordinator = MessageWriteCoordinator();
    writer = MessageStatusHiveWriter(
      box: box,
      coordinator: coordinator,
    );
    await persistMessagesToHive(box, key, [message('sent')]);
  });

  tearDown(() async {
    await Hive.close();
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('delivered is persisted', () async {
    expect(
      await apply('message_delivered'),
      StatusPersistenceOutcome.updated,
    );
    expect(status(), 'delivered');
  });

  test('read survives database reopen', () async {
    expect(
      await apply('message_read'),
      StatusPersistenceOutcome.updated,
    );

    await box.close();
    box = await Hive.openBox('status_hive_502');

    expect(status(), 'read');
  });

  test('duplicate and downgrade are ignored', () async {
    await apply('message_read');

    expect(
      await apply('message_read'),
      StatusPersistenceOutcome.alreadyApplied,
    );
    expect(
      await apply('message_delivered'),
      StatusPersistenceOutcome.alreadyApplied,
    );
    expect(status(), 'read');
  });

  test('foreign and missing status events are rejected', () async {
    expect(
      await apply('message_read', from: 'mallory'),
      StatusPersistenceOutcome.rejected,
    );
    expect(
      await apply('message_read', id: 'missing'),
      StatusPersistenceOutcome.missing,
    );
    expect(status(), 'sent');
  });

  test('queued write precedes status update', () async {
    final gate = Completer<void>();
    final started = Completer<void>();

    final initial = coordinator.run<void>(key, () async {
      started.complete();
      await gate.future;
      await persistMessagesToHive(box, key, [message('delivered')]);
    });

    await started.future;

    final read = apply('message_read');
    gate.complete();

    await initial;
    expect(await read, StatusPersistenceOutcome.updated);
    expect(status(), 'read');
  });

  test('deletion before status does not resurrect a message', () async {
    await coordinator.run<void>(key, () => box.delete(key));

    expect(
      await apply('message_read'),
      StatusPersistenceOutcome.missing,
    );
    expect(box.containsKey(key), isFalse);
  });

  test('closed Hive box propagates an error', () async {
    await box.close();

    await expectLater(
      apply('message_read'),
      throwsA(isA<HiveError>()),
    );
  });
}