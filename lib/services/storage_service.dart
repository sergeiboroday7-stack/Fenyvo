import 'dart:io';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

import 'media_cache_service.dart';
import 'message_persistence_service.dart';
import 'message_write_coordinator.dart';
import 'message_deletion_guard.dart';
import 'message_deletion_pipeline.dart';
import 'message_local_deletion_guard.dart';
import 'message_local_deletion_pipeline.dart';
import 'message_status_hive_writer.dart';
import 'message_status_persistence_service.dart';

import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  static String _screenSecurityKey(String currentUser, String contact) {
    final owner = Uri.encodeComponent(currentUser.trim().toLowerCase());
    final peer = Uri.encodeComponent(contact.trim().toLowerCase());
    return 'screen_security_${owner}_$peer';
  }

  static Future<bool> getChatScreenSecurity(
    String currentUser,
    String contact,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_screenSecurityKey(currentUser, contact)) ?? false;
  }

  static Future<void> setChatScreenSecurity(
    String currentUser,
    String contact,
    bool enabled,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_screenSecurityKey(currentUser, contact), enabled);
  }

  static late Box _messagesBox;
  static late Box _avatarsBox;
  static late Box _unreadBox;
  static late Box _outboxBox;
  static late Box _deletedMessagesBox;
  static late Box _localDeletedMessagesBox;

  static Future<void> init() async {
    if (Platform.isWindows) {
      final supportDirectory = await getApplicationSupportDirectory();
      await supportDirectory.create(recursive: true);
      await _migrateLegacyWindowsBoxes(supportDirectory);
      Hive.init(supportDirectory.path);
    } else {
      await Hive.initFlutter();
    }

    _messagesBox = await Hive.openBox('chat_messages');

    _avatarsBox = await Hive.openBox('avatars');

    _unreadBox = await Hive.openBox('unread_messages');

    _outboxBox = await Hive.openBox('spartan_outbox');

    _deletedMessagesBox = await Hive.openBox('fenyvo_deleted_message_ids');
    _localDeletedMessagesBox = await Hive.openBox('fenyvo_local_deleted_message_ids');

    await Hive.openBox('spartan_saved_messages');
    await Hive.openBox('spartan_call_history');

    await _migrateEmbeddedMediaToFiles();

    await _reconcileDeletedMessagesOnStartup();

    print('📦 StorageService инициализирован');
  }

  static Future<void> _migrateLegacyWindowsBoxes(
    Directory supportDirectory,
  ) async {
    try {
      final legacyDirectory = await getApplicationDocumentsDirectory();
      if (legacyDirectory.path == supportDirectory.path) return;

      const boxNames = <String>[
        'chat_messages',
        'avatars',
        'unread_messages',
        'spartan_outbox',
        'spartan_saved_messages',
        'spartan_call_history',
      ];

      var migrated = 0;
      for (final boxName in boxNames) {
        final source = File(
          '${legacyDirectory.path}${Platform.pathSeparator}$boxName.hive',
        );
        final destination = File(
          '${supportDirectory.path}${Platform.pathSeparator}$boxName.hive',
        );
        if (!await destination.exists() && await source.exists()) {
          await source.copy(destination.path);
          migrated++;
        }
      }
      if (migrated > 0) {
        print('📦 Windows: перенесено локальных баз Hive: $migrated');
      }
    } catch (error) {
      // A damaged or protected legacy file must not leave the app on a white
      // screen. The new storage can still start and the old file remains intact.
      print('⚠️ Windows: старая база Hive недоступна, запускаем новую: $error');
    }
  }

  /// Complete interrupted delete-for-everyone operations before UI startup.
  ///
  /// Only chats with existing durable markers are inspected. A persistence
  /// error propagates so an unclean history is not silently displayed.
  static Future<void> _reconcileDeletedMessagesOnStartup() async {
    final guard = MessageDeletionGuard(_deletedMessagesBox);
    final affectedChats = guard.markedChatKeys();

    if (affectedChats.isEmpty) {
      return;
    }

    final pipeline = _deletionPipeline();

    for (final chatKey in affectedChats) {
      if (!_messagesBox.containsKey(chatKey)) {
        continue;
      }

      await pipeline.reconcile(chatKey: chatKey);
    }
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

  /// Persist chat messages and wait for Hive to finish the write.
  ///
  /// Intended for operations that require persistence confirmation,
  /// such as a future client-side status ACK protocol.
  static final MessageWriteCoordinator _durableMessageWriteCoordinator =
      MessageWriteCoordinator();

  static Future<void> saveMessagesDurable(
    String currentUser,
    String targetUser,
    List<Map<String, dynamic>> messages,
  ) async {
    final key = _getChatKey(currentUser, targetUser);
    await _durableMessageWriteCoordinator.run<void>(
      key,
      () => persistMessagesToHive(_messagesBox, key, messages),
    );
  }
  /// Persist an outgoing delivery/read status without opening its chat.
  ///
  /// Uses the same per-chat write queue as saveMessagesDurable.
  /// This method does not send a network ACK.
  static Future<StatusPersistenceOutcome> applyMessageStatusDurable({
    required String currentUser,
    required String peer,
    required String messageId,
    required String eventType,
    required String from,
    required String to,
  }) async {
    final owner = currentUser.trim();
    final contact = peer.trim();

    if (owner.isEmpty || contact.isEmpty || messageId.trim().isEmpty) {
      return StatusPersistenceOutcome.rejected;
    }

    final key = _getChatKey(owner, contact);

    final writer = MessageStatusHiveWriter(
      box: _messagesBox,
      coordinator: _durableMessageWriteCoordinator,
    );

    return writer.apply(
      key: key,
      currentUser: owner,
      peer: contact,
      messageId: messageId,
      eventType: eventType,
      from: from,
      to: to,
    );
  }
  /// Apply a change to the latest persisted chat history.
  ///
  /// The read, mutation and write share the durable message queue.
  /// Callers must supply a mutation rather than a stale full snapshot.
  static Future<bool> mutateMessagesDurably(
    String currentUser,
    String targetUser,
    List<Map<String, dynamic>>? Function(
      List<Map<String, dynamic>> current,
    ) mutate,
  ) async {
    final owner = currentUser.trim();
    final peer = targetUser.trim();

    if (owner.isEmpty || peer.isEmpty || owner == peer) {
      return false;
    }

    final key = _getChatKey(owner, peer);

    return _durableMessageWriteCoordinator.run<bool>(
      key,
      () => mutateMessagesInHive(_messagesBox, key, mutate),
    );
  }
  /// Append to the latest persisted chat history using the shared queue.
  ///
  /// Returns false for duplicate or invalid messages.
  /// Deleted-message replay protection is handled separately.
  static MessageDeletionPipeline _deletionPipeline() {
    return MessageDeletionPipeline(
      messagesBox: _messagesBox,
      guard: MessageDeletionGuard(_deletedMessagesBox),
      coordinator: _durableMessageWriteCoordinator,
    );
  }

  /// Persist incoming/outgoing message only if its ID is not deleted.
  ///
  /// False means no append occurred, or recovery-only work was performed.
  /// Do not interpret this result as a server delivery ACK.
  static Future<bool> appendMessageDurably(
    String currentUser,
    String targetUser,
    Map<String, dynamic> incoming, {
    Future<bool> Function()? allowAppend,
  }) async {
    final owner = currentUser.trim();
    final peer = targetUser.trim();

    if (owner.isEmpty || peer.isEmpty || owner == peer) {
      return false;
    }

    final from = incoming['from']?.toString().trim() ?? '';
    final to = incoming['to']?.toString().trim() ?? '';
    final id = incoming['id']?.toString().trim() ?? '';
    final time = incoming['time']?.toString().trim() ?? '';
    final text = incoming['text']?.toString() ?? '';

    // Legacy clients may omit the ID. Retain their established
    // time/from/to/text duplicate identity.
    if ((id.isEmpty && (time.isEmpty || text.isEmpty)) ||
        !((from == owner && to == peer) ||
          (from == peer && to == owner))) {
      return false;
    }

    return _deletionPipeline().append(
      chatKey: _getChatKey(owner, peer),
      incoming: Map<String, dynamic>.from(incoming),
      allowAppend: allowAppend,
    );
  }

  /// Owner-only message visibility, separate from delete-for-everyone.
  static MessageLocalDeletionPipeline _localDeletionPipeline() {
    return MessageLocalDeletionPipeline(
      messagesBox: _messagesBox,
      guard: MessageLocalDeletionGuard(_localDeletedMessagesBox),
      coordinator: _durableMessageWriteCoordinator,
    );
  }

  /// Persist a hide marker for an existing message for this owner only.
  /// The shared chat history is not physically removed.
  static Future<bool> hideMessageForMeDurably({
    required String currentUser,
    required String peer,
    required String messageId,
  }) {
    final owner = currentUser.trim();
    final contact = peer.trim();
    final id = messageId.trim();

    if (owner.isEmpty ||
        contact.isEmpty ||
        owner == contact ||
        id.isEmpty) {
      return Future<bool>.value(false);
    }

    return _localDeletionPipeline().hideForOwner(
      chatKey: _getChatKey(owner, contact),
      owner: owner,
      peer: contact,
      messageId: id,
    );
  }

  /// Query whether a message is hidden for this account.
  static bool isMessageHiddenForMe({
    required String currentUser,
    required String peer,
    required String messageId,
  }) {
    return _localDeletionPipeline().isHiddenForOwner(
      owner: currentUser,
      peer: peer,
      messageId: messageId,
    );
  }

  /// Read chat history while respecting this account's hide markers.
  /// The existing getMessages API remains unchanged.
  static List<Map<String, dynamic>> getMessagesVisibleForOwner(
    String currentUser,
    String targetUser,
  ) {
    return _localDeletionPipeline().visibleForOwner(
      owner: currentUser,
      peer: targetUser,
      messages: getMessages(currentUser, targetUser),
    );
  }
  /// Call only for a validated delete-for-everyone event.
  ///
  /// This checks chat identity, not server event authenticity.
  /// The caller must establish that the server authorized the deletion.
  static Future<bool> deleteForEveryoneDurably({
    required String currentUser,
    required String peer,
    required String messageId,
    required String from,
    required String to,
  }) async {
    final owner = currentUser.trim();
    final contact = peer.trim();
    final id = messageId.trim();
    final sender = from.trim();
    final recipient = to.trim();

    if (owner.isEmpty ||
        contact.isEmpty ||
        owner == contact ||
        id.isEmpty ||
        !((sender == owner && recipient == contact) ||
          (sender == contact && recipient == owner))) {
      return false;
    }

    return _deletionPipeline().deleteForEveryone(
      chatKey: _getChatKey(owner, contact),
      messageId: id,
    );
  }

  /// Repair an interruption between marker write and history deletion.
  static Future<bool> reconcileDeletedMessagesDurably(
    String currentUser,
    String targetUser,
  ) async {
    final owner = currentUser.trim();
    final peer = targetUser.trim();

    if (owner.isEmpty || peer.isEmpty || owner == peer) {
      return false;
    }

    return _deletionPipeline().reconcile(
      chatKey: _getChatKey(owner, peer),
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

  static bool updateMessagePinnedState(
    String currentUser,
    String targetUser,
    String messageId,
    bool pinned,
  ) {
    final user = currentUser.trim();
    final peer = targetUser.trim();
    final id = messageId.trim();
    if (user.isEmpty || peer.isEmpty || id.isEmpty) {
      return false;
    }

    final key = _getChatKey(user, peer);
    final rawData = _messagesBox.get(key);
    if (rawData is! List) {
      return false;
    }

    final messages = <Map<String, dynamic>>[];
    var changed = false;
    for (final rawItem in rawData) {
      if (rawItem is! Map) {
        continue;
      }
      final message = Map<String, dynamic>.from(rawItem);
      if (_getStoredMessageId(message) == id) {
        final wasPinned = message['isPinned'] == true;
        if (wasPinned != pinned) {
          message['isPinned'] = pinned;
          changed = true;
        }
      }
      messages.add(message);
    }

    if (changed) {
      _messagesBox.put(key, messages);
      print('📌 Состояние закрепления сохранено: $id = $pinned');
    }
    return changed;
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
  // ИСХОДЯЩАЯ ОЧЕРЕДЬ ТЕКСТОВЫХ СООБЩЕНИЙ
  // ========================================

  static List<Map<String, dynamic>> getOutboxMessages(String currentUser) {
    final user = currentUser.trim();
    if (user.isEmpty) return <Map<String, dynamic>>[];
    final raw = _outboxBox.get(user);
    if (raw is! List) return <Map<String, dynamic>>[];
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .where((item) => (item['id']?.toString().trim() ?? '').isNotEmpty)
        .toList();
  }

  static void saveOutboxMessage(
    String currentUser,
    Map<String, dynamic> message,
  ) {
    final user = currentUser.trim();
    final id = message['id']?.toString().trim() ?? '';
    if (user.isEmpty || id.isEmpty) return;
    final messages = getOutboxMessages(user)
      ..removeWhere((item) => item['id']?.toString().trim() == id)
      ..add(Map<String, dynamic>.from(message));
    _outboxBox.put(user, messages);
    print('📤 Сообщение добавлено в исходящую очередь: $id');
  }

  static void updateOutboxStatus(
    String currentUser,
    String messageId,
    String status,
  ) {
    final user = currentUser.trim();
    final id = messageId.trim();
    if (user.isEmpty || id.isEmpty) return;
    final messages = getOutboxMessages(user);
    var changed = false;
    for (final message in messages) {
      if (message['id']?.toString().trim() == id) {
        message['status'] = status;
        changed = true;
      }
    }
    if (changed) _outboxBox.put(user, messages);
  }

  static void removeOutboxMessage(String currentUser, String messageId) {
    final user = currentUser.trim();
    final id = messageId.trim();
    if (user.isEmpty || id.isEmpty) return;
    final messages = getOutboxMessages(user)
      ..removeWhere((item) => item['id']?.toString().trim() == id);
    if (messages.isEmpty) {
      _outboxBox.delete(user);
    } else {
      _outboxBox.put(user, messages);
    }
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
