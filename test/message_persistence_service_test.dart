import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:fenyvo/services/message_persistence_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory sandbox;
  late Box box;

  setUp(() async {
    sandbox = await Directory.systemTemp.createTemp('fenyvo_hive_491_');
    Hive.init(sandbox.path);
    box = await Hive.openBox('status_test_491');
  });

  tearDown(() async {
    await Hive.close();
    if (await sandbox.exists()) {
      await sandbox.delete(recursive: true);
    }
  });

  test('writes and persists messages after reopen', () async {
    await persistMessagesToHive(box, 'alice_bob', [
      <String, dynamic>{
        'id': 'm1',
        'text': 'test',
        'status': 'read',
      },
    ]);

    await box.close();
    box = await Hive.openBox('status_test_491');

    final raw = box.get('alice_bob') as List;
    final message = Map<String, dynamic>.from(raw.single as Map);

    expect(message['id'], 'm1');
    expect(message['status'], 'read');
  });

  test('removes embedded media only when cached locally', () async {
    await persistMessagesToHive(box, 'alice_bob', [
      <String, dynamic>{
        'id': 'm2',
        'localMediaPath': 'cached-file',
        'mediaData': 'embedded',
        'voiceData': 'embedded-voice',
        'fileName': 'photo.jpg',
      },
    ]);

    final raw = box.get('alice_bob') as List;
    final message = Map<String, dynamic>.from(raw.single as Map);

    expect(message.containsKey('mediaData'), isFalse);
    expect(message.containsKey('voiceData'), isFalse);
    expect(message['fileName'], 'photo.jpg');
  });

  test('preserves embedded media without local cache', () async {
    await persistMessagesToHive(box, 'alice_bob', [
      <String, dynamic>{
        'id': 'm3',
        'mediaData': 'embedded',
      },
    ]);

    final raw = box.get('alice_bob') as List;
    final message = Map<String, dynamic>.from(raw.single as Map);

    expect(message['mediaData'], 'embedded');
  });

  test('failed write propagates an error', () async {
    await box.close();

    await expectLater(
      persistMessagesToHive(box, 'alice_bob', [
        <String, dynamic>{'id': 'm4'},
      ]),
      throwsA(isA<HiveError>()),
    );
  });
}