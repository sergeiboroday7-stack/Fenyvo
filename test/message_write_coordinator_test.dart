import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../lib/services/message_write_coordinator.dart';
import '../lib/services/message_persistence_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late MessageWriteCoordinator coordinator;
  late Directory sandbox;
  late Box box;

  Map<String, dynamic> message(String status) =>
      <String, dynamic>{
        'id': 'm1',
        'from': 'alice',
        'to': 'bob',
        'status': status,
        'text': 'hello',
      };

  setUp(() async {
    coordinator = MessageWriteCoordinator();
    sandbox = await Directory.systemTemp.createTemp('fenyvo_step500_');
    Hive.init(sandbox.path);
    box = await Hive.openBox('step500_chat');
  });

  tearDown(() async {
    await Hive.close();
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('same-key operations execute in order', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    final events = <String>[];

    final first = coordinator.run<void>('chat', () async {
      events.add('first-start');
      started.complete();
      await gate.future;
      events.add('first-end');
    });

    await started.future;

    final second = coordinator.run<void>('chat', () async {
      events.add('second');
    });

    await Future<void>.delayed(Duration.zero);
    expect(events, ['first-start']);

    gate.complete();
    await Future.wait([first, second]);

    expect(events, ['first-start', 'first-end', 'second']);
  });

  test('different keys are independent', () async {
    final gate = Completer<void>();
    final started = Completer<void>();
    var secondCompleted = false;

    final first = coordinator.run<void>('chat-a', () async {
      started.complete();
      await gate.future;
    });

    await started.future;

    await coordinator.run<void>('chat-b', () async {
      secondCompleted = true;
    });

    expect(secondCompleted, isTrue);

    gate.complete();
    await first;
  });

  test('failed operation does not block following operation', () async {
    await expectLater(
      coordinator.run<void>('chat', () async {
        throw StateError('simulated write failure');
      }),
      throwsA(isA<StateError>()),
    );

    final value = await coordinator.run<int>('chat', () async => 42);
    expect(value, 42);
  });

  test('serialized Hive writes preserve read status', () async {
    final gate = Completer<void>();
    final started = Completer<void>();

    final first = coordinator.run<void>('alice_bob', () async {
      started.complete();
      await gate.future;
      await persistMessagesToHive(
        box,
        'alice_bob',
        [message('read')],
      );
    });

    await started.future;

    final second = coordinator.run<void>('alice_bob', () async {
      await persistMessagesToHive(
        box,
        'alice_bob',
        [message('sent')],
      );
    });

    gate.complete();
    await Future.wait([first, second]);

    await box.close();
    box = await Hive.openBox('step500_chat');

    final raw = box.get('alice_bob') as List;
    final saved = Map<String, dynamic>.from(raw.single as Map);

    expect(saved['status'], 'read');
  });

  test('queued delete executes after preceding write', () async {
    final first = coordinator.run<void>('alice_bob', () async {
      await persistMessagesToHive(
        box,
        'alice_bob',
        [message('sent')],
      );
    });

    final second = coordinator.run<void>('alice_bob', () async {
      await box.delete('alice_bob');
    });

    await Future.wait([first, second]);
    expect(box.containsKey('alice_bob'), isFalse);
  });
}