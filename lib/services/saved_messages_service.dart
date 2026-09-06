import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'media_cache_service.dart';

/// Local-only, per-account copies. Never sends a message or mutates the source chat.
class SavedMessagesService {
  static final changes = ValueNotifier<int>(0);
  static Future<void> _queue = Future<void>.value();
  static Box get _box => Hive.box('spartan_saved_messages');
  static List<Map<String, dynamic>> items(String owner) {
    final raw = _box.get(owner);
    return raw is List
        ? raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
        : [];
  }

  static Future<void> _serialize(Future<void> Function() action) {
    final next = _queue.then((_) => action());
    _queue = next.then<void>((_) {}, onError: (Object _, StackTrace trace) {});
    return next;
  }

  static Future<void> save(
    String owner,
    Map<String, dynamic> source, {
    String origin = '',
  }) => _serialize(() async {
    if (owner.trim().isEmpty) throw StateError('Сначала войдите в аккаунт');
    final sourceId = source['id']?.toString() ?? '';
    final list = items(owner);
    final sourceKey = jsonEncode([origin, sourceId]);
    if (sourceId.isNotEmpty && list.any((e) => e['sourceKey'] == sourceKey))
      return;
    var message = Map<String, dynamic>.from(source);
    final type = message['messageType']?.toString() ?? 'text';
    final media = ['voice', 'image', 'video', 'file'].contains(type);
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    String? savedPath;
    if (media) {
      message = await MediaCacheService.cacheRemoteMedia(message);
      final local = MediaCacheService.existingLocalPath(message);
      if (local == null)
        throw StateError(
          'Вложение недоступно. Загрузите его и повторите сохранение.',
        );
      final root = await getApplicationSupportDirectory();
      final account = base64Url.encode(utf8.encode(owner)).replaceAll('=', '');
      final directory = Directory(
        '${root.path}${Platform.pathSeparator}spartan_saved_media${Platform.pathSeparator}$account',
      );
      await directory.create(recursive: true);
      final match = RegExp(r'\.[a-zA-Z0-9]{1,8}$').firstMatch(local);
      final extension = match?.group(0) ?? '.bin';
      savedPath = '${directory.path}${Platform.pathSeparator}$id$extension';
      await File(local).copy(savedPath);
    }
    list.insert(0, {
      'id': id,
      'sourceKey': sourceId.isEmpty ? id : sourceKey,
      'origin': origin,
      'from': source['from']?.toString() ?? owner,
      'text': source['text']?.toString() ?? '',
      'messageType': type,
      'fileName': source['fileName']?.toString() ?? '',
      'mimeType':
          source['mimeType']?.toString() ??
          source['voiceMimeType']?.toString() ??
          '',
      'savedAt': DateTime.now().toIso8601String(),
      if (savedPath != null) 'localMediaPath': savedPath,
    });
    await _box.put(owner, list);
    changes.value++;
  });
  static Future<void> remove(String owner, String id) => _serialize(() async {
    final list = items(owner)..removeWhere((e) => e['id'] == id);
    // Remove only the saved entry. Original messages and files are never deleted.
    await _box.put(owner, list);
    changes.value++;
  });
}
