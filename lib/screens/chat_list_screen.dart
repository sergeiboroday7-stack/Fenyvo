import 'dart:async';
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

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({
    super.key,
  });

  @override
  State<ChatListScreen> createState() =>
      _ChatListScreenState();
}

class _ChatListScreenState
    extends State<ChatListScreen> {
  List<String> _chats = [];
  List<String> _onlineUsers = [];

  bool _isLoading = true;

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

  final Map<String, Timer> _typingTimers = {};

  StreamSubscription<String>? _notificationTapSubscription;

  StreamSubscription<String>? _firebaseNotificationTapSubscription;

  @override
  void initState() {
    super.initState();

    SocketService.instance.addMessageHandler(
      _handleMessage,
    );

    SocketService.instance.getOfflineMessages();

    _notificationTapSubscription =
        NotificationService.instance.notificationTapStream.listen(
      _handleNotificationPayload,
    );

    _firebaseNotificationTapSubscription =
        FirebaseMessagingService.instance.notificationTapStream.listen(
      _handleNotificationPayload,
    );

    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        final localPayload =
            NotificationService.instance.takeInitialPayload();

        final firebasePayload =
            FirebaseMessagingService.instance.takeInitialPayload();

        final payload =
            firebasePayload ??
            localPayload;

        if (payload != null) {
          _handleNotificationPayload(
            payload,
          );
        }
      },
    );

    _loadChats(
      requestAvatars: true,
    );

    _loadOnlineUsers();
  }

  @override
  void dispose() {
    SocketService.instance.removeMessageHandler(
      _handleMessage,
    );

    _notificationTapSubscription?.cancel();
    _notificationTapSubscription = null;

    _firebaseNotificationTapSubscription?.cancel();
    _firebaseNotificationTapSubscription = null;

    for (final timer in _typingTimers.values) {
      timer.cancel();
    }

    _typingTimers.clear();
    _typingUsers.clear();

    _avatarCache.clear();
    _avatarBase64Cache.clear();

    super.dispose();
  }

  // ========================================
  // ЗАГРУЗКА ЧАТОВ
  // ========================================

  void _loadChats({
    bool requestAvatars = false,
  }) {
    final currentUser =
        SocketService.instance.currentUser;

    if (currentUser == null ||
        currentUser.isEmpty) {
      if (!mounted) {
        return;
      }

      setState(() {
        _chats = [];
        _isLoading = false;
      });

      return;
    }

    final storedChats =
        StorageService.getChatUsers(
      currentUser,
    );

    final combined = <String>{};

    combined.addAll(
      storedChats,
    );

    combined.addAll(
      _onlineUsers,
    );

    combined.remove(
      currentUser,
    );

    final chats = combined.toList();

    if (!mounted) {
      return;
    }

    setState(() {
      _chats = chats;
      _isLoading = false;
    });

    if (requestAvatars) {
      _requestMissingAvatars(
        chats,
      );
    }
  }

  // ========================================
  // ОБНОВЛЕНИЕ СПИСКА
  // ========================================

  Future<void> _refreshChats() async {
    _loadChats(
      requestAvatars: true,
    );

    _loadOnlineUsers();

    await Future<void>.delayed(
      const Duration(
        milliseconds: 350,
      ),
    );
  }

  // ========================================
  // ЗАПРОС НЕДОСТАЮЩИХ АВАТАРОК
  // ========================================

  void _requestMissingAvatars(
    List<String> users,
  ) {
    for (final user in users) {
      final avatar =
          StorageService.getAvatar(
        user,
      );

      if (avatar == null ||
          avatar.isEmpty) {
        SocketService.instance.requestAvatar(
          user,
        );
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

  void _setUserTyping(
    String user,
    bool isTyping,
  ) {
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
        _typingUsers.add(
          user,
        );
      });

      _typingTimers[user] =
          Timer(
        const Duration(
          seconds: 4,
        ),
        () {
          if (!mounted) {
            return;
          }

          setState(() {
            _typingUsers.remove(
              user,
            );
          });

          _typingTimers.remove(
            user,
          );
        },
      );

      return;
    }

    if (_typingUsers.contains(user)) {
      setState(() {
        _typingUsers.remove(
          user,
        );
      });
    }
  }

  // ========================================
  // ОБРАБОТКА СООБЩЕНИЙ СЕРВЕРА
  // ========================================

  void _handleMessage(
    Map<String, dynamic> msg,
  ) {
    final type =
        msg['type']?.toString() ?? '';

    final rawData =
        msg['data'];

    final data =
        rawData is Map
            ? Map<String, dynamic>.from(
                rawData,
              )
            : <String, dynamic>{};

    if (type == 'users') {
      final rawUsers =
          data['users'];

      if (rawUsers is! List) {
        return;
      }

      final currentUser =
          SocketService.instance.currentUser ??
              '';

      final users =
          rawUsers
              .map(
                (user) =>
                    user.toString(),
              )
              .where(
                (user) =>
                    user.isNotEmpty &&
                    user != currentUser,
              )
              .toList();

      _onlineUsers = users;

      _loadChats();

      _requestMissingAvatars(
        users,
      );

      return;
    }

    if (type == 'avatar_data') {
      final username =
          data['username']?.toString() ?? '';

      if (username.isNotEmpty) {
        _avatarCache.remove(
          username,
        );

        _avatarBase64Cache.remove(
          username,
        );
      }

      if (mounted) {
        setState(() {});
      }

      return;
    }

    if (type == 'avatar_updated') {
      final username =
          data['username']?.toString() ?? '';

      if (username.isNotEmpty) {
        _avatarCache.remove(
          username,
        );

        _avatarBase64Cache.remove(
          username,
        );
      }

      return;
    }

    // ========================================
    // ПЕЧАТАЕТ В СПИСКЕ ЧАТОВ
    // ========================================

    if (type == 'typing') {
      final currentUser =
          SocketService.instance.currentUser ??
              '';

      final from =
          data['from']
                  ?.toString()
                  .trim() ??
              '';

      final to =
          data['to']
                  ?.toString()
                  .trim() ??
              '';

      final isTyping =
          data['isTyping'] == true;

      if (currentUser.isEmpty ||
          from.isEmpty ||
          from == currentUser ||
          to != currentUser) {
        return;
      }

      _setUserTyping(
        from,
        isTyping,
      );

      return;
    }

    if (type == 'message_edited') {
      final currentUser =
          SocketService.instance.currentUser ??
              '';

      final messageId =
          data['messageId']
                  ?.toString()
                  .trim() ??
              '';

      final from =
          data['from']
                  ?.toString()
                  .trim() ??
              '';

      final to =
          data['to']
                  ?.toString()
                  .trim() ??
              '';

      final newText =
          data['newText']
                  ?.toString()
                  .trim() ??
              '';

      final editedAt =
          data['editedAt']
                  ?.toString()
                  .trim() ??
              DateTime.now()
                  .toIso8601String();

      if (currentUser.isEmpty ||
          messageId.isEmpty ||
          newText.isEmpty ||
          (from != currentUser &&
              to != currentUser)) {
        return;
      }

      final otherUser =
          from == currentUser
              ? to
              : from;

      if (otherUser.isEmpty) {
        return;
      }

      final messages =
          StorageService.getMessages(
        currentUser,
        otherUser,
      );

      var changed = false;

      for (final message in messages) {
        final id =
            message['id']
                    ?.toString()
                    .trim() ??
                '';

        if (id == messageId) {
          message['text'] =
              newText;
          message['isEdited'] =
              true;
          message['editedAt'] =
              editedAt;
          changed = true;
        }

        final rawReply =
            message['replyTo'];

        if (rawReply is Map &&
            rawReply['id']
                    ?.toString()
                    .trim() ==
                messageId) {
          final reply =
              Map<String, dynamic>.from(
            rawReply,
          );

          reply['text'] =
              newText;
          message['replyTo'] =
              reply;
          changed = true;
        }
      }

      if (changed) {
        StorageService.saveMessages(
          currentUser,
          otherUser,
          messages,
        );

        _loadChats();
      }

      return;
    }

    if (type == 'message') {
      final currentUser =
          SocketService.instance.currentUser ??
              '';

      final from =
          data['from']?.toString() ?? '';

      final to =
          data['to']?.toString() ??
              currentUser;

      final text =
          data['text']?.toString() ?? '';

      final time =
          data['time']?.toString() ??
              DateTime.now()
                  .toIso8601String();

      final id =
          data['id']?.toString() ?? '';

      if (currentUser.isEmpty ||
          from.isEmpty ||
          from == currentUser ||
          text.isEmpty) {
        return;
      }

      _setUserTyping(
        from,
        false,
      );

      final messages =
          StorageService.getMessages(
        currentUser,
        from,
      );

      bool alreadyExists = false;

      for (final message in messages) {
        final oldId =
            message['id']?.toString() ?? '';

        if (id.isNotEmpty &&
            oldId.isNotEmpty &&
            oldId == id) {
          alreadyExists = true;
          break;
        }

        final oldFrom =
            message['from']?.toString() ?? '';

        final oldText =
            message['text']?.toString() ?? '';

        final oldTime =
            message['time']?.toString() ?? '';

        if (oldFrom == from &&
            oldText == text &&
            oldTime == time) {
          alreadyExists = true;
          break;
        }
      }

      if (!alreadyExists) {
        messages.add(
          {
            'id': id,
            'from': from,
            'to': to,
            'text': text,
            'time': time,
            'status': 'delivered',
            if (data['replyTo'] is Map)
              'replyTo': Map<String, dynamic>.from(
                data['replyTo'] as Map,
              ),
            if (data['forwardedFrom'] != null)
              'forwardedFrom':
                  data['forwardedFrom'].toString(),
            if (data['forwardComment'] != null)
              'forwardComment':
                  data['forwardComment'].toString(),
            if (data['isEdited'] == true)
              'isEdited': true,
            if (data['editedAt'] != null)
              'editedAt':
                  data['editedAt'].toString(),
          },
        );

        StorageService.saveMessages(
          currentUser,
          from,
          messages,
        );

        StorageService.incrementUnreadCount(
          currentUser,
          from,
        );
      }

      _loadChats();

      return;
    }

    if (type == 'message_sent') {
      final currentUser =
          SocketService.instance.currentUser ??
              '';

      final to =
          data['to']?.toString() ?? '';

      final text =
          data['text']?.toString() ?? '';

      final time =
          data['time']?.toString() ??
              DateTime.now()
                  .toIso8601String();

      final id =
          data['id']?.toString() ?? '';

      if (currentUser.isEmpty ||
          to.isEmpty ||
          text.isEmpty) {
        return;
      }

      final messages =
          StorageService.getMessages(
        currentUser,
        to,
      );

      bool alreadyExists = false;

      for (final message in messages) {
        final oldId =
            message['id']?.toString() ?? '';

        if (id.isNotEmpty &&
            oldId.isNotEmpty &&
            oldId == id) {
          alreadyExists = true;
          break;
        }

        final oldFrom =
            message['from']?.toString() ?? '';

        final oldTo =
            message['to']?.toString() ?? '';

        final oldText =
            message['text']?.toString() ?? '';

        final oldTime =
            message['time']?.toString() ?? '';

        if (oldFrom == currentUser &&
            oldTo == to &&
            oldText == text &&
            oldTime == time) {
          alreadyExists = true;
          break;
        }
      }

      if (!alreadyExists) {
        messages.add(
          {
            'id': id,
            'from': currentUser,
            'to': to,
            'text': text,
            'time': time,
            'status': 'sent',
            if (data['replyTo'] is Map)
              'replyTo': Map<String, dynamic>.from(
                data['replyTo'] as Map,
              ),
            if (data['forwardedFrom'] != null)
              'forwardedFrom':
                  data['forwardedFrom'].toString(),
            if (data['forwardComment'] != null)
              'forwardComment':
                  data['forwardComment'].toString(),
            if (data['isEdited'] == true)
              'isEdited': true,
            if (data['editedAt'] != null)
              'editedAt':
                  data['editedAt'].toString(),
          },
        );

        StorageService.saveMessages(
          currentUser,
          to,
          messages,
        );
      }

      _loadChats();

      return;
    }
  }

  // ========================================
  // НАЖАТИЕ НА УВЕДОМЛЕНИЕ
  // ========================================

  void _handleNotificationPayload(
    String payload,
  ) {
    if (!mounted) {
      return;
    }

    final value =
        payload.trim();

    if (value.isEmpty) {
      return;
    }

    String? user;

    if (value.startsWith('message:')) {
      user =
          value.substring(
        'message:'.length,
      ).trim();
    } else if (value.startsWith('reaction:')) {
      user =
          value.substring(
        'reaction:'.length,
      ).trim();
    }

    if (user == null ||
        user.isEmpty) {
      return;
    }

    final currentUser =
        SocketService.instance.currentUser ?? '';

    if (currentUser.isEmpty ||
        user == currentUser) {
      return;
    }

    print(
      '🔔 Открываем чат из уведомления: $user',
    );

    // При входе именно через шторку очищаем
    // уведомления приложения. Это также убирает
    // системное FCM-уведомление, которое нельзя
    // удалить по локальному ID собеседника.
    unawaited(
      NotificationService.instance.cancelAll(),
    );

    _openChat(
      user,
    );
  }

  // ========================================
  // ОТКРЫТИЕ ЧАТА
  // ========================================

  void _openChat(
    String user,
  ) {
    final currentUser =
        SocketService.instance.currentUser ?? '';

    if (currentUser.isEmpty) {
      return;
    }

    StorageService.clearUnreadCount(
      currentUser,
      user,
    );

    final isDesktopLayout =
        MediaQuery.sizeOf(context).width >= 900;

    if (isDesktopLayout) {
      if (!mounted) {
        return;
      }

      setState(() {
        _selectedDesktopUser = user;
      });

      return;
    }

    if (mounted) {
      setState(() {});
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChatScreen(
          targetUser: user,
        ),
      ),
    ).then(
      (_) {
        if (!mounted) {
          return;
        }

        _loadChats();
        _loadOnlineUsers();
      },
    );
  }

  // ========================================
  // УДАЛЕНИЕ ЧАТА
  // ========================================

  Future<void> _deleteChat(
    String user,
  ) async {
    final currentUser =
        SocketService.instance.currentUser ?? '';

    if (currentUser.isEmpty) {
      return;
    }

    await StorageService.removeChat(
      currentUser,
      user,
    );

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
        content: Text(
          'Чат с $user удалён',
        ),
        backgroundColor:
            Colors.red,
        duration:
            const Duration(
          seconds: 1,
        ),
      ),
    );
  }

  // ========================================
  // ПОСЛЕДНЕЕ СООБЩЕНИЕ
  // ========================================

  String _getLastMessage(
    String user,
  ) {
    final currentUser =
        SocketService.instance.currentUser ?? '';

    if (currentUser.isEmpty) {
      return '';
    }

    final messages =
        StorageService.getMessages(
      currentUser,
      user,
    );

    if (messages.isEmpty) {
      return '';
    }

    return messages.last['text']
            ?.toString() ??
        '';
  }

  // ========================================
  // ВРЕМЯ
  // ========================================

  String _getLastMessageTime(
    String user,
  ) {
    final currentUser =
        SocketService.instance.currentUser ?? '';

    if (currentUser.isEmpty) {
      return '';
    }

    final messages =
        StorageService.getMessages(
      currentUser,
      user,
    );

    if (messages.isEmpty) {
      return '';
    }

    final timeString =
        messages.last['time']
            ?.toString();

    if (timeString == null ||
        timeString.isEmpty) {
      return '';
    }

    try {
      final time =
          DateTime.parse(
        timeString,
      ).toLocal();

      return '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  // ========================================
  // СЧЁТЧИК
  // ========================================

  int _getUnreadCount(
    String user,
  ) {
    final currentUser =
        SocketService.instance.currentUser ?? '';

    if (currentUser.isEmpty) {
      return 0;
    }

    return StorageService.getUnreadCount(
      currentUser,
      user,
    );
  }

  // ========================================
  // ОНЛАЙН
  // ========================================

  bool _isUserOnline(
    String user,
  ) {
    return _onlineUsers.contains(
      user,
    );
  }

  // ========================================
  // АВАТАРКА С КЭШЕМ
  // ========================================

  Widget _buildAvatar(
    String username, {
    double radius = 30,
  }) {
    final avatar =
        StorageService.getAvatar(
      username,
    );

    if (avatar != null &&
        avatar.isNotEmpty) {
      try {
        final cachedBase64 =
            _avatarBase64Cache[
                username];

        MemoryImage? image =
            _avatarCache[
                username];

        if (image == null ||
            cachedBase64 != avatar) {
          final bytes =
              base64Decode(
            avatar,
          );

          image =
              MemoryImage(
            bytes,
          );

          _avatarCache[
              username] = image;

          _avatarBase64Cache[
              username] = avatar;
        }

        return CircleAvatar(
          key: ValueKey(
            'avatar_$username',
          ),
          radius: radius,
          backgroundColor:
              const Color(
            0xFF111111,
          ),
          backgroundImage:
              image,
        );
      } catch (error) {
        print(
          '❌ Ошибка аватарки $username: $error',
        );
      }
    }

    return CircleAvatar(
      key: ValueKey(
        'avatar_fallback_$username',
      ),
      radius: radius,
      backgroundColor:
          const Color(
        0xFFD4AF37,
      ),
      child: Text(
        username.isNotEmpty
            ? username[0].toUpperCase()
            : '?',
        style:
            TextStyle(
          color: Colors.black,
          fontSize:
              radius * 0.72,
          fontWeight:
              FontWeight.bold,
        ),
      ),
    );
  }

  // ========================================
  // УВЕЛИЧЕННАЯ АВАТАРКА
  // ========================================

  void _showAvatarPreview(
    String username,
  ) {
    final avatar =
        StorageService.getAvatar(
      username,
    );

    if (avatar == null ||
        avatar.isEmpty) {
      return;
    }

    try {
      final bytes =
          base64Decode(
        avatar,
      );

      if (bytes.isEmpty) {
        return;
      }

      final image =
          MemoryImage(
        bytes,
      );

      showDialog<void>(
        context: context,
        barrierColor:
            Colors.black.withValues(
          alpha: 0.85,
        ),
        builder: (
          dialogContext,
        ) {
          final screenWidth =
              MediaQuery.of(
            dialogContext,
          ).size.width;

          final size =
              screenWidth > 320
                  ? 260.0
                  : 220.0;

          return Dialog(
            backgroundColor:
                Colors.transparent,
            elevation: 0,
            insetPadding:
                const EdgeInsets.all(
              24,
            ),
            child: GestureDetector(
              onTap: () {
                Navigator.of(
                  dialogContext,
                ).pop();
              },
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  Container(
                    width: size,
                    height: size,
                    decoration:
                        BoxDecoration(
                      shape:
                          BoxShape.circle,
                      border:
                          Border.all(
                        color:
                            const Color(
                          0xFFD4AF37,
                        ),
                        width: 3,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              Colors.black
                                  .withValues(
                            alpha: 0.5,
                          ),
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
                        fit:
                            BoxFit.cover,
                      ),
                    ),
                  ),

                  const SizedBox(
                    height: 18,
                  ),

                  Text(
                    username,
                    style:
                        const TextStyle(
                      color:
                          Colors.white,
                      fontSize: 18,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (error) {
      print(
        '❌ Ошибка увеличения аватарки $username: $error',
      );
    }
  }

  // ========================================
  // СТРОКА ЧАТА
  // ========================================

  Widget _buildChatTile(
    String user,
  ) {
    final lastMessage =
        _getLastMessage(
      user,
    );

    final lastTime =
        _getLastMessageTime(
      user,
    );

    final unreadCount =
        _getUnreadCount(
      user,
    );

    final isOnline =
        _isUserOnline(
      user,
    );

    final isTyping =
        _typingUsers.contains(
      user,
    );

    final isDesktopLayout =
        MediaQuery.sizeOf(context).width >= 900;

    final isSelected =
        _selectedDesktopUser == user &&
        isDesktopLayout;

    return Dismissible(
      key: Key(
        user,
      ),
      direction:
          DismissDirection.endToStart,
      background:
          Container(
        alignment:
            Alignment.centerRight,
        padding:
            const EdgeInsets.only(
          right: 24,
        ),
        color:
            Colors.red.withValues(
          alpha: 0.92,
        ),
        child:
            const Icon(
          Icons.delete,
          color:
              Colors.white,
        ),
      ),
      onDismissed:
          (_) {
        _deleteChat(
          user,
        );
      },
      child: Material(
        color:
            Colors.transparent,
        child: Ink(
          decoration:
              BoxDecoration(
            borderRadius:
                isDesktopLayout
                    ? BorderRadius.circular(
                        12,
                      )
                    : null,
            color:
                isSelected
                    ? null
                    : Colors.black.withValues(
                        alpha:
                            isDesktopLayout
                                ? 0.22
                                : 0.16,
                      ),
            gradient:
                isSelected
                    ? LinearGradient(
                        begin:
                            Alignment.centerLeft,
                        end:
                            Alignment.centerRight,
                        colors: [
                          const Color(
                            0xFFD4AF37,
                          ).withValues(
                            alpha: 0.22,
                          ),
                          const Color(
                            0xFFD4AF37,
                          ).withValues(
                            alpha: 0.07,
                          ),
                          Colors.transparent,
                        ],
                      )
                    : null,
            border:
                isDesktopLayout
                    ? Border.all(
                        color:
                            isSelected
                                ? const Color(
                                    0xFFD4AF37,
                                  ).withValues(
                                    alpha: 0.42,
                                  )
                                : Colors.white.withValues(
                                    alpha: 0.08,
                                  ),
                        width: 0.8,
                      )
                    : Border(
                        bottom:
                            BorderSide(
                          color:
                              isSelected
                                  ? const Color(
                                      0xFFD4AF37,
                                    ).withValues(
                                      alpha: 0.28,
                                    )
                                  : Colors.white.withValues(
                                      alpha: 0.08,
                                    ),
                          width: 0.8,
                        ),
                      ),
          ),
        child: ListTile(
          selected:
              isSelected,
          mouseCursor:
              isDesktopLayout
                  ? SystemMouseCursors.click
                  : MouseCursor.defer,
          hoverColor:
              isDesktopLayout
                  ? const Color(
                      0xFFD4AF37,
                    ).withValues(
                      alpha: 0.075,
                    )
                  : null,
          splashColor:
              isDesktopLayout
                  ? const Color(
                      0xFFD4AF37,
                    ).withValues(
                      alpha: 0.13,
                    )
                  : null,
          focusColor:
              isDesktopLayout
                  ? const Color(
                      0xFFD4AF37,
                    ).withValues(
                      alpha: 0.08,
                    )
                  : null,
          shape:
              isDesktopLayout
                  ? RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                        12,
                      ),
                    )
                  : null,
          dense:
              isDesktopLayout,
          visualDensity:
              isDesktopLayout
                  ? const VisualDensity(
                      horizontal: -0.5,
                      vertical: -0.7,
                    )
                  : null,
          minTileHeight:
              isDesktopLayout
                  ? 82
                  : 96,
          contentPadding:
              EdgeInsets.symmetric(
            horizontal:
                isDesktopLayout
                    ? 14
                    : 18,
            vertical:
                isDesktopLayout
                    ? 4
                    : 8,
          ),
          leading:
              GestureDetector(
            behavior:
                HitTestBehavior.opaque,
            onTap: () {
              _showAvatarPreview(
                user,
              );
            },
            child:
                Stack(
              clipBehavior:
                  Clip.none,
              children: [
                _buildAvatar(
                  user,
                  radius:
                      isDesktopLayout
                          ? 27
                          : 30,
                ),

                if (isOnline)
                  Positioned(
                    right: -1,
                    bottom: 2,
                    child:
                        Container(
                      width:
                          isDesktopLayout
                              ? 14
                              : 16,
                      height:
                          isDesktopLayout
                              ? 14
                              : 16,
                      decoration:
                          BoxDecoration(
                        color:
                            const Color(
                          0xFF25D94F,
                        ),
                        shape:
                            BoxShape.circle,
                        border:
                            Border.all(
                          color:
                              Colors.black,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                Colors.black.withValues(
                              alpha: 0.7,
                            ),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          title:
              Text(
            user,
            maxLines: 1,
            overflow:
                TextOverflow.ellipsis,
            style:
                TextStyle(
              color:
                  Colors.white,
              fontWeight:
                  FontWeight.w600,
              fontSize:
                  isDesktopLayout
                      ? 16
                      : 17,
            ),
          ),

          subtitle:
              Padding(
            padding:
                EdgeInsets.only(
              top:
                  isDesktopLayout
                      ? 4
                      : 7,
            ),
            child:
                AnimatedSwitcher(
              duration:
                  const Duration(
                milliseconds: 180,
              ),
              child:
                  isTyping
                      ? Row(
                          key:
                              ValueKey(
                            'typing_$user',
                          ),
                          mainAxisSize:
                              MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.edit_outlined,
                              size: 14,
                              color:
                                  Color(
                                0xFFD4AF37,
                              ),
                            ),

                            const SizedBox(
                              width: 5,
                            ),

                            Text(
                              'печатает',
                              style:
                                  TextStyle(
                                color:
                                    Color(
                                  0xFFD4AF37,
                                ),
                                fontSize:
                                    isDesktopLayout
                                        ? 13
                                        : 14,
                                fontWeight:
                                    FontWeight.w600,
                              ),
                            ),

                            const SizedBox(
                              width: 5,
                            ),

                            Text(
                              '•••',
                              style:
                                  TextStyle(
                                color:
                                    const Color(
                                  0xFFD4AF37,
                                ).withValues(
                                  alpha: 0.85,
                                ),
                                fontSize:
                                  isDesktopLayout
                                      ? 13
                                      : 14,
                                fontWeight:
                                    FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        )
                      : Align(
                          key:
                              ValueKey(
                            'message_$user',
                          ),
                          alignment:
                              Alignment.centerLeft,
                          child:
                              Text(
                            lastMessage.isEmpty
                                ? 'Нет сообщений'
                                : lastMessage,
                            maxLines: 1,
                            overflow:
                                TextOverflow.ellipsis,
                            style:
                                TextStyle(
                              color:
                                  unreadCount > 0
                                      ? Colors.white
                                      : Colors.white60,
                              fontSize: 14,
                              fontWeight:
                                  unreadCount > 0
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                            ),
                          ),
                        ),
            ),
          ),

          trailing:
              SizedBox(
            width:
                isDesktopLayout
                    ? 52
                    : 58,
            child:
                Column(
              mainAxisSize:
                  MainAxisSize.min,
              mainAxisAlignment:
                  MainAxisAlignment.center,
              crossAxisAlignment:
                  CrossAxisAlignment.end,
              children: [
                if (lastTime.isNotEmpty)
                  Text(
                    lastTime,
                    style:
                        TextStyle(
                      color:
                          unreadCount > 0
                              ? const Color(
                                  0xFFD4AF37,
                                )
                              : Colors.white54,
                      fontSize:
                          isDesktopLayout
                              ? 12
                              : 13,
                      fontWeight:
                          unreadCount > 0
                              ? FontWeight.w600
                              : FontWeight.normal,
                    ),
                  ),

                const SizedBox(
                  height: 3,
                ),

                if (unreadCount > 0)
                  Container(
                    constraints:
                        BoxConstraints(
                      minWidth:
                          isDesktopLayout
                              ? 22
                              : 26,
                      minHeight:
                          isDesktopLayout
                              ? 22
                              : 26,
                    ),
                    alignment:
                        Alignment.center,
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 7,
                    ),
                    decoration:
                        const BoxDecoration(
                      color:
                          Color(
                        0xFFD4AF37,
                      ),
                      shape:
                          BoxShape.circle,
                    ),
                    child:
                        Text(
                      unreadCount > 99
                          ? '99+'
                          : unreadCount
                              .toString(),
                      style:
                          TextStyle(
                        color:
                            Colors.black,
                        fontSize:
                            isDesktopLayout
                                ? 11
                                : 12,
                        fontWeight:
                            FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          onTap: () {
            _openChat(
              user,
            );
          },
        ),
        ),
      ),
    );
  }

  // ========================================
  // ПУСТОЙ СПИСОК
  // ========================================

  Widget _buildEmptyState() {
    return RefreshIndicator(
      color:
          const Color(
        0xFFD4AF37,
      ),
      backgroundColor:
          const Color(
        0xFF111111,
      ),
      onRefresh:
          _refreshChats,
      child: ListView(
        physics:
            const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height:
                MediaQuery.of(
                      context,
                    ).size.height *
                    0.28,
          ),

          const Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color:
                Color(
              0xFFD4AF37,
            ),
          ),

          const SizedBox(
            height: 16,
          ),

          const Center(
            child: Text(
              'Нет чатов',
              style:
                  TextStyle(
                color:
                    Colors.white70,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========================================
  // СПИСОК ЧАТОВ
  // ========================================

  Widget _buildChatList() {
    final isDesktopLayout =
        MediaQuery.sizeOf(context).width >= 900;

    return Stack(
      children: [
        RefreshIndicator(
          color:
              const Color(
            0xFFD4AF37,
          ),
          backgroundColor:
              const Color(
            0xFF111111,
          ),
          onRefresh:
              _refreshChats,
          child:
              ListView.builder(
            physics:
                const AlwaysScrollableScrollPhysics(
              parent:
                  BouncingScrollPhysics(),
            ),
            padding:
                EdgeInsets.fromLTRB(
              isDesktopLayout
                  ? 6
                  : 0,
              isDesktopLayout
                  ? 6
                  : 0,
              isDesktopLayout
                  ? 6
                  : 0,
              isDesktopLayout
                  ? 12
                  : 58,
            ),
            itemCount:
                _chats.length,
            itemBuilder:
                (
              context,
              index,
            ) {
              return _buildChatTile(
                _chats[index],
              );
            },
          ),
        ),

        // ==================================
        // ПОДСКАЗКА ЗАКРЕПЛЕНА СНИЗУ
        // ==================================

        if (!isDesktopLayout)
          Positioned(
          left: 0,
          right: 0,
          bottom: 14,
          child:
              IgnorePointer(
            child:
                Center(
              child:
                  Container(
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                decoration:
                    BoxDecoration(
                  color:
                      Colors.black.withValues(
                    alpha: 0.38,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    20,
                  ),
                ),
                child:
                    Text(
                  'Потяните вниз для обновления',
                  style:
                      TextStyle(
                    color:
                        Colors.white.withValues(
                      alpha: 0.45,
                    ),
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ========================================
  // ЭКРАН
  // ========================================

  Widget _buildChatListPane() {
    return Scaffold(
      backgroundColor:
          Colors.black,
      appBar: AppBar(
        toolbarHeight:
            MediaQuery.sizeOf(context).width >= 900
                ? 68
                : kToolbarHeight,
        backgroundColor:
            Colors.black.withValues(
          alpha: 0.94,
        ),
        surfaceTintColor:
            Colors.transparent,
        shadowColor:
            Colors.transparent,
        elevation: 0,
        centerTitle:
            MediaQuery.sizeOf(context).width < 900,
        titleSpacing:
            MediaQuery.sizeOf(context).width >= 900
                ? 18
                : NavigationToolbar.kMiddleSpacing,
        title:
            MediaQuery.sizeOf(context).width >= 900
                ? const Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        'SPARTAN',
                        style:
                            TextStyle(
                          color:
                              Color(
                            0xFFD4AF37,
                          ),
                          fontSize: 18,
                          fontWeight:
                              FontWeight.w800,
                          letterSpacing: 1.4,
                        ),
                      ),
                      SizedBox(
                        height: 1,
                      ),
                      Text(
                        'ЧАТЫ',
                        style:
                            TextStyle(
                          color:
                              Colors.white54,
                          fontSize: 10,
                          fontWeight:
                              FontWeight.w600,
                          letterSpacing: 2.2,
                        ),
                      ),
                    ],
                  )
                : const Text(
                    'Чаты',
                    style:
                        TextStyle(
                      color:
                          Color(
                        0xFFD4AF37,
                      ),
                      fontSize: 21,
                      fontWeight:
                          FontWeight.w700,
                    ),
                  ),
        bottom:
            PreferredSize(
          preferredSize:
              const Size.fromHeight(
            1,
          ),
          child:
              Container(
            height: 1,
            color:
                MediaQuery.sizeOf(context).width >= 900
                    ? const Color(
                        0xFFD4AF37,
                      ).withValues(
                        alpha: 0.24,
                      )
                    : Colors.white.withValues(
                        alpha: 0.10,
                      ),
          ),
        ),
        actions: [
          IconButton(
            tooltip:
                'Обновить',
            icon:
                Icon(
              Icons.refresh_rounded,
              color:
                  Color(
                0xFFD4AF37,
              ),
              size:
                  MediaQuery.sizeOf(context).width >= 900
                      ? 24
                      : 29,
            ),
            onPressed: () {
              _refreshChats();
            },
          ),
          IconButton(
            tooltip:
                'Настройки',
            icon:
                Icon(
              Icons.settings_outlined,
              color:
                  Color(
                0xFFD4AF37,
              ),
              size:
                  MediaQuery.sizeOf(context).width >= 900
                      ? 24
                      : 29,
            ),
            onPressed: () {
              final currentUser =
                  SocketService
                          .instance
                          .currentUser ??
                      '';

              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      SettingsScreen(
                    username:
                        currentUser,
                    onLogout: () async {
                      final prefs =
                          await SharedPreferences
                              .getInstance();

                      await prefs.setBool(
                        'logged_in',
                        false,
                      );

                      await SocketService
                          .instance
                          .disconnect();

                      if (!mounted) {
                        return;
                      }

                      Navigator.of(
                        this.context,
                      ).pushAndRemoveUntil(
                        MaterialPageRoute(
                          builder: (_) =>
                              const AuthScreen(),
                        ),
                        (route) =>
                            false,
                      );
                    },
                    onDeleteAccount:
                        () {},
                  ),
                ),
              ).then(
                (_) {
                  if (!mounted) {
                    return;
                  }

                  _loadChats(
                    requestAvatars:
                        true,
                  );

                  _loadOnlineUsers();
                },
              );
            },
          ),

          const SizedBox(
            width: 4,
          ),
        ],
      ),
      body: Stack(
        fit:
            StackFit.expand,
        children: [
          Image.asset(
            'assets/images/chat_list_bg.png',
            fit:
                BoxFit.cover,
            alignment:
                Alignment.center,
            filterQuality:
                FilterQuality.high,
            gaplessPlayback:
                true,
          ),

          Container(
            color:
                Colors.black.withValues(
              alpha: 0.24,
            ),
          ),

          if (_isLoading)
            const Center(
              child:
                  CircularProgressIndicator(
                color:
                    Color(
                  0xFFD4AF37,
                ),
              ),
            )
          else if (_chats.isEmpty)
            Stack(
              children: [
                _buildEmptyState(),

                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 14,
                  child:
                      IgnorePointer(
                    child:
                        Center(
                      child:
                          Container(
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration:
                            BoxDecoration(
                          color:
                              Colors.black.withValues(
                            alpha: 0.38,
                          ),
                          borderRadius:
                              BorderRadius.circular(
                            20,
                          ),
                        ),
                        child:
                            Text(
                          'Потяните вниз для обновления',
                          style:
                              TextStyle(
                            color:
                                Colors.white.withValues(
                              alpha: 0.45,
                            ),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          else
            _buildChatList(),
        ],
      ),
    );
  }

  Widget _buildDesktopEmptyChat() {
    return Stack(
      fit:
          StackFit.expand,
      children: [
        Image.asset(
          'assets/images/chat_list_bg.png',
          fit:
              BoxFit.cover,
          alignment:
              Alignment.center,
          filterQuality:
              FilterQuality.high,
        ),

        Container(
          color:
              Colors.black.withValues(
            alpha: 0.63,
          ),
        ),

        Center(
          child:
              Container(
            constraints:
                const BoxConstraints(
              maxWidth: 420,
            ),
            margin:
                const EdgeInsets.all(
              28,
            ),
            padding:
                const EdgeInsets.symmetric(
              horizontal: 34,
              vertical: 30,
            ),
            decoration:
                BoxDecoration(
              color:
                  Colors.black.withValues(
                alpha: 0.62,
              ),
              borderRadius:
                  BorderRadius.circular(
                24,
              ),
              border:
                  Border.all(
                color:
                    const Color(
                  0xFFD4AF37,
                ).withValues(
                  alpha: 0.45,
                ),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      Colors.black.withValues(
                    alpha: 0.55,
                  ),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            child:
                Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                const Icon(
                  Icons.forum_outlined,
                  color:
                      Color(
                    0xFFD4AF37,
                  ),
                  size: 54,
                ),

                const SizedBox(
                  height: 16,
                ),

                const Text(
                  'SPARTAN CHAT',
                  textAlign:
                      TextAlign.center,
                  style:
                      TextStyle(
                    color:
                        Color(
                      0xFFD4AF37,
                    ),
                    fontSize: 24,
                    fontWeight:
                        FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),

                const SizedBox(
                  height: 10,
                ),

                Text(
                  'Выберите чат слева',
                  textAlign:
                      TextAlign.center,
                  style:
                      TextStyle(
                    color:
                        Colors.white.withValues(
                      alpha: 0.78,
                    ),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    final screenWidth =
        MediaQuery.sizeOf(context).width;

    final sidebarWidth =
        screenWidth >= 1700
            ? 400.0
            : screenWidth >= 1300
                ? 365.0
                : 325.0;

    return Scaffold(
      backgroundColor:
          const Color(
        0xFF090909,
      ),
      body:
          Row(
        children: [
          SizedBox(
            width:
                sidebarWidth,
            child:
                _buildChatListPane(),
          ),

          Container(
            width: 2,
            decoration:
                BoxDecoration(
              gradient:
                  LinearGradient(
                begin:
                    Alignment.topCenter,
                end:
                    Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  const Color(
                    0xFFD4AF37,
                  ).withValues(
                    alpha: 0.32,
                  ),
                  const Color(
                    0xFFD4AF37,
                  ).withValues(
                    alpha: 0.72,
                  ),
                  const Color(
                    0xFFD4AF37,
                  ).withValues(
                    alpha: 0.32,
                  ),
                  Colors.transparent,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color:
                      const Color(
                    0xFFD4AF37,
                  ).withValues(
                    alpha: 0.12,
                  ),
                  blurRadius: 10,
                ),
              ],
            ),
          ),

          Expanded(
            child:
                Container(
              color:
                  const Color(
                0xFF090909,
              ),
              alignment:
                  Alignment.center,
              child:
                  _selectedDesktopUser == null
                      ? _buildDesktopEmptyChat()
                      : Center(
                          child:
                              ConstrainedBox(
                            constraints:
                                const BoxConstraints(
                              maxWidth: 1120,
                            ),
                            child:
                                ChatScreen(
                              key:
                                  ValueKey(
                                'desktop_chat_$_selectedDesktopUser',
                              ),
                              targetUser:
                                  _selectedDesktopUser!,
                            ),
                          ),
                        ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    final isDesktopLayout =
        MediaQuery.sizeOf(context).width >= 900;

    if (isDesktopLayout) {
      return _buildDesktopLayout();
    }

    return _buildChatListPane();
  }

}
