import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import '../lib/services/message_persistence_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late Box box;

  Map<String, dynamic> message(
    String id,
    String status, {
    String text = 'original',
  }) =>
      <String, dynamic>{
        'id': id,
        'from': 'alice',
        'to': 'bob',
        'status': status,
        'text': text,
      };

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('fenyvo_498_');
    Hive.init(sandbox.path);
    box = await Hive.openBox('status_merge_498');
  });

  tearDown(() async {
    await Hive.close();
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('persisted read survives stale sent snapshot', () async {
    await persistMessagesToHive(
      box, 'alice_bob', [message('m1', 'read')],
    );

    await persistMessagesToHive(
      box, 'alice_bob', [message('m1', 'sent')],
    );

    await box.close();
    box = await Hive.openBox('status_merge_498');

    final raw = box.get('alice_bob') as List;
    final saved = Map<String, dynamic>.from(raw.single as Map);

    expect(saved['status'], 'read');
  });

  test('persisted delivered survives stale sent snapshot', () async {
    await persistMessagesToHive(
      box, 'alice_bob', [message('m1', 'delivered')],
    );

    await persistMessagesToHive(
      box, 'alice_bob', [message('m1', 'sent')],
    );

    final raw = box.get('alice_bob') as List;
    final saved = Map<String, dynamic>.from(raw.single as Map);

    expect(saved['status'], 'delivered');
  });

  test('newer read status still upgrades delivered', () async {
    await persistMessagesToHive(
      box, 'alice_bob', [message('m1', 'delivered')],
    );

    await persistMessagesToHive(
      box, 'alice_bob', [message('m1', 'read')],
    );

    final raw = box.get('alice_bob') as List;
    final saved = Map<String, dynamic>.from(raw.single as Map);

    expect(saved['status'], 'read');
  });

  test('edited text is not reverted by status protection', () async {
    await persistMessagesToHive(
      box, 'alice_bob', [message('m1', 'read')],
    );

    await persistMessagesToHive(
      box, 'alice_bob', [message('m1', 'sent', text: 'edited')],
    );

    final raw = box.get('alice_bob') as List;
    final saved = Map<String, dynamic>.from(raw.single as Map);

    expect(saved['status'], 'read');
    expect(saved['text'], 'edited');
  });

  test('deleting a message does not restore it', () async {
    await persistMessagesToHive(
      box, 'alice_bob', [message('m1', 'read')],
    );

    await persistMessagesToHive(box, 'alice_bob', []);

    final raw = box.get('alice_bob') as List;
    expect(raw, isEmpty);
  });

  test('same ID belonging to another sender is not merged', () async {
    await persistMessagesToHive(
      box, 'alice_bob', [message('m1', 'read')],
    );

    final other = message('m1', 'sent')..['from'] = 'carol';

    await persistMessagesToHive(
      box, 'alice_bob', [other],
    );

    final raw = box.get('alice_bob') as List;
    final saved = Map<String, dynamic>.from(raw.single as Map);

    expect(saved['status'], 'sent');
    expect(saved['from'], 'carol');
  });
}