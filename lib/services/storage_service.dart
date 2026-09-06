import 'package:hive_flutter/hive_flutter.dart';

import 'media_cache_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static late Box _messagesBox;
  static late Box _avatarsBox;
  static late Box _unreadBox;

  static Future<void> init() async {
    await Hive.initFlutter();

    _messagesBox = await Hive.openBox('chat_messages');

    _avatarsBox = await Hive.openBox('avatars');

    _unreadBox = await Hive.openBox('unread_messages');

    await Hive.openBox('spartan_saved_messages');
    await Hive.openBox('spartan_call_history');

    await _migrateEmbeddedMediaToFiles();

    print('📦 StorageService инициализирован');
  }

  static Future<void> _migrateEmbeddedMediaToFiles() async {
    var migrated = 0;

    for (final key in _messagesBox.keys.toList()) {
      final rawData = _messagesBox.get(key);
      if (rawData is! List) continue;

      final compacted = <Map<String, dynamic>>[];
      var changed = false;

      for (final item in rawData) {
        if (item is! Map) continue;
        final original = Map<String, dynamic>.from(item);
        var message = original;

        if (MediaCacheService.hasEmbeddedData(original)) {
          try {
            message = await MediaCacheService.cacheEmbeddedMedia(original);
            final localPath =
                message['localMediaPath']?.toString().trim() ?? '';
            if (localPath.isNotEmpty) {
              migrated++;
              changed = true;
            }
          } catch (error) {
            print('⚠️ Не удалось вынести медиа из Hive: $error');
          }
        }

        compacted.add(message);
      }

      if (changed) {
        await _messagesBox.put(key, compacted);
      }
    }

    if (migrated > 0) {
      print('⚡ Медиа вынесено из Hive в файлы: $migrated');
    }
  }

  static String _getChatKey(String user1, String user2) {
    final users = [user1, user2]..sort();

    return users.join('_');
  }

  static String _getUnreadKey(String currentUser, String targetUser) {
    return '${currentUser}_$targetUser';
  }

  static String _getStoredMessageId(Map<String, dynamic> message) {
    final id = message['id']?.toString().trim() ?? '';

    if (id.isNotEmpty) {
      return id;
    }

    final from = message['from']?.toString() ?? '';
    final to = message['to']?.toString() ?? '';
    final time = message['time']?.toString() ?? '';
    final text = message['text']?.toString() ?? '';

    return 'legacy:'
        '${Uri.encodeComponent(from)}:'
        '${Uri.encodeComponent(to)}:'
        '${Uri.encodeComponent(time)}:'
        '${Uri.encodeComponent(text)}';
  }

  // ========================================
  // СООБЩЕНИЯ
  // ========================================

  static void saveMessages(
    String currentUser,
    String targetUser,
    List<Map<String, dynamic>> messages,
  ) {
    final key = _getChatKey(currentUser, targetUser);

    final messagesToSave = <Map<String, dynamic>>[];

    for (final message in messages) {
      final copy = Map<String, dynamic>.from(message);
      final localPath = copy['localMediaPath']?.toString().trim() ?? '';
      if (localPath.isNotEmpty) {
        copy.remove('mediaData');
        copy.remove('voiceData');
      }
      messagesToSave.add(copy);
    }

    _messagesBox.put(key, messagesToSave);

    print(
      '💾 Сохранено '
      '${messagesToSave.length} '
      'сообщений для чата $key',
    );
  }

  static List<Map<String, dynamic>> getMessages(
    String currentUser,
    String targetUser,
  ) {
    final key = _getChatKey(currentUser, targetUser);

    if (!_messagesBox.containsKey(key)) {
      return [];
    }

    final rawData = _messagesBox.get(key);

    if (rawData is! List) {
      return [];
    }

    final messages = <Map<String, dynamic>>[];

    for (final item in rawData) {
      if (item is Map) {
        messages.add(Map<String, dynamic>.from(item));
      }
    }

    print(
      '📂 Загружено '
      '${messages.length} '
      'сообщений для чата $key',
    );

    return messages;
  }

  static bool deleteMessageWithoutTrace(
    String currentUser,
    String targetUser,
    String messageId,
  ) {
    final id = messageId.trim();

    if (currentUser.trim().isEmpty || targetUser.trim().isEmpty || id.isEmpty) {
      return false;
    }

    final key = _getChatKey(currentUser, targetUser);

    final rawData = _messagesBox.get(key);

    if (rawData is! List) {
      return false;
    }

    final messagesToSave = <Map<String, dynamic>>[];
    var changed = false;

    for (final rawItem in rawData) {
      if (rawItem is! Map) {
        continue;
      }

      final message = Map<String, dynamic>.from(rawItem);

      if (_getStoredMessageId(message) == id) {
        changed = true;
        continue;
      }

      final rawReply = message['replyTo'];

      if (rawReply is Map) {
        final replyId = rawReply['id']?.toString().trim() ?? '';

        if (replyId == id) {
          message.remove('replyTo');
          changed = true;
        }
      }

      messagesToSave.add(message);
    }

    if (!changed) {
      return false;
    }

    _messagesBox.put(key, messagesToSave);

    print('🧹 Сообщение удалено без следов: $id');

    return true;
  }

  static String _getPinnedMessageKey(String currentUser, String targetUser) {
    return 'pinned_message_${_getChatKey(currentUser, targetUser)}';
  }

  static void savePinnedMessages(
    String currentUser,
    String targetUser,
    List<Map<String, dynamic>> messages,
  ) {
    _avatarsBox.put(
      _getPinnedMessageKey(currentUser, targetUser),
      messages.map((message) => Map<String, dynamic>.from(message)).toList(),
    );
  }

  static List<Map<String, dynamic>> getPinnedMessages(
    String currentUser,
    String targetUser,
  ) {
    final raw = _avatarsBox.get(_getPinnedMessageKey(currentUser, targetUser));

    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    // Совместимость с первой версией,
    // где закрепление было только одно.
    if (raw is Map) {
      return [Map<String, dynamic>.from(raw)];
    }

    return <Map<String, dynamic>>[];
  }

  static void addPinnedMessage(
    String currentUser,
    String targetUser,
    Map<String, dynamic> message,
  ) {
    final messageId = message['messageId']?.toString().trim() ?? '';

    if (messageId.isEmpty) {
      return;
    }

    final pinned = getPinnedMessages(
      currentUser,
      targetUser,
    )..removeWhere((item) => item['messageId']?.toString().trim() == messageId);

    pinned.insert(0, Map<String, dynamic>.from(message));

    savePinnedMessages(currentUser, targetUser, pinned);
  }

  static void removePinnedMessage(
    String currentUser,
    String targetUser,
    String messageId,
  ) {
    final id = messageId.trim();

    if (id.isEmpty) {
      return;
    }

    final pinned = getPinnedMessages(currentUser, targetUser)
      ..removeWhere((item) => item['messageId']?.toString().trim() == id);

    if (pinned.isEmpty) {
      _avatarsBox.delete(_getPinnedMessageKey(currentUser, targetUser));
      return;
    }

    savePinnedMessages(currentUser, targetUser, pinned);
  }

  // ========================================
  // СПИСОК ЧАТОВ
  // ========================================

  static List<String> getChatUsers(String currentUser) {
    final users = <String>{};

    for (final key in _messagesBox.keys) {
      final keyString = key.toString();

      final parts = keyString.split('_');

      if (parts.length != 2) {
        continue;
      }

      if (parts[0] == currentUser) {
        users.add(parts[1]);
      }

      if (parts[1] == currentUser) {
        users.add(parts[0]);
      }
    }

    return users.toList();
  }

  // ========================================
  // АВАТАРКИ
  // ========================================

  static void saveAvatar(String username, String avatarBase64) {
    _avatarsBox.put(username, avatarBase64);

    print('🖼️ Аватарка сохранена для $username');
  }

  static String? getAvatar(String username) {
    final avatar = _avatarsBox.get(username);

    if (avatar == null) {
      return null;
    }

    final value = avatar.toString();

    if (value.isEmpty) {
      return null;
    }

    return value;
  }

  static Future<void> removeAvatar(String username) async {
    await _avatarsBox.delete(username);

    print('🗑️ Аватарка удалена для $username');
  }

  // ========================================
  // НЕПРОЧИТАННЫЕ СООБЩЕНИЯ
  // ========================================

  static int getUnreadCount(String currentUser, String targetUser) {
    final key = _getUnreadKey(currentUser, targetUser);

    final value = _unreadBox.get(key, defaultValue: 0);

    if (value is int) {
      return value;
    }

    return 0;
  }

  static void incrementUnreadCount(String currentUser, String targetUser) {
    final currentCount = getUnreadCount(currentUser, targetUser);

    final key = _getUnreadKey(currentUser, targetUser);

    _unreadBox.put(key, currentCount + 1);

    print(
      '🔴 Непрочитанных от '
      '$targetUser: '
      '${currentCount + 1}',
    );
  }

  static void clearUnreadCount(String currentUser, String targetUser) {
    final key = _getUnreadKey(currentUser, targetUser);

    _unreadBox.put(key, 0);

    print(
      '✅ Счётчик '
      '$targetUser очищен',
    );
  }

  // ========================================
  // ФОН ЧАТА
  // ========================================

  /// An old dark-theme wallpaper stays on disk, but is opt-in in the light theme.
  static Future<bool> isLightWallpaperEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('light_theme_wallpaper_enabled') ?? false;
  }

  static Future<void> setLightWallpaperEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('light_theme_wallpaper_enabled', enabled);
  }

  static Future<String?> getLightBackground() async {
    return await isLightWallpaperEnabled() ? getBackground() : null;
  }

  static Future<String?> getBackground() async {
    final prefs = await SharedPreferences.getInstance();

    final path = prefs.getString('chat_background');

    if (path == null || path.isEmpty) {
      return null;
    }

    return path;
  }

  static Future<void> saveBackground(String path) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('chat_background', path);

    print('🖼️ Фон чата сохранён');
  }

  static Future<void> removeBackground() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('chat_background');

    print('🗑️ Пользовательский фон удалён');
  }

  // ========================================
  // ПРОЗРАЧНОСТЬ ФОНА
  // ========================================

  static Future<double> getBackgroundOpacity() async {
    final prefs = await SharedPreferences.getInstance();

    final value = prefs.getDouble('chat_background_opacity');

    if (value == null) {
      return 0.35;
    }

    return value.clamp(0.0, 1.0);
  }

  static Future<void> saveBackgroundOpacity(double opacity) async {
    final prefs = await SharedPreferences.getInstance();

    final safeValue = opacity.clamp(0.0, 1.0);

    await prefs.setDouble('chat_background_opacity', safeValue);

    print(
      '🌗 Прозрачность фона: '
      '${(safeValue * 100).round()}%',
    );
  }

  // ========================================
  // ЦВЕТ ТЕКСТА
  // ========================================

  static Future<int> getTextColor() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getInt('text_color') ?? 0xFFFFFFFF;
  }

  static Future<void> saveTextColor(int color) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt('text_color', color);
  }

  // ========================================
  // ЗАКРЕПЛЁННЫЕ ЧАТЫ
  // ========================================

  static void savePinnedChats(String currentUser, List<String> pinnedChats) {
    final key = 'pinned_${currentUser}_chats';

    _avatarsBox.put(key, pinnedChats);
  }

  static List<String> getPinnedChats(String currentUser) {
    final key = 'pinned_${currentUser}_chats';

    final data = _avatarsBox.get(key);

    if (data is List) {
      return List<String>.from(data);
    }

    return [];
  }

  static void togglePinChat(String currentUser, String targetUser) {
    final pinned = getPinnedChats(currentUser);

    if (pinned.contains(targetUser)) {
      pinned.remove(targetUser);
    } else {
      pinned.insert(0, targetUser);
    }

    savePinnedChats(currentUser, pinned);
  }

  // ========================================
  // БЕЗ ЗВУКА
  // ========================================

  static Future<bool> isChatMuted(String currentUser, String contact) async {
    final prefs = await SharedPreferences.getInstance();

    final key = 'muted_${currentUser}_$contact';

    return prefs.getBool(key) ?? false;
  }

  static Future<void> setChatMuted(
    String currentUser,
    String contact,
    bool muted,
  ) async {
    final prefs = await SharedPreferences.getInstance();

    final key = 'muted_${currentUser}_$contact';

    await prefs.setBool(key, muted);
  }

  // ========================================
  // УДАЛЕНИЕ ЧАТА
  // ========================================

  static Future<void> removeChat(String currentUser, String targetUser) async {
    final chatKey = _getChatKey(currentUser, targetUser);

    await _messagesBox.delete(chatKey);

    final unreadKey = _getUnreadKey(currentUser, targetUser);

    await _unreadBox.delete(unreadKey);

    final pinned = getPinnedChats(currentUser);

    if (pinned.contains(targetUser)) {
      pinned.remove(targetUser);

      savePinnedChats(currentUser, pinned);
    }

    await setChatMuted(currentUser, targetUser, false);

    print(
      '🗑️ Чат '
      '$currentUser - '
      '$targetUser удалён',
    );
  }
}
