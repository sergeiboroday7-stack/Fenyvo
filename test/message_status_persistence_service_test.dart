import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../lib/services/message_status_persistence_service.dart';

void main() {
  late List<Map<String, dynamic>> stored;
  late MessageStatusPersistenceService service;
  late int writes;

  setUp(() {
    stored = [
      <String, dynamic>{
        'id': 'm1',
        'from': 'alice',
        'to': 'bob',
        'isMe': true,
        'status': 'sent',
      },
    ];
    writes = 0;
    service = MessageStatusPersistenceService(
      loadMessages: (_, __) =>
          stored.map((item) => Map<String, dynamic>.from(item)).toList(),
      saveMessages: (_, __, messages) async {
        writes++;
        stored = messages;
      },
    );
  });

  Future<StatusPersistenceOutcome> apply(
    String type, {
    String id = 'm1',
    String from = 'alice',
    String to = 'bob',
  }) {
    return service.apply(
      currentUser: 'alice',
      peer: 'bob',
      messageId: id,
      eventType: type,
      from: from,
      to: to,
    );
  }

  test('persists delivered status', () async {
    expect(
      await apply('message_delivered'),
      StatusPersistenceOutcome.updated,
    );
    expect(stored.single['status'], 'delivered');
    expect(writes, 1);
  });

  test('persists read status', () async {
    expect(
      await apply('message_read'),
      StatusPersistenceOutcome.updated,
    );
    expect(stored.single['status'], 'read');
  });

  test('duplicate and downgrade do not write', () async {
    await apply('message_read');
    expect(
      await apply('message_read'),
      StatusPersistenceOutcome.alreadyApplied,
    );
    expect(
      await apply('message_delivered'),
      StatusPersistenceOutcome.alreadyApplied,
    );
    expect(writes, 1);
  });

  test('foreign or missing message is not stored', () async {
    expect(
      await apply('message_read', from: 'mallory'),
      StatusPersistenceOutcome.rejected,
    );
    expect(
      await apply('message_read', id: 'unknown'),
      StatusPersistenceOutcome.missing,
    );
    expect(writes, 0);
  });

  test('failed persistence propagates error', () async {
    service = MessageStatusPersistenceService(
      loadMessages: (_, __) => stored,
      saveMessages: (_, __, ___) async {
        throw StateError('disk failure');
      },
    );

    await expectLater(
      apply('message_read'),
      throwsA(isA<StateError>()),
    );
    expect(stored.single['status'], 'sent');
  });

  test('concurrent statuses serialize without downgrade', () async {
    final gate = Completer<void>();
    final firstWriteStarted = Completer<void>();
    var saveCount = 0;

    service = MessageStatusPersistenceService(
      loadMessages: (_, __) =>
          stored.map((item) => Map<String, dynamic>.from(item)).toList(),
      saveMessages: (_, __, messages) async {
        saveCount++;
        if (saveCount == 1) {
          firstWriteStarted.complete();
          await gate.future;
        }
        stored = messages;
      },
    );

    final delivered = apply('message_delivered');
    await firstWriteStarted.future;

    final read = apply('message_read');
    gate.complete();

    expect(
      await delivered,
      StatusPersistenceOutcome.updated,
    );
    expect(
      await read,
      StatusPersistenceOutcome.updated,
    );
    expect(stored.single['status'], 'read');
    expect(saveCount, 2);
  });
}