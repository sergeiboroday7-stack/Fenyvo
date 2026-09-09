import '../theme/spartan_theme.dart';

import 'dart:async';

import '../services/system_call_service.dart';
import '../services/call_service.dart';
import '../services/call_history_service.dart';
import '../services/pulse_service.dart';
import '../services/spartan_trust_service.dart';
import '../widgets/spartan_brand.dart';
import 'saved_messages_screen.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/socket_service.dart';
import '../services/notification_service.dart';
import '../services/firebase_messaging_service.dart';
import '../services/storage_service.dart';
import '../settings_screen.dart';
import 'auth_screen.dart';
import 'chat_screen.dart';
import 'group_chat_screen.dart';
import 'group_create_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  List<String> _chats = [];
  List<String> _onlineUsers = [];
  // SPARTAN_STAGE24_GROUPS
  List<Map<String, dynamic>> _groups = <Map<String, dynamic>>[];

  bool _isLoading = true;
  final _search = TextEditingController();
  int _filter = 0;
  int _section = 0;
  bool _desktopSaved = false;
  Map<String, dynamic>? _selectedDesktopGroup;

  String? _selectedDesktopUser;

  // ========================================
  // КЭШ АВАТАРОК
  // ========================================

  final Map<String, MemoryImage> _avatarCache = {};

  final Map<String, String> _avatarBase64Cache = {};

  // ========================================
  // ПЕЧАТАЮЩИЕ ПОЛЬЗОВАТЕЛИ
  // ========================================

  final Set<String> _typingUsers = {};

  final Set<String> _trustedUsers = {};

  final Map<String, Timer> _typingTimers = {};

  StreamSubscription<String>? _notificationTapSubscription;

  StreamSubscription<String>? _firebaseNotificationTapSubscription;

  @override
  void initState() {
    super.initState();

    SocketService.instance.addMessageHandler(_handleMessage);

    SocketService.instance.getOfflineMessages();
    SocketService.instance.getGroups();

    _notificationTapSubscription = NotificationService
        .instance
        .notificationTapStream
        .listen(_handleNotificationPayload);

    _firebaseNotificationTapSubscription = FirebaseMessagingService
        .instance
        .notificationTapStream
        .listen(_handleNotificationPayload);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      SocketService.instance.requestPendingCall();
      unawaited(SystemCallService.instance.restorePending());
      unawaited(SystemCallService.instance.requestPermissions(context));
      final localPayload = NotificationService.instance.takeInitialPayload();

      final firebasePayload = FirebaseMessagingService.instance
          .takeInitialPayload();

      final payload = firebasePayload ?? localPayload;

      if (payload != null) {
        _handleNotificationPayload(payload);
      }
    });

    _loadChats(requestAvatars: true);

    _loadOnlineUsers();
  }

  @override
  void dispose() {
    SocketService.instance.removeMessageHandler(_handleMessage);

    _notificationTapSubscription?.cancel();
    _notificationTapSubscription = null;

    _firebaseNotificationTapSubscription?.cancel();
    _firebaseNotificationTapSubscription = null;

    for (final timer in _typingTimers.values) {
      timer.cancel();
    }

    _typingTimers.clear();
    _typingUsers.clear();

    _search.dispose();
    _avatarCache.clear();
    _avatarBase64Cache.clear();

    super.dispose();
  }

  // ========================================
  // ЗАГРУЗКА ЧАТОВ
  // ========================================

  void _loadChats({bool requestAvatars = false}) {
    final currentUser = SocketService.instance.currentUser;

    if (currentUser == null || currentUser.isEmpty) {
      if (!mounted) {
        return;
      }

      setState(() {
        _chats = [];
        _isLoading = false;
      });

      return;
    }

    final storedChats = StorageService.getChatUsers(currentUser);

    final combined = <String>{};

    combined.addAll(storedChats);

    combined.addAll(_onlineUsers);

    combined.remove(currentUser);

    final chats = combined.toList();

    if (!mounted) {
      return;
    }

    setState(() {
      final groupEntries = _groups
          .map((group) => "group::${group['id']?.toString() ?? ''}")
          .where((value) => value != 'group::')
          .toList();
      _chats = <String>[...groupEntries, ...chats];
      _isLoading = false;
    });

    if (requestAvatars) {
      _requestMissingAvatars(chats);
    }

    unawaited(_loadTrustStates(chats));
  }

  Future<void> _loadTrustStates(List<String> users) async {
    final trusted = <String>{};
    await Future.wait(
      users.map((user) async {
        if (await SpartanTrustService.isTrusted(user)) trusted.add(user);
      }),
    );
    if (!mounted) return;
    setState(() {
      _trustedUsers
        ..clear()
        ..addAll(trusted);
    });
  }

  // ========================================
  // ОБНОВЛЕНИЕ СПИСКА
  // ========================================

  Future<void> _refreshChats() async {
    _loadChats(requestAvatars: true);

    _loadOnlineUsers();

    await Future<void>.delayed(const Duration(milliseconds: 350));
  }

  // ========================================
  // ЗАПРОС НЕДОСТАЮЩИХ АВАТАРОК
  // ========================================

  void _requestMissingAvatars(List<String> users) {
    for (final user in users) {
      final avatar = StorageService.getAvatar(user);

      if (avatar == null || avatar.isEmpty) {
        SocketService.instance.requestAvatar(user);
      }
    }
  }

  // ========================================
  // ОНЛАЙН-ПОЛЬЗОВАТЕЛИ
  // ========================================

  void _loadOnlineUsers() {
    SocketService.instance.getUsers();
  }

  // ========================================
  // ПЕЧАТАЕТ
  // ========================================

  void _setUserTyping(String user, bool isTyping) {
    if (user.isEmpty) {
      return;
    }

    _typingTimers[user]?.cancel();
    _typingTimers.remove(user);

    if (!mounted) {
      return;
    }

    if (isTyping) {
      setState(() {
        _typingUsers.add(user);
      });

      _typingTimers[user] = Timer(const Duration(seconds: 4), () {
        if (!mounted) {
          return;
        }

        setState(() {
          _typingUsers.remove(user);
        });

        _typingTimers.remove(user);
      });

      return;
    }

    if (_typingUsers.contains(user)) {
      setState(() {
        _typingUsers.remove(user);
      });
    }
  }

  // ========================================
  // ОБРАБОТКА СООБЩЕНИЙ СЕРВЕРА
  // ========================================

  void _handleMessage(Map<String, dynamic> msg) {
    final type = msg['type']?.toString() ?? '';

    final rawData = msg['data'];

    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};

    // SPARTAN_STAGE24_GROUPS
    if (type == 'groups') {
      final rawGroups = data['groups'];
      if (rawGroups is! List) {
        return;
      }

      _groups = rawGroups
          .whereType<Map>()
          .map((group) => Map<String, dynamic>.from(group))
          .where((group) => (group['id']?.toString() ?? '').isNotEmpty)
          .toList();

      _loadChats();
      return;
    }

    if (type == 'group_created') {
      final rawGroup = data['group'];
      if (rawGroup is! Map) {
        return;
      }

      final group = Map<String, dynamic>.from(rawGroup);
      final groupId = group['id']?.toString() ?? '';
      if (groupId.isEmpty) {
        return;
      }

      _groups.removeWhere((item) => item['id']?.toString() == groupId);
      _groups.insert(0, group);

      _loadChats();
      return;
    }
    // SPARTAN_STAGE24_1_ADD_MEMBERS
    if (type == 'group_updated') {
      final rawGroup = data['group'];
      if (rawGroup is! Map) {
        return;
      }

      final group = Map<String, dynamic>.from(rawGroup);
      final groupId = group['id']?.toString() ?? '';
      if (groupId.isEmpty) {
        return;
      }

      _groups.removeWhere((item) => item['id']?.toString() == groupId);
      _groups.insert(0, group);

      _loadChats();
      return;
    }
    if (type == 'users') {
      final rawUsers = data['users'];

      if (rawUsers is! List) {
        return;
      }

      final currentUser = SocketService.instance.currentUser ?? '';

      final users = rawUsers
          .map((user) => user.toString())
          .where((user) => user.isNotEmpty && user != currentUser)
          .toList();

      _onlineUsers = users;

      _loadChats();

      _requestMissingAvatars(users);

      return;
    }

    if (type == 'avatar_data') {
      final username = data['username']?.toString() ?? '';

      if (username.isNotEmpty) {
        _avatarCache.remove(username);

        _avatarBase64Cache.remove(username);
      }

      if (mounted) {
        setState(() {});
      }

      return;
    }

    if (type == 'avatar_updated') {
      final username = data['username']?.toString() ?? '';

      if (username.isNotEmpty) {
        _avatarCache.remove(username);

        _avatarBase64Cache.remove(username);
      }

      return;
    }

    // ========================================
    // ПЕЧАТАЕТ В СПИСКЕ ЧАТОВ
    // ========================================

    if (type == 'typing') {
      final currentUser = SocketService.instance.currentUser ?? '';

      final from = data['from']?.toString().trim() ?? '';

      final to = data['to']?.toString().trim() ?? '';

      final isTyping = data['isTyping'] == true;

      if (currentUser.isEmpty ||
          from.isEmpty ||
          from == currentUser ||
          to != currentUser) {
        return;
      }

      _setUserTyping(from, isTyping);

      return;
    }

    if (type == 'message_edited') {
      final currentUser = SocketService.instance.currentUser ?? '';

      final messageId = data['messageId']?.toString().trim() ?? '';

      final from = data['from']?.toString().trim() ?? '';

      final to = data['to']?.toString().trim() ?? '';

      final newText = data['newText']?.toString().trim() ?? '';

      final editedAt =
          data['editedAt']?.toString().trim() ??
          DateTime.now().toIso8601String();

      if (currentUser.isEmpty ||
          messageId.isEmpty ||
          newText.isEmpty ||
          (from != currentUser && to != currentUser)) {
        return;
      }

      final otherUser = from == currentUser ? to : from;

      if (otherUser.isEmpty) {
        return;
      }

      final messages = StorageService.getMessages(currentUser, otherUser);

      var changed = false;

      for (final message in messages) {
        final id = message['id']?.toString().trim() ?? '';

        if (id == messageId) {
          message['text'] = newText;
          message['isEdited'] = true;
          message['editedAt'] = editedAt;
          changed = true;
        }

        final rawReply = message['replyTo'];

        if (rawReply is Map && rawReply['id']?.toString().trim() == messageId) {
          final reply = Map<String, dynamic>.from(rawReply);

          reply['text'] = newText;
          message['replyTo'] = reply;
          changed = true;
        }
      }

      if (changed) {
        StorageService.saveMessages(currentUser, otherUser, messages);

        _loadChats();
      }

      return;
    }

    if (type == 'message_deleted') {
      final currentUser = SocketService.instance.currentUser ?? '';

      final messageId = data['messageId']?.toString().trim() ?? '';

      final from = data['from']?.toString().trim() ?? '';

      final to = data['to']?.toString().trim() ?? '';

      if (currentUser.isEmpty ||
          messageId.isEmpty ||
          (from != currentUser && to != currentUser)) {
        return;
      }

      final otherUser = from == currentUser ? to : from;

      if (otherUser.isEmpty) {
        return;
      }

      final messages = StorageService.getMessages(currentUser, otherUser);

      var changed = false;

      final before = messages.length;

      messages.removeWhere(
        (message) => message['id']?.toString().trim() == messageId,
      );

      if (messages.length != before) {
        changed = true;
      }

      for (final message in messages) {
        final rawReply = message['replyTo'];

        if (rawReply is Map && rawReply['id']?.toString().trim() == messageId) {
          message.remove('replyTo');
          changed = true;
        }
      }

      if (changed) {
        StorageService.saveMessages(currentUser, otherUser, messages);

        if (messages.isEmpty) {
          StorageService.clearUnreadCount(currentUser, otherUser);
        }

        _loadChats();
      }

      return;
    }

    if (type == 'message') {
      final currentUser = SocketService.instance.currentUser ?? '';

      final from = data['from']?.toString() ?? '';

      final to = data['to']?.toString() ?? currentUser;

      final text = data['text']?.toString() ?? '';

      final time = data['time']?.toString() ?? DateTime.now().toIso8601String();

      final id = data['id']?.toString() ?? '';

      if (currentUser.isEmpty ||
          from.isEmpty ||
          from == currentUser ||
          text.isEmpty) {
        return;
      }

      _setUserTyping(from, false);

      final messages = StorageService.getMessages(currentUser, from);

      bool alreadyExists = false;

      for (final message in messages) {
        final oldId = message['id']?.toString() ?? '';

        if (id.isNotEmpty && oldId.isNotEmpty && oldId == id) {
          alreadyExists = true;
          break;
        }

        final oldFrom = message['from']?.toString() ?? '';

        final oldText = message['text']?.toString() ?? '';

        final oldTime = message['time']?.toString() ?? '';

        if (oldFrom == from && oldText == text && oldTime == time) {
          alreadyExists = true;
          break;
        }
      }

      if (!alreadyExists) {
        messages.add({
          'id': id,
          'from': from,
          'to': to,
          'text': text,
          'messageType': data['messageType']?.toString().trim() ?? 'text',
          if (data['voiceData'] is String)
            'voiceData': data['voiceData'].toString(),
          if (data['voiceDurationMs'] != null)
            'voiceDurationMs': data['voiceDurationMs'],
          if (data['voiceMimeType'] != null)
            'voiceMimeType': data['voiceMimeType'].toString(),
          if (data['mediaId'] != null &&
              data['mediaId'].toString().trim().isNotEmpty)
            'mediaId': data['mediaId'].toString(),
          if (data['mediaData'] is String)
            'mediaData': data['mediaData'].toString(),
          if (data['fileName'] != null) 'fileName': data['fileName'].toString(),
          if (data['fileSize'] != null) 'fileSize': data['fileSize'],
          if (data['mimeType'] != null) 'mimeType': data['mimeType'].toString(),
          'time': time,
          'status': 'delivered',
          if (data['replyTo'] is Map)
            'replyTo': Map<String, dynamic>.from(data['replyTo'] as Map),
          if (data['forwardedFrom'] != null)
            'forwardedFrom': data['forwardedFrom'].toString(),
          if (data['forwardComment'] != null)
            'forwardComment': data['forwardComment'].toString(),
          if (data['isEdited'] == true) 'isEdited': true,
          if (data['editedAt'] != null) 'editedAt': data['editedAt'].toString(),
        });

        StorageService.saveMessages(currentUser, from, messages);

        StorageService.incrementUnreadCount(currentUser, from);
      }

      _loadChats();

      return;
    }

    if (type == 'message_sent') {
      final currentUser = SocketService.instance.currentUser ?? '';

      final to = data['to']?.toString() ?? '';

      final text = data['text']?.toString() ?? '';

      final time = data['time']?.toString() ?? DateTime.now().toIso8601String();

      final id = data['id']?.toString() ?? '';

      if (currentUser.isEmpty || to.isEmpty || text.isEmpty) {
        return;
      }

      final messages = StorageService.getMessages(currentUser, to);

      bool alreadyExists = false;

      for (final message in messages) {
        final oldId = message['id']?.toString() ?? '';

        if (id.isNotEmpty && oldId.isNotEmpty && oldId == id) {
          alreadyExists = true;
          break;
        }

        final oldFrom = message['from']?.toString() ?? '';

        final oldTo = message['to']?.toString() ?? '';

        final oldText = message['text']?.toString() ?? '';

        final oldTime = message['time']?.toString() ?? '';

        if (oldFrom == currentUser &&
            oldTo == to &&
            oldText == text &&
            oldTime == time) {
          alreadyExists = true;
          break;
        }
      }

      if (!alreadyExists) {
        messages.add({
          'id': id,
          'from': currentUser,
          'to': to,
          'text': text,
          'messageType': data['messageType']?.toString().trim() ?? 'text',
          if (data['voiceData'] is String)
            'voiceData': data['voiceData'].toString(),
          if (data['voiceDurationMs'] != null)
            'voiceDurationMs': data['voiceDurationMs'],
          if (data['voiceMimeType'] != null)
            'voiceMimeType': data['voiceMimeType'].toString(),
          if (data['mediaId'] != null &&
              data['mediaId'].toString().trim().isNotEmpty)
            'mediaId': data['mediaId'].toString(),
          if (data['mediaData'] is String)
            'mediaData': data['mediaData'].toString(),
          if (data['fileName'] != null) 'fileName': data['fileName'].toString(),
          if (data['fileSize'] != null) 'fileSize': data['fileSize'],
          if (data['mimeType'] != null) 'mimeType': data['mimeType'].toString(),
          'time': time,
          'status': 'sent',
          if (data['replyTo'] is Map)
            'replyTo': Map<String, dynamic>.from(data['replyTo'] as Map),
          if (data['forwardedFrom'] != null)
            'forwardedFrom': data['forwardedFrom'].toString(),
          if (data['forwardComment'] != null)
            'forwardComment': data['forwardComment'].toString(),
          if (data['isEdited'] == true) 'isEdited': true,
          if (data['editedAt'] != null) 'editedAt': data['editedAt'].toString(),
        });

        StorageService.saveMessages(currentUser, to, messages);
      }

      _loadChats();

      return;
    }
  }

  // ========================================
  // НАЖАТИЕ НА УВЕДОМЛЕНИЕ
  // ========================================

  void _handleNotificationPayload(String payload) {
    if (CallService.instance.hasCall) return;
    if (!mounted) {
      return;
    }

    final value = payload.trim();

    if (value.isEmpty) {
      return;
    }

    String? user;

    if (value.startsWith('group:')) {
      final id = value.substring('group:'.length);
      for (final group in _groups) {
        if (group['id']?.toString() == id) {
          _openGroup(group);
          return;
        }
      }
      return;
    }

    if (value.startsWith('message:')) {
      user = value.substring('message:'.length).trim();
    } else if (value.startsWith('reaction:')) {
      user = value.substring('reaction:'.length).trim();
    }

    if (user == null || user.isEmpty) {
      return;
    }

    final currentUser = SocketService.instance.currentUser ?? '';

    if (currentUser.isEmpty || user == currentUser) {
      return;
    }

    print('🔔 Открываем чат из уведомления: $user');

    // При входе именно через шторку очищаем
    // уведомления приложения. Это также убирает
    // системное FCM-уведомление, которое нельзя
    // удалить по локальному ID собеседника.
    unawaited(NotificationService.instance.cancelAll());

    _openChat(user);
  }

  // ========================================
  // ОТКРЫТИЕ ЧАТА
  // ========================================

  void _openChat(String user) {
    final currentUser = SocketService.instance.currentUser ?? '';

    if (currentUser.isEmpty) {
      return;
    }

    StorageService.clearUnreadCount(currentUser, user);

    final isDesktopLayout = MediaQuery.sizeOf(context).width >= 900;

    if (isDesktopLayout) {
      if (!mounted) {
        return;
      }

      setState(() {
        _selectedDesktopUser = user;
        _selectedDesktopGroup = null;
        _desktopSaved = false;
        _section = 0;
      });

      return;
    }

    if (mounted) {
      setState(() {});
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(targetUser: user)),
    ).then((_) {
      if (!mounted) {
        return;
      }

      _loadChats();
      _loadOnlineUsers();
    });
  }

  // ========================================
  // УДАЛЕНИЕ ЧАТА
  // ========================================

  Future<void> _deleteChat(String user) async {
    final currentUser = SocketService.instance.currentUser ?? '';

    if (currentUser.isEmpty) {
      return;
    }

    await StorageService.removeChat(currentUser, user);

    if (!mounted) {
      return;
    }

    if (_selectedDesktopUser == user) {
      setState(() {
        _selectedDesktopUser = null;
      });
    }

    _loadChats();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Чат с $user удалён'),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 1),
      ),
    );
  }

  // ========================================
  // ПОСЛЕДНЕЕ СООБЩЕНИЕ
  // ========================================

  String _getLastMessage(String user) {
    final currentUser = SocketService.instance.currentUser ?? '';

    if (currentUser.isEmpty) {
      return '';
    }

    final messages = StorageService.getMessages(currentUser, user);

    if (messages.isEmpty) {
      return '';
    }

    return messages.last['text']?.toString() ?? '';
  }

  // ========================================
  // ВРЕМЯ
  // ========================================

  String _getLastMessageTime(String user) {
    final currentUser = SocketService.instance.currentUser ?? '';

    if (currentUser.isEmpty) {
      return '';
    }

    final messages = StorageService.getMessages(currentUser, user);

    if (messages.isEmpty) {
      return '';
    }

    final timeString = messages.last['time']?.toString();

    if (timeString == null || timeString.isEmpty) {
      return '';
    }

    try {
      final time = DateTime.parse(timeString).toLocal();

      return '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  // ========================================
  // СЧЁТЧИК
  // ========================================

  int _getUnreadCount(String user) {
    final currentUser = SocketService.instance.currentUser ?? '';

    if (currentUser.isEmpty) {
      return 0;
    }

    return StorageService.getUnreadCount(currentUser, user);
  }

  // ========================================
  // ОНЛАЙН
  // ========================================

  bool _isUserOnline(String user) {
    return _onlineUsers.contains(user);
  }

  // ========================================
  // АВАТАРКА С КЭШЕМ
  // ========================================

  Widget _buildAvatar(String username, {double radius = 30}) {
    final avatar = StorageService.getAvatar(username);

    if (avatar != null && avatar.isNotEmpty) {
      try {
        final cachedBase64 = _avatarBase64Cache[username];

        MemoryImage? image = _avatarCache[username];

        if (image == null || cachedBase64 != avatar) {
          final bytes = base64Decode(avatar);

          image = MemoryImage(bytes);

          _avatarCache[username] = image;

          _avatarBase64Cache[username] = avatar;
        }

        return CircleAvatar(
          key: ValueKey('avatar_$username'),
          radius: radius,
          backgroundColor: SpartanPalette.canvas,
          backgroundImage: image,
        );
      } catch (error) {
        print('❌ Ошибка аватарки $username: $error');
      }
    }

    return CircleAvatar(
      key: ValueKey('avatar_fallback_$username'),
      radius: radius,
      backgroundColor: SpartanPalette.blue,
      child: Text(
        username.isNotEmpty ? username[0].toUpperCase() : '?',
        style: TextStyle(
          color: SpartanPalette.ink,
          fontSize: radius * 0.72,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ========================================
  // УВЕЛИЧЕННАЯ АВАТАРКА
  // ========================================

  void _showAvatarPreview(String username) {
    final avatar = StorageService.getAvatar(username);

    if (avatar == null || avatar.isEmpty) {
      return;
    }

    try {
      final bytes = base64Decode(avatar);

      if (bytes.isEmpty) {
        return;
      }

      final image = MemoryImage(bytes);

      showDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.85),
        builder: (dialogContext) {
          final screenWidth = MediaQuery.of(dialogContext).size.width;

          final size = screenWidth > 320 ? 260.0 : 220.0;

          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.all(24),
            child: GestureDetector(
              onTap: () {
                Navigator.of(dialogContext).pop();
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFFD4AF37),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 20,
                          spreadRadius: 3,
                        ),
                      ],
                    ),
                    child: ClipOval(
                      child: Image(
                        image: image,
                        width: size,
                        height: size,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  Text(
                    username,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (error) {
      print('❌ Ошибка увеличения аватарки $username: $error');
    }
  }

  // ========================================
  // СТРОКА ЧАТА
  // ========================================

  // ========================================
  // GROUPS — STAGE 24
  // SPARTAN_STAGE24_GROUPS
  // ========================================

  Future<void> _openCreateGroup() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const GroupCreateScreen()),
    );

    if (!mounted) {
      return;
    }

    if (result != null) {
      final groupId = result['id']?.toString() ?? '';
      if (groupId.isNotEmpty) {
        _groups.removeWhere((item) => item['id']?.toString() == groupId);
        _groups.insert(0, result);
      }
    }

    SocketService.instance.getGroups();
    _loadChats();
  }

  void _openGroup(Map<String, dynamic> group) {
    if (MediaQuery.sizeOf(context).width >= 900) {
      setState(() {
        _selectedDesktopGroup = group;
        _selectedDesktopUser = null;
        _desktopSaved = false;
        _section = 0;
      });
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GroupChatScreen(group: group)),
    );
  }

  Widget _buildGroupTile(Map<String, dynamic> group) {
    final id = group['id']?.toString() ?? '';
    final name = group['name']?.toString() ?? 'Группа';
    final preview = group['lastMessage']?.toString() ?? '';
    final members = group['members'];
    return _conversationTile(
      title: name,
      subtitle: preview.isEmpty
          ? '${members is List ? members.length : 0} участников'
          : preview,
      avatar: const CircleAvatar(
        radius: 24,
        backgroundColor: SpartanPalette.blue,
        child: Icon(Icons.groups_rounded, color: SpartanPalette.gold),
      ),
      selected: _selectedDesktopGroup?['id'] == id,
      onTap: () => _openGroup(group),
    );
  }

  Widget _conversationTile({
    required String title,
    required String subtitle,
    required Widget avatar,
    required VoidCallback onTap,
    String time = '',
    int unread = 0,
    bool selected = false,
    bool pinned = false,
    VoidCallback? onLongPress,
  }) {
    final highlighted = selected || unread > 0;
    const cardRadius = BorderRadius.only(
      topLeft: Radius.circular(22),
      topRight: Radius.circular(9),
      bottomRight: Radius.circular(22),
      bottomLeft: Radius.circular(9),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Material(
        color: Colors.transparent,
        borderRadius: cardRadius,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: cardRadius,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.fromLTRB(13, 13, 10, 13),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: selected
                    ? const [SpartanPalette.surfaceRaised, SpartanPalette.blue]
                    : const [
                        SpartanPalette.surfaceSoft,
                        SpartanPalette.surface,
                      ],
              ),
              borderRadius: cardRadius,
              border: Border.all(
                color: highlighted
                    ? SpartanPalette.gold.withValues(alpha: .62)
                    : SpartanPalette.line,
                width: highlighted ? 1.1 : .7,
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x24000000),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                avatar,
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: SpartanPalette.ink,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: SpartanPalette.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (time.isNotEmpty)
                      Text(
                        time,
                        style: const TextStyle(
                          fontSize: 11,
                          color: SpartanPalette.secondary,
                        ),
                      ),
                    const SizedBox(height: 7),
                    if (unread > 0)
                      Container(
                        width: 8,
                        height: 25,
                        decoration: BoxDecoration(
                          color: SpartanPalette.gold,
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: SpartanPalette.gold.withValues(alpha: .35),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                      )
                    else if (pinned)
                      const Icon(
                        Icons.push_pin_outlined,
                        size: 15,
                        color: SpartanPalette.gold,
                      )
                    else
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: SpartanPalette.muted,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showChatOptions(String user) async {
    final owner = SocketService.instance.currentUser ?? '';
    final pinned = StorageService.getPinnedChats(owner).contains(user);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: Text(pinned ? 'Открепить чат' : 'Закрепить чат'),
              onTap: () => Navigator.pop(context, 'pin'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Удалить локальную историю'),
              onTap: () => Navigator.pop(context, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'pin') {
      StorageService.togglePinChat(owner, user);
      setState(() {});
    }
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Удалить чат с $user?'),
          content: const Text('История удалится только на этом устройстве.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Удалить'),
            ),
          ],
        ),
      );
      if (confirmed == true && mounted) await _deleteChat(user);
    }
  }

  Widget _buildChatTile(String user) {
    if (user.startsWith('group::')) {
      for (final group in _groups) {
        if ('group::${group['id']}' == user) return _buildGroupTile(group);
      }
      return const SizedBox.shrink();
    }
    final pinned = StorageService.getPinnedChats(
      SocketService.instance.currentUser ?? '',
    ).contains(user);
    return _conversationTile(
      title: user,
      subtitle: _typingUsers.contains(user)
          ? 'печатает…'
          : _getLastMessage(user),
      time: _getLastMessageTime(user),
      unread: _getUnreadCount(user),
      pinned: pinned,
      selected:
          _selectedDesktopUser == user &&
          !_desktopSaved &&
          _selectedDesktopGroup == null,
      avatar: GestureDetector(
        onLongPress: () => _showAvatarPreview(user),
        child: Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: _trustedUsers.contains(user)
                  ? SpartanPalette.gold
                  : _isUserOnline(user)
                  ? SpartanPalette.online
                  : SpartanPalette.line,
              width: _trustedUsers.contains(user) || _isUserOnline(user)
                  ? 2
                  : 1,
            ),
            boxShadow: _trustedUsers.contains(user) || _isUserOnline(user)
                ? [
                    BoxShadow(
                      color:
                          (_trustedUsers.contains(user)
                                  ? SpartanPalette.gold
                                  : SpartanPalette.online)
                              .withValues(alpha: .22),
                      blurRadius: 10,
                    ),
                  ]
                : const [],
          ),
          child: Stack(
            children: [
              _buildAvatar(user, radius: 23),
              if (_isUserOnline(user))
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: SpartanPalette.online,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: SpartanPalette.surfaceSoft,
                        width: 2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      onTap: () => _openChat(user),
      onLongPress: () => unawaited(_showChatOptions(user)),
    );
  }

  List<String> get _visibleChats {
    final query = _search.text.trim().toLowerCase();
    final result = _chats.where((entry) {
      final isGroup = entry.startsWith('group::');
      if (_filter == 1 && isGroup || _filter == 2 && !isGroup) return false;
      var name = entry;
      if (isGroup) {
        for (final group in _groups) {
          if ('group::${group['id']}' == entry)
            name = group['name']?.toString() ?? '';
        }
      }
      return name.toLowerCase().contains(query);
    }).toList();
    final pinned = StorageService.getPinnedChats(
      SocketService.instance.currentUser ?? '',
    );
    final times = {for (final entry in result) entry: _lastActivity(entry)};
    result.sort((a, b) {
      final pa = pinned.indexOf(a), pb = pinned.indexOf(b);
      if (pa >= 0 || pb >= 0) {
        if (pa < 0) return 1;
        if (pb < 0) return -1;
        return pa.compareTo(pb);
      }
      final time = times[b]!.compareTo(times[a]!);
      return time == 0 ? a.toLowerCase().compareTo(b.toLowerCase()) : time;
    });
    return result;
  }

  DateTime _lastActivity(String user) {
    if (user.startsWith('group::')) {
      for (final group in _groups) {
        if ('group::${group['id']}' == user) {
          return DateTime.tryParse(
                group['lastMessageTime']?.toString() ?? '',
              ) ??
              DateTime(2000);
        }
      }
      return DateTime(2000);
    }
    final messages = StorageService.getMessages(
      SocketService.instance.currentUser ?? '',
      user,
    );
    return messages.isEmpty
        ? DateTime(2000)
        : DateTime.tryParse(messages.last['time']?.toString() ?? '') ??
              DateTime(2000);
  }

  void _openSaved() {
    if (MediaQuery.sizeOf(context).width >= 900) {
      setState(() {
        _desktopSaved = true;
        _selectedDesktopGroup = null;
        _selectedDesktopUser = null;
        _section = 0;
      });
    } else {
      Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => SavedMessagesScreen(
            owner: SocketService.instance.currentUser ?? '',
          ),
        ),
      );
    }
  }

  Widget _savedTile() => _conversationTile(
    title: 'Сохранённое',
    subtitle: 'Заметки и сообщения · на устройстве',
    avatar: const CircleAvatar(
      radius: 24,
      backgroundColor: SpartanPalette.blue,
      child: Icon(Icons.bookmark_outline_rounded, color: SpartanPalette.gold),
    ),
    selected: _desktopSaved,
    onTap: _openSaved,
  );

  Future<void> _showPulseRequests() async {
    final service = PulseService.instance;
    service.markAllSeen();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => AnimatedBuilder(
        animation: service,
        builder: (context, _) {
          final currentUser = SocketService.instance.currentUser ?? '';
          final pulses = service.pulses;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .72,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 12, 12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.bolt_rounded,
                          color: SpartanPalette.gold,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Запросы SPARTAN PULSE · ${pulses.length}',
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Закрыть',
                          onPressed: () => Navigator.pop(sheetContext),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  if (pulses.isEmpty)
                    const Padding(
                      padding: EdgeInsets.fromLTRB(24, 24, 24, 40),
                      child: Text(
                        'Активных запросов пока нет',
                        style: TextStyle(color: SpartanPalette.secondary),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
                        itemCount: pulses.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final pulse = pulses[index];
                          final peer = pulse.peerFor(currentUser);
                          final incoming =
                              pulse.to == currentUser &&
                              pulse.state == 'pending';
                          final matched = pulse.state == 'matched';
                          final accepted = pulse.state == 'accepted';
                          final minutes = service.remainingMinutes(pulse);
                          final status = matched
                              ? 'Оба готовы · соединяем'
                              : incoming
                              ? 'Входящий запрос · ещё $minutes мин.'
                              : accepted
                              ? 'Готовность подтверждена'
                              : 'Исходящий запрос · ещё $minutes мин.';
                          return Material(
                            color: SpartanPalette.canvas,
                            borderRadius: BorderRadius.circular(16),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  _buildAvatar(peer, radius: 24),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: InkWell(
                                      onTap: () {
                                        Navigator.pop(sheetContext);
                                        _openChat(peer);
                                      },
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            peer,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 16,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            status,
                                            style: const TextStyle(
                                              color: SpartanPalette.secondary,
                                              fontSize: 12,
                                            ),
                                          ),
                                          Text(
                                            pulse.video
                                                ? 'Видеозвонок'
                                                : 'Аудиозвонок',
                                            style: const TextStyle(
                                              color: SpartanPalette.gold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  if (incoming) ...[
                                    IconButton(
                                      tooltip: 'Не сейчас',
                                      onPressed: () =>
                                          service.declinePulse(pulse.id),
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                                    IconButton.filled(
                                      tooltip: 'Я готов',
                                      onPressed: () =>
                                          service.acceptPulse(pulse.id),
                                      style: IconButton.styleFrom(
                                        backgroundColor: SpartanPalette.gold,
                                        foregroundColor: SpartanPalette.onGold,
                                      ),
                                      icon: const Icon(Icons.check_rounded),
                                    ),
                                  ] else if (!matched)
                                    IconButton(
                                      tooltip: 'Отменить',
                                      onPressed: () =>
                                          service.cancelPulse(pulse.id),
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _pulseDock() => AnimatedBuilder(
    animation: PulseService.instance,
    builder: (context, _) {
      final service = PulseService.instance;
      final pulse = service.current;
      final currentUser = SocketService.instance.currentUser ?? '';
      if (pulse == null || currentUser.isEmpty) {
        return const SizedBox.shrink();
      }

      final peer = pulse.peerFor(currentUser);
      final incoming = service.phase == SpartanPulsePhase.incoming;
      final matched = service.phase == SpartanPulsePhase.matched;
      final minutes = service.remainingMinutes(pulse);
      final stateText = matched
          ? 'Оба готовы · звонок через ${service.countdownSeconds} сек.'
          : incoming
          ? 'Входящий · осталось $minutes мин.'
          : 'Ждём готовность · осталось $minutes мин.';
      final mode = pulse.video ? 'видеозвонок' : 'аудиозвонок';
      final requestCount = service.requestCount;
      final unreadCount = service.unreadCount;

      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: Material(
          color: SpartanPalette.blue,
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            key: const ValueKey('pulse-dock'),
            onTap: _showPulseRequests,
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: SpartanPalette.gold),
              ),
              child: Row(
                children: [
                  Badge(
                    isLabelVisible: requestCount > 0,
                    label: Text(requestCount > 9 ? '9+' : '$requestCount'),
                    backgroundColor: unreadCount > 0
                        ? SpartanPalette.gold
                        : SpartanPalette.secondary,
                    textColor: SpartanPalette.onGold,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: SpartanPalette.gold.withValues(alpha: .14),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        color: SpartanPalette.gold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'SPARTAN PULSE',
                          style: TextStyle(
                            color: SpartanPalette.gold,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .7,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '$peer · $mode',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: SpartanPalette.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          unreadCount > 0
                              ? '$stateText · новых: $unreadCount'
                              : '$stateText · запросов: $requestCount',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: SpartanPalette.secondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (incoming) ...[
                    IconButton(
                      tooltip: 'Не сейчас',
                      onPressed: service.decline,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: SpartanPalette.secondary,
                      ),
                    ),
                    IconButton.filled(
                      tooltip: 'Я готов',
                      onPressed: service.accept,
                      style: IconButton.styleFrom(
                        backgroundColor: SpartanPalette.gold,
                        foregroundColor: SpartanPalette.onGold,
                      ),
                      icon: const Icon(Icons.check_rounded),
                    ),
                  ] else if (!matched)
                    IconButton(
                      tooltip: 'Отменить SPARTAN PULSE',
                      onPressed: service.cancel,
                      icon: const Icon(
                        Icons.close_rounded,
                        color: SpartanPalette.secondary,
                      ),
                    ),
                  if (!incoming)
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: SpartanPalette.secondary,
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _buildChatListPane() {
    final visible = _visibleChats;
    final query = _search.text.trim().toLowerCase();
    final contactCount = _chats
        .where((item) => !item.startsWith('group::'))
        .length;
    final eventCount = PulseService.instance.requestCount;
    final showSaved =
        _filter != 2 &&
        (query.isEmpty || 'сохранённое сохраненное заметки'.contains(query));
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [SpartanPalette.canvasDeep, SpartanPalette.surface],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
              child: Row(
                children: [
                  const Expanded(child: SpartanBrand()),
                  IconButton(
                    tooltip: 'Обновить контакты',
                    onPressed: _refreshChats,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  if (MediaQuery.sizeOf(context).width < 900)
                    IconButton(
                      tooltip: 'Система',
                      onPressed: () => _selectSection(2),
                      icon: const Icon(Icons.tune_rounded),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 5, 20, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'COMMAND DECK',
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w900,
                            letterSpacing: .8,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'ЦЕНТР СВЯЗИ',
                          style: TextStyle(
                            color: SpartanPalette.gold,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: SpartanPalette.surfaceSoft,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: SpartanPalette.line),
                    ),
                    child: Text(
                      'Люди: $contactCount · События: $eventCount',
                      style: const TextStyle(
                        color: SpartanPalette.secondary,
                        fontSize: 10,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                key: const ValueKey('contact-search'),
                controller: _search,
                onChanged: (_) => setState(() {}),
                onTap: _loadOnlineUsers,
                decoration: InputDecoration(
                  hintText: 'Поиск контактов и чатов',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Очистить поиск',
                          icon: const Icon(Icons.close),
                          onPressed: () {
                            _search.clear();
                            setState(() {});
                          },
                        ),
                  fillColor: SpartanPalette.surfaceSoft,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 13),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: SpartanPalette.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: SpartanPalette.line),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: SpartanPalette.canvasDeep.withValues(alpha: .58),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: SpartanPalette.line),
                ),
                child: Row(
                  children: List.generate(
                    3,
                    (index) => Expanded(
                      child: InkWell(
                        key: ValueKey('chat-filter-$index'),
                        onTap: () => setState(() => _filter = index),
                        borderRadius: BorderRadius.circular(14),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: _filter == index
                                ? SpartanPalette.gold.withValues(alpha: .16)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(14),
                            border: _filter == index
                                ? Border.all(color: SpartanPalette.gold)
                                : null,
                          ),
                          child: Text(
                            ['ОБЗОР', 'ЛЮДИ', 'КОМАНДЫ'][index],
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _filter == index
                                  ? SpartanPalette.gold
                                  : SpartanPalette.secondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: .7,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            _pulseDock(),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: _refreshChats,
                      child: ListView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        children: [
                          for (final user in visible) _buildChatTile(user),
                          if (showSaved) _savedTile(),
                          if (visible.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                query.isEmpty
                                    ? (_filter == 2
                                          ? 'Пока нет групп. Создайте первую.'
                                          : 'Здесь появятся ваши чаты и контакты онлайн.')
                                    : 'Ничего не найдено. Поиск по существующим чатам и контактам онлайн.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: SpartanPalette.secondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('logged_in', false);
    await SocketService.instance.disconnect();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }

  Widget _settings() => SettingsScreen(
    username: SocketService.instance.currentUser ?? '',
    onLogout: _logout,
    onDeleteAccount: () {},
  );

  void _dial(String user, bool video) {
    if (!SocketService.instance.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Для звонка подключитесь к серверу')),
      );
      return;
    }
    if (CallService.instance.hasCall) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Звонок уже активен')));
      return;
    }
    unawaited(CallService.instance.startCall(peer: user, video: video));
  }

  Widget _callsPane() => Scaffold(
    appBar: AppBar(title: const Text('Звонки')),
    body: ValueListenableBuilder<int>(
      valueListenable: CallHistoryService.changes,
      builder: (context, _, child) {
        final history = CallHistoryService.items(
          SocketService.instance.currentUser ?? '',
        );
        final contacts = _chats.where((e) => !e.startsWith('group::')).toList()
          ..sort();
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Недавние',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            if (history.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'История появится после новых звонков.',
                  style: TextStyle(color: SpartanPalette.secondary),
                ),
              ),
            for (final item in history)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _buildAvatar(item['peer'].toString(), radius: 22),
                title: Text(item['peer'].toString()),
                subtitle: Text(
                  '${item['incoming'] == true ? 'Входящий' : 'Исходящий'} · '
                  '${CallHistoryService.status(item)}'
                  '\n${_formatCallDate(item['time']?.toString() ?? '')}',
                  style: item['outcome'] == 'missed'
                      ? const TextStyle(color: Colors.redAccent)
                      : null,
                ),
                trailing: IconButton(
                  tooltip: 'Повторить звонок',
                  icon: Icon(
                    item['video'] == true
                        ? Icons.videocam_outlined
                        : Icons.call_outlined,
                  ),
                  onPressed: () =>
                      _dial(item['peer'].toString(), item['video'] == true),
                ),
              ),
            const SizedBox(height: 24),
            const Text(
              'Позвонить контакту',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            for (final user in contacts)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _buildAvatar(user, radius: 22),
                title: Text(user),
                subtitle: Text(_isUserOnline(user) ? 'в сети' : 'не в сети'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Аудиозвонок: $user',
                      onPressed: () => _dial(user, false),
                      icon: const Icon(Icons.call_outlined),
                    ),
                    IconButton(
                      tooltip: 'Видеозвонок: $user',
                      onPressed: () => _dial(user, true),
                      icon: const Icon(Icons.videocam_outlined),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );

  String _formatCallDate(String raw) {
    final date = DateTime.tryParse(raw)?.toLocal();
    if (date == null) return '';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}.${two(date.month)} · ${two(date.hour)}:${two(date.minute)}';
  }

  void _selectSection(int value) {
    if (_section == value) return;
    setState(() => _section = value);
    // A hidden desktop conversation must not auto-mark incoming messages read.
    if (value != 0) SocketService.instance.setActiveChatUser('');
    _loadChats();
    _loadOnlineUsers();
  }

  Widget _desktopConversation() {
    if (_desktopSaved)
      return SavedMessagesScreen(
        owner: SocketService.instance.currentUser ?? '',
      );
    if (_selectedDesktopGroup != null)
      return GroupChatScreen(
        key: ValueKey('desktop-group-${_selectedDesktopGroup!['id']}'),
        group: _selectedDesktopGroup!,
      );
    if (_selectedDesktopUser != null)
      return ChatScreen(
        key: ValueKey('desktop_chat_$_selectedDesktopUser'),
        targetUser: _selectedDesktopUser!,
      );
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SpartanBrand(),
          SizedBox(height: 20),
          Text('Выберите чат', style: TextStyle(fontSize: 22)),
          SizedBox(height: 8),
          Text(
            'Сообщения, фото и звонки — рядом',
            style: TextStyle(color: SpartanPalette.secondary),
          ),
        ],
      ),
    );
  }

  Widget _pulseBadgeIcon(IconData icon, {Color? color}) => AnimatedBuilder(
    animation: PulseService.instance,
    builder: (context, _) {
      final unread = PulseService.instance.unreadCount;
      return Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        backgroundColor: SpartanPalette.gold,
        textColor: SpartanPalette.onGold,
        child: Icon(icon, color: color),
      );
    },
  );

  Widget _railButton(
    int index,
    IconData icon,
    String label, {
    bool pulseBadge = false,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Tooltip(
      message: label,
      child: InkWell(
        key: ValueKey('nav-$index'),
        onTap: () => _selectSection(index),
        borderRadius: BorderRadius.circular(13),
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _section == index ? SpartanPalette.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
          ),
          child: pulseBadge
              ? Center(
                  child: _pulseBadgeIcon(
                    icon,
                    color: _section == index
                        ? SpartanPalette.onGold
                        : SpartanPalette.ink,
                  ),
                )
              : Icon(
                  icon,
                  color: _section == index
                      ? SpartanPalette.onGold
                      : SpartanPalette.ink,
                ),
        ),
      ),
    ),
  );

  Future<void> _showCommandActions() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Text(
                  'SPARTAN COMMAND',
                  style: TextStyle(
                    color: SpartanPalette.gold,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1,
                  ),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.bolt_rounded,
                  color: SpartanPalette.gold,
                ),
                title: const Text('Запросы SPARTAN PULSE'),
                subtitle: const Text('Созвоны, когда оба готовы'),
                onTap: () => Navigator.pop(context, 'pulse'),
              ),
              ListTile(
                leading: const Icon(Icons.groups_rounded),
                title: const Text('Создать команду'),
                subtitle: const Text('Новый групповой чат'),
                onTap: () => Navigator.pop(context, 'group'),
              ),
              ListTile(
                leading: const Icon(Icons.sync_rounded),
                title: const Text('Обновить связь'),
                subtitle: const Text('Синхронизировать контакты и события'),
                onTap: () => Navigator.pop(context, 'refresh'),
              ),
              ListTile(
                leading: const Icon(Icons.tune_rounded),
                title: const Text('Система'),
                subtitle: const Text('Настройки SPARTAN CHAT'),
                onTap: () => Navigator.pop(context, 'settings'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'pulse') await _showPulseRequests();
    if (action == 'group') await _openCreateGroup();
    if (action == 'refresh') await _refreshChats();
    if (action == 'settings') _selectSection(2);
  }

  Widget _mobileDeckButton(int index, IconData icon, String label) => Expanded(
    child: InkWell(
      key: ValueKey('mobile-command-$index'),
      onTap: () => _selectSection(index),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _section == index && index == 1
                ? _pulseBadgeIcon(icon, color: SpartanPalette.gold)
                : Icon(
                    icon,
                    color: _section == index
                        ? SpartanPalette.gold
                        : SpartanPalette.secondary,
                  ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: _section == index
                    ? SpartanPalette.gold
                    : SpartanPalette.secondary,
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: .8,
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _mobileCommandDock() => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: SpartanPalette.rail,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: SpartanPalette.line),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            _mobileDeckButton(0, Icons.chat_bubble_outline_rounded, 'СВЯЗЬ'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: IconButton.filled(
                key: const ValueKey('spartan-command-button'),
                tooltip: 'SPARTAN COMMAND',
                onPressed: _showCommandActions,
                style: IconButton.styleFrom(
                  minimumSize: const Size(56, 56),
                  backgroundColor: SpartanPalette.gold,
                  foregroundColor: SpartanPalette.onGold,
                  side: const BorderSide(color: Color(0xFFE3C87C), width: 1.5),
                  shadowColor: SpartanPalette.gold,
                  elevation: 7,
                ),
                icon: const Icon(Icons.bolt_rounded, size: 30),
              ),
            ),
            _mobileDeckButton(1, Icons.call_outlined, 'ЗВОНКИ'),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final desktop = MediaQuery.sizeOf(context).width >= 900;
    final body = _section == 1
        ? _callsPane()
        : _section == 2
        ? _settings()
        : desktop
        ? Row(
            children: [
              SizedBox(
                width: MediaQuery.sizeOf(context).width >= 1300 ? 340 : 310,
                child: _buildChatListPane(),
              ),
              const VerticalDivider(width: 1, thickness: 1),
              Expanded(child: _desktopConversation()),
            ],
          )
        : _buildChatListPane();
    if (desktop)
      return Scaffold(
        body: Row(
          children: [
            ColoredBox(
              color: SpartanPalette.rail,
              child: SafeArea(
                child: SizedBox(
                  width: 72,
                  child: Column(
                    children: [
                      const SizedBox(height: 22),
                      const SpartanBrand(compact: true),
                      const SizedBox(height: 34),
                      _railButton(0, Icons.chat_bubble_outline_rounded, 'Чаты'),
                      _railButton(
                        1,
                        Icons.call_outlined,
                        'Звонки',
                        pulseBadge: true,
                      ),
                      const Spacer(),
                      _railButton(2, Icons.settings_outlined, 'Настройки'),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(child: body),
          ],
        ),
      );
    return Scaffold(body: body, bottomNavigationBar: _mobileCommandDock());
  }
}
