// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:fenyvo/services/saved_messages_service.dart';
import 'package:fenyvo/widgets/emoji_picker.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory sandbox;
  setUpAll(() async {
    sandbox = await Directory.systemTemp.createTemp('spartan_saved_test_');
    PathProviderPlatform.instance = _Paths(sandbox.path);
    Hive.init(sandbox.path);
    await Hive.openBox('spartan_saved_messages');
  });
  tearDownAll(() async {
    await Hive.close();
    await sandbox.delete(recursive: true);
  });
  test('emoji replaces selected text and preserves a UTF-16 caret', () {
    final input = TextEditingController(text: 'Привет друг');
    input.selection = const TextSelection(baseOffset: 7, extentOffset: 11);
    insertComposerEmoji(input, '👋');
    expect(input.text, 'Привет 👋');
    expect(input.selection.baseOffset, input.text.length);
    input.selection = const TextSelection.collapsed(offset: 0);
    insertComposerEmoji(input, '❤️');
    expect(input.text, '❤️Привет 👋');
    input.selection = const TextSelection.collapsed(offset: -1);
    insertComposerEmoji(input, '😊');
    expect(input.text, '❤️Привет 👋😊');
    input.dispose();
  });
  test(
    'saved messages deduplicate, isolate accounts and survive reopening',
    () async {
      final source = {
        'id': 'original',
        'from': 'Sparta',
        'text': 'Важное',
        'messageType': 'text',
      };
      await SavedMessagesService.save('Acer', source, origin: 'Sparta');
      await SavedMessagesService.save('Acer', source, origin: 'Sparta');
      expect(SavedMessagesService.items('Acer'), hasLength(1));
      expect(SavedMessagesService.items('Alla'), isEmpty);
      expect(source, {
        'id': 'original',
        'from': 'Sparta',
        'text': 'Важное',
        'messageType': 'text',
      });
      await Hive.box('spartan_saved_messages').close();
      await Hive.openBox('spartan_saved_messages');
      expect(SavedMessagesService.items('Acer').single['text'], 'Важное');
      await SavedMessagesService.save('Alla', source, origin: 'Sparta');
      await SavedMessagesService.remove(
        'Acer',
        SavedMessagesService.items('Acer').single['id'].toString(),
      );
      expect(SavedMessagesService.items('Acer'), isEmpty);
      expect(SavedMessagesService.items('Alla'), hasLength(1));
    },
  );
  test(
    'saved media is an independent copy and removing it leaves the source',
    () async {
      final original = File('${sandbox.path}/fixture.png');
      await original.writeAsBytes([1, 2, 3, 4]);
      await SavedMessagesService.save('MediaOwner', {
        'id': 'photo',
        'messageType': 'image',
        'localMediaPath': original.path,
        'fileName': 'fixture.png',
        'mimeType': 'image/png',
      }, origin: 'Sparta');
      final item = SavedMessagesService.items('MediaOwner').single;
      final copy = File(item['localMediaPath'].toString());
      expect(copy.path, isNot(original.path));
      expect(await copy.readAsBytes(), [1, 2, 3, 4]);
      await SavedMessagesService.remove('MediaOwner', item['id'].toString());
      expect(await original.exists(), isTrue);
      expect(SavedMessagesService.items('MediaOwner'), isEmpty);
    },
  );
  test('cannot create unauthenticated saved entry', () async {
    await expectLater(
      SavedMessagesService.save('', {'text': 'secret'}),
      throwsStateError,
    );
    expect(SavedMessagesService.items(''), isEmpty);
  });
}
