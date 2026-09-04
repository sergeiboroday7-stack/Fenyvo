import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/socket_service.dart';
import '../services/storage_service.dart';

class ChatScreen extends StatefulWidget {
  final String targetUser;

  const ChatScreen({
    super.key,
    required this.targetUser,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _messageController =
      TextEditingController();

  final FocusNode _messageFocusNode =
      FocusNode();

  final ScrollController _messageScrollController =
      ScrollController();

  final List<Map<String, dynamic>> _messages = [];

  Map<String, dynamic>? _replyToMessage;

  String? _backgroundPath;
  double _backgroundOpacity = 0.35;
  String? _contactAvatarBase64;
  bool _contactOnline = false;
  DateTime? _contactLastSeen;
  bool _contactIsTyping = false;
  bool _typingSent = false;

  String? _hoveredMessageId;
  bool _sendButtonHovered = false;
  bool _contactAvatarHovered = false;
  bool _showScrollToLatest = false;
  bool _scrollToLatestHovered = false;
  int _newMessagesWhileScrolledUp = 0;

  Timer? _typingStopTimer;
  Timer? _remoteTypingTimeoutTimer;

  late final AnimationController _typingAnimationController;

  static const Color _gold = Color(0xFFD4AF37);
  static const Color _darkGold = Color(0xFF8B6914);

  @override
  void initState() {
    super.initState();

    SocketService.instance.setActiveChatUser(
      widget.targetUser,
    );

    _typingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(
        milliseconds: 1200,
      ),
    )..repeat();

    _messageScrollController.addListener(
      _handleMessageScroll,
    );

    _loadMessages();
    _loadBackgroundSettings();
    _loadContactAvatar();

    SocketService.instance.addMessageHandler(
      _handleMessage,
    );

    _clearUnread();

    SocketService.instance.requestAvatar(
      widget.targetUser,
    );

    SocketService.instance.getUserStatus(
      widget.targetUser,
    );
  }

  @override
  void dispose() {
    SocketService.instance.clearActiveChatUser(
      widget.targetUser,
    );

    if (_typingSent) {
      SocketService.instance.sendTyping(
        widget.targetUser,
        false,
      );
    }

    _typingStopTimer?.cancel();
    _remoteTypingTimeoutTimer?.cancel();

    _typingAnimationController.dispose();

    SocketService.instance.removeMessageHandler(
      _handleMessage,
    );

    _messageScrollController.removeListener(
      _handleMessageScroll,
    );
    _messageScrollController.dispose();

    _messageFocusNode.dispose();
    _messageController.dispose();

    super.dispose();
  }

  // ========================================
  // ЗАГРУЗКА ФОНА
  // ========================================

  Future<void> _loadBackgroundSettings() async {
    final background =
        await StorageService.getBackground();

    final opacity =
        await StorageService.getBackgroundOpacity();

    if (!mounted) {
      return;
    }

    String? validBackground;

    if (background != null &&
        background.isNotEmpty) {
      final file = File(background);

      if (file.existsSync()) {
        validBackground = background;
      }
    }

    setState(() {
      _backgroundPath = validBackground;
      _backgroundOpacity = opacity;
    });
  }

  // ========================================
  // АВАТАР КОНТАКТА
  // ========================================

  void _loadContactAvatar() {
    final avatar =
        StorageService.getAvatar(
      widget.targetUser,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _contactAvatarBase64 = avatar;
    });
  }

  Widget _buildContactAvatar() {
    final avatar = _contactAvatarBase64;

    ImageProvider? imageProvider;

    if (avatar != null &&
        avatar.isNotEmpty) {
      try {
        imageProvider = MemoryImage(
          base64Decode(
            avatar,
          ),
        );
      } catch (_) {
        imageProvider = null;
      }
    }

    final avatarStack =
        Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius:
              Platform.isWindows
                  ? 22
                  : 20,
          backgroundColor:
              const Color(
            0xFF2A2A2A,
          ),
          backgroundImage:
              imageProvider,
          child: imageProvider == null
              ? Text(
                  widget.targetUser.isNotEmpty
                      ? widget.targetUser[0]
                          .toUpperCase()
                      : '?',
                  style:
                      const TextStyle(
                    color: _gold,
                    fontWeight:
                        FontWeight.bold,
                  ),
                )
              : null,
        ),
        if (_contactOnline)
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width:
                  Platform.isWindows
                      ? 13
                      : 12,
              height:
                  Platform.isWindows
                      ? 13
                      : 12,
              decoration:
                  BoxDecoration(
                color:
                    Colors.greenAccent,
                shape:
                    BoxShape.circle,
                border:
                    Border.all(
                  color:
                      const Color(
                    0xFF151515,
                  ),
                  width: 2,
                ),
              ),
            ),
          ),
      ],
    );

    if (!Platform.isWindows) {
      return avatarStack;
    }

    return MouseRegion(
      cursor:
          SystemMouseCursors.basic,
      onEnter: (_) {
        if (!_contactAvatarHovered) {
          setState(
            () {
              _contactAvatarHovered = true;
            },
          );
        }
      },
      onExit: (_) {
        if (_contactAvatarHovered) {
          setState(
            () {
              _contactAvatarHovered = false;
            },
          );
        }
      },
      child:
          AnimatedScale(
        duration:
            const Duration(
          milliseconds: 150,
        ),
        curve:
            Curves.easeOutCubic,
        scale:
            _contactAvatarHovered
                ? 1.045
                : 1.0,
        child:
            AnimatedContainer(
          duration:
              const Duration(
            milliseconds: 260,
          ),
          curve:
              Curves.easeOutCubic,
          padding:
              const EdgeInsets.all(
            2,
          ),
          decoration:
              BoxDecoration(
            shape:
                BoxShape.circle,
            boxShadow:
                (_contactOnline ||
                        _contactIsTyping ||
                        _contactAvatarHovered)
                    ? [
                        BoxShadow(
                          color:
                              (_contactIsTyping
                                      ? _gold
                                      : _contactOnline
                                          ? Colors.greenAccent
                                          : _gold)
                                  .withValues(
                            alpha:
                                _contactAvatarHovered
                                    ? 0.24
                                    : 0.18,
                          ),
                          blurRadius:
                              _contactAvatarHovered
                                  ? 18
                                  : 14,
                          spreadRadius:
                              _contactAvatarHovered
                                  ? 1.5
                                  : 1,
                        ),
                      ]
                    : const [],
          ),
          child:
              avatarStack,
        ),
      ),
    );
  }

  // ========================================
  // СТАТУС КОНТАКТА
  // ========================================

  String _formatContactStatus() {
    if (_contactOnline) {
      return 'в сети';
    }

    final lastSeen =
        _contactLastSeen;

    if (lastSeen == null) {
      return 'не в сети';
    }

    final local =
        lastSeen.toLocal();

    final now =
        DateTime.now();

    final today =
        DateTime(
      now.year,
      now.month,
      now.day,
    );

    final seenDay =
        DateTime(
      local.year,
      local.month,
      local.day,
    );

    final difference =
        today.difference(
      seenDay,
    ).inDays;

    final time =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';

    if (difference == 0) {
      return 'был(а) в сети сегодня в $time';
    }

    if (difference == 1) {
      return 'был(а) в сети вчера в $time';
    }

    final date =
        '${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')}.'
        '${local.year}';

    return 'был(а) в сети $date в $time';
  }

  // ========================================
  // TYPING — ОТПРАВКА
  // ========================================

  void _handleTextChanged(
    String value,
  ) {
    final hasText =
        value.trim().isNotEmpty;

    _typingStopTimer?.cancel();

    if (!hasText) {
      _stopTyping();
      return;
    }

    if (!_typingSent) {
      _typingSent = true;

      SocketService.instance.sendTyping(
        widget.targetUser,
        true,
      );
    }

    _typingStopTimer =
        Timer(
      const Duration(
        milliseconds: 1400,
      ),
      _stopTyping,
    );
  }

  void _stopTyping() {
    _typingStopTimer?.cancel();
    _typingStopTimer = null;

    if (!_typingSent) {
      return;
    }

    _typingSent = false;

    SocketService.instance.sendTyping(
      widget.targetUser,
      false,
    );
  }

  // ========================================
  // TYPING — ПОЛУЧЕНИЕ
  // ========================================

  void _setContactTyping(
    bool isTyping,
  ) {
    _remoteTypingTimeoutTimer?.cancel();

    if (!mounted) {
      return;
    }

    if (_contactIsTyping != isTyping) {
      setState(() {
        _contactIsTyping = isTyping;
      });
    }

    if (isTyping) {
      _remoteTypingTimeoutTimer =
          Timer(
        const Duration(
          seconds: 4,
        ),
        () {
          if (!mounted) {
            return;
          }

          setState(() {
            _contactIsTyping = false;
          });
        },
      );
    }
  }

  // ========================================
  // АНИМИРОВАННЫЕ ТОЧКИ
  // ========================================

  Widget _buildTypingDots() {
    return AnimatedBuilder(
      animation:
          _typingAnimationController,
      builder: (
        context,
        child,
      ) {
        final progress =
            _typingAnimationController.value;

        final activeIndex =
            (progress * 3).floor() % 3;

        return Row(
          mainAxisSize:
              MainAxisSize.min,
          children:
              List.generate(
            3,
            (index) {
              final active =
                  index == activeIndex;

              return AnimatedContainer(
                duration:
                    const Duration(
                  milliseconds: 180,
                ),
                margin:
                    const EdgeInsets.symmetric(
                  horizontal: 2,
                ),
                width: active ? 7 : 5,
                height: active ? 7 : 5,
                decoration:
                    BoxDecoration(
                  shape:
                      BoxShape.circle,
                  color:
                      _gold.withValues(
                    alpha:
                        active
                            ? 1.0
                            : 0.40,
                  ),
                  boxShadow:
                      active
                          ? [
                              BoxShadow(
                                color:
                                    _gold.withValues(
                                  alpha:
                                      0.35,
                                ),
                                blurRadius:
                                    5,
                              ),
                            ]
                          : null,
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return AnimatedSwitcher(
      duration:
          const Duration(
        milliseconds: 180,
      ),
      child:
          !_contactIsTyping
              ? const SizedBox.shrink()
              : Container(
                  key:
                      const ValueKey(
                    'typing_indicator',
                  ),
                  width:
                      double.infinity,
                  padding:
                      const EdgeInsets.fromLTRB(
                    18,
                    7,
                    18,
                    5,
                  ),
                  color:
                      const Color(
                    0xE61A1A1A,
                  ),
                  child:
                      Row(
                    children: [
                      const Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: _gold,
                      ),
                      const SizedBox(
                        width: 7,
                      ),
                      Flexible(
                        child: Text(
                          '${widget.targetUser} печатает',
                          maxLines: 1,
                          overflow:
                              TextOverflow.ellipsis,
                          style:
                              const TextStyle(
                            color:
                                Colors.white70,
                            fontSize: 12,
                            fontWeight:
                                FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(
                        width: 7,
                      ),
                      _buildTypingDots(),
                    ],
                  ),
                ),
    );
  }

  // ========================================
  // ЗАГРУЗКА СООБЩЕНИЙ
  // ========================================

  void _loadMessages() {
    final currentUser =
        SocketService.instance.currentUser;

    if (currentUser == null ||
        currentUser.isEmpty) {
      return;
    }

    final savedMessages =
        StorageService.getMessages(
      currentUser,
      widget.targetUser,
    );

    setState(() {
      _messages.clear();

      for (final savedMessage
          in savedMessages) {
        final message =
            Map<String, dynamic>.from(
          savedMessage,
        );

        _normalizeReactionUsers(
          message,
        );

        final isMe =
            message['isMe'] == true ||
                message['from']
                        ?.toString() ==
                    currentUser;

        message['isMe'] = isMe;

        if (isMe) {
          final status =
              message['status']
                      ?.toString()
                      .trim() ??
                  '';

          if (status.isEmpty) {
            message['status'] =
                'sent';
          }
        }

        _messages.add(
          message,
        );
      }
    });

    _markIncomingMessagesRead();
  }

  // ========================================
  // СОХРАНЕНИЕ СООБЩЕНИЙ
  // ========================================

  void _saveMessages() {
    final currentUser =
        SocketService.instance.currentUser;

    if (currentUser == null ||
        currentUser.isEmpty) {
      return;
    }

    StorageService.saveMessages(
      currentUser,
      widget.targetUser,
      _messages,
    );
  }

  // ========================================
  // ОЧИСТКА НЕПРОЧИТАННЫХ
  // ========================================

  void _clearUnread() {
    final currentUser =
        SocketService.instance.currentUser;

    if (currentUser == null ||
        currentUser.isEmpty) {
      return;
    }

    StorageService.clearUnreadCount(
      currentUser,
      widget.targetUser,
    );
  }

  // ========================================
  // СТАТУС СООБЩЕНИЯ
  // ========================================

  int _messageStatusRank(
    String status,
  ) {
    switch (status) {
      case 'read':
        return 3;
      case 'delivered':
        return 2;
      case 'sent':
        return 1;
      default:
        return 0;
    }
  }

  void _updateMessageStatus(
    String messageId,
    String newStatus,
  ) {
    final id = messageId.trim();

    if (id.isEmpty) {
      return;
    }

    final messageIndex =
        _messages.indexWhere(
      (message) =>
          message['id']
                  ?.toString()
                  .trim() ==
              id,
    );

    if (messageIndex == -1) {
      return;
    }

    final message =
        _messages[messageIndex];

    if (message['isMe'] != true) {
      return;
    }

    final oldStatus =
        message['status']
                ?.toString()
                .trim() ??
            '';

    if (_messageStatusRank(
          newStatus,
        ) <=
        _messageStatusRank(
          oldStatus,
        )) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _messages[messageIndex]
              ['status'] =
          newStatus;
    });

    _saveMessages();
  }

  // ========================================
  // ПРОЧТЕНИЕ ВХОДЯЩИХ СООБЩЕНИЙ
  // ========================================

  void _markIncomingMessagesRead() {
    final currentUser =
        SocketService.instance.currentUser ??
            '';

    if (currentUser.isEmpty ||
        !SocketService.instance.isConnected) {
      return;
    }

    bool changed = false;

    for (final message in _messages) {
      final from =
          message['from']
                  ?.toString()
                  .trim() ??
              '';

      final to =
          message['to']
                  ?.toString()
                  .trim() ??
              '';

      final messageId =
          message['id']
                  ?.toString()
                  .trim() ??
              '';

      final alreadyRead =
          message['readByMe'] == true;

      if (from != widget.targetUser ||
          to != currentUser ||
          messageId.isEmpty ||
          alreadyRead) {
        continue;
      }

      SocketService.instance.sendMessageRead(
        messageId: messageId,
        from: from,
        to: to,
      );

      message['readByMe'] = true;

      changed = true;
    }

    if (changed) {
      _saveMessages();
    }
  }

  // ========================================
  // ID СООБЩЕНИЯ
  // ========================================

  String _getMessageId(
    Map<String, dynamic> message,
  ) {
    final id =
        message['id']
                ?.toString()
                .trim() ??
            '';

    if (id.isNotEmpty) {
      return id;
    }

    final from =
        message['from']
                ?.toString() ??
            '';

    final to =
        message['to']
                ?.toString() ??
            '';

    final time =
        message['time']
                ?.toString() ??
            '';

    final text =
        message['text']
                ?.toString() ??
            '';

    return 'legacy:'
        '${Uri.encodeComponent(from)}:'
        '${Uri.encodeComponent(to)}:'
        '${Uri.encodeComponent(time)}:'
        '${Uri.encodeComponent(text)}';
  }

  // ========================================
  // ПОЛЬЗОВАТЕЛИ РЕАКЦИИ
  // ========================================

  List<String> _getReactionUsers(
    Map<String, dynamic> message,
  ) {
    final rawUsers =
        message['reactionUsers'];

    if (rawUsers is! List) {
      return <String>[];
    }

    final result = <String>[];

    for (final rawUser in rawUsers) {
      final user =
          rawUser.toString().trim();

      if (user.isEmpty ||
          result.contains(user)) {
        continue;
      }

      result.add(user);

      if (result.length == 2) {
        break;
      }
    }

    return result;
  }

  void _normalizeReactionUsers(
    Map<String, dynamic> message,
  ) {
    final users =
        _getReactionUsers(
      message,
    );

    message['reactionUsers'] = users;

    message.remove(
      'reaction',
    );
  }

  // ========================================
  // ПОЛУЧЕНИЕ СОБЫТИЙ ОТ СЕРВЕРА
  // ========================================

  void _handleMessage(
    Map<String, dynamic> msg,
  ) {
    final type =
        msg['type']?.toString() ?? '';

    final rawData =
        msg['data'];

    final Map<String, dynamic> data =
        rawData is Map
            ? Map<String, dynamic>.from(
                rawData,
              )
            : <String, dynamic>{};

    final currentUser =
        SocketService.instance.currentUser ??
            '';

    if (type == 'avatar_data') {
      final username =
          data['username']
                  ?.toString()
                  .trim() ??
              '';

      if (username == widget.targetUser) {
        _loadContactAvatar();
      }

      return;
    }

    if (type == 'avatar_updated') {
      final username =
          data['username']
                  ?.toString()
                  .trim() ??
              '';

      if (username == widget.targetUser) {
        SocketService.instance.requestAvatar(
          widget.targetUser,
        );
      }

      return;
    }

    if (type == 'user_status') {
      final username =
          data['username']
                  ?.toString()
                  .trim() ??
              '';

      if (username != widget.targetUser) {
        return;
      }

      final online =
          data['online'] == true;

      final lastSeenRaw =
          data['lastSeen']
                  ?.toString()
                  .trim() ??
              '';

      DateTime? lastSeen;

      if (lastSeenRaw.isNotEmpty) {
        lastSeen =
            DateTime.tryParse(
          lastSeenRaw,
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _contactOnline = online;
        _contactLastSeen = lastSeen;
      });

      return;
    }

    if (type == 'typing') {
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

      final belongsToThisChat =
          from == widget.targetUser &&
              to == currentUser;

      if (!belongsToThisChat) {
        return;
      }

      _setContactTyping(
        isTyping,
      );

      return;
    }

    if (type == 'message_edited') {
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

      final belongsToThisChat =
          (from == widget.targetUser &&
                  to == currentUser) ||
              (from == currentUser &&
                  to == widget.targetUser);

      if (!belongsToThisChat ||
          messageId.isEmpty ||
          newText.isEmpty) {
        return;
      }

      var changed = false;

      if (mounted) {
        setState(() {
          for (final message in _messages) {
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
        });
      }

      if (changed) {
        _saveMessages();
      }

      return;
    }

    if (type == 'message') {
      final id =
          data['id']
                  ?.toString()
                  .trim() ??
              '';

      final from =
          data['from']?.toString() ?? '';

      final to =
          data['to']?.toString() ?? '';

      final text =
          data['text']?.toString() ?? '';

      final time =
          data['time']?.toString() ??
              DateTime.now()
                  .toIso8601String();

      final belongsToThisChat =
          (from == widget.targetUser &&
                  to == currentUser) ||
              (from == currentUser &&
                  to == widget.targetUser);

      if (!belongsToThisChat) {
        return;
      }

      if (from == widget.targetUser) {
        _setContactTyping(
          false,
        );
      }

      _addMessageIfNotExists(
        {
          'id': id,
          'from': from,
          'to': to,
          'text': text,
          'isMe':
              from == currentUser,
          'time': time,
          'reactionUsers':
              <String>[],
          'readByMe':
              from == widget.targetUser &&
                  to == currentUser,
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

      if (from == widget.targetUser &&
          to == currentUser &&
          id.isNotEmpty) {
        SocketService.instance
            .sendMessageRead(
          messageId: id,
          from: from,
          to: to,
        );
      }

      return;
    }

    if (type == 'message_sent') {
      final id =
          data['id']
                  ?.toString()
                  .trim() ??
              '';

      final from =
          data['from']?.toString() ?? '';

      final to =
          data['to']?.toString() ?? '';

      final text =
          data['text']?.toString() ?? '';

      final time =
          data['time']?.toString() ??
              DateTime.now()
                  .toIso8601String();

      if (from != currentUser ||
          to != widget.targetUser) {
        return;
      }

      _addMessageIfNotExists(
        {
          'id': id,
          'from': from,
          'to': to,
          'text': text,
          'isMe': true,
          'time': time,
          'status': 'sent',
          'reactionUsers':
              <String>[],
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

      return;
    }

    if (type == 'message_delivered') {
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

      if (messageId.isEmpty ||
          from != currentUser ||
          to != widget.targetUser) {
        return;
      }

      _updateMessageStatus(
        messageId,
        'delivered',
      );

      return;
    }

    if (type == 'message_read') {
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

      if (messageId.isEmpty ||
          from != currentUser ||
          to != widget.targetUser) {
        return;
      }

      _updateMessageStatus(
        messageId,
        'read',
      );

      return;
    }

    if (type == 'reaction_update') {
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

      if (messageId.isEmpty) {
        return;
      }

      final belongsToThisChat =
          (from == currentUser &&
                  to == widget.targetUser) ||
              (from == widget.targetUser &&
                  to == currentUser);

      if (!belongsToThisChat) {
        return;
      }

      final rawUsers =
          data['users'];

      final reactionUsers =
          <String>[];

      if (rawUsers is List) {
        for (final rawUser
            in rawUsers) {
          final user =
              rawUser.toString().trim();

          if (user.isEmpty ||
              reactionUsers.contains(user)) {
            continue;
          }

          reactionUsers.add(user);

          if (reactionUsers.length == 2) {
            break;
          }
        }
      }

      final messageIndex =
          _messages.indexWhere(
        (message) =>
            _getMessageId(message) ==
                messageId,
      );

      if (messageIndex == -1) {
        return;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _messages[messageIndex]
                ['reactionUsers'] =
            reactionUsers;

        _messages[messageIndex].remove(
          'reaction',
        );
      });

      _saveMessages();

      return;
    }
  }

  // ========================================
  // ДОБАВЛЕНИЕ СООБЩЕНИЯ БЕЗ ДУБЛЕЙ
  // ========================================

  void _addMessageIfNotExists(
    Map<String, dynamic> newMessage,
  ) {
    _normalizeReactionUsers(
      newMessage,
    );

    final newId =
        newMessage['id']
                ?.toString()
                .trim() ??
            '';

    final exists =
        _messages.any(
      (message) {
        final existingId =
            message['id']
                    ?.toString()
                    .trim() ??
                '';

        if (newId.isNotEmpty &&
            existingId.isNotEmpty) {
          return newId == existingId;
        }

        return message['from'] ==
                newMessage['from'] &&
            message['to'] ==
                newMessage['to'] &&
            message['text'] ==
                newMessage['text'] &&
            message['time'] ==
                newMessage['time'];
      },
    );

    if (exists) {
      return;
    }

    if (!mounted) {
      return;
    }

    final isIncomingMessage =
        newMessage['isMe'] != true;

    final shouldCountAsNew =
        Platform.isWindows &&
            isIncomingMessage &&
            _showScrollToLatest;

    setState(() {
      _messages.add(
        newMessage,
      );

      if (shouldCountAsNew) {
        _newMessagesWhileScrolledUp++;
      }
    });

    _saveMessages();
    _clearUnread();
  }

  void _focusMessageComposer() {
    if (!Platform.isWindows ||
        !mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback(
      (_) {
        if (!mounted ||
            !_messageFocusNode.canRequestFocus) {
          return;
        }

        _messageFocusNode.requestFocus();
      },
    );
  }

  // ========================================
  // ОТПРАВКА СООБЩЕНИЯ
  // ========================================

  void _sendMessage() {
    final text =
        _messageController.text.trim();

    if (text.isEmpty) {
      return;
    }

    if (!SocketService.instance.isConnected) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Нет подключения к серверу',
          ),
          backgroundColor:
              Colors.red,
        ),
      );

      return;
    }

    _stopTyping();

    Map<String, dynamic>? replyTo;

    final selectedReply =
        _replyToMessage;

    if (selectedReply != null) {
      final replyId =
          _getMessageId(
        selectedReply,
      );

      final replyFrom =
          selectedReply['from']
                  ?.toString()
                  .trim() ??
              '';

      final replyText =
          selectedReply['text']
                  ?.toString()
                  .trim() ??
              '';

      if (replyId.isNotEmpty &&
          replyFrom.isNotEmpty &&
          replyText.isNotEmpty) {
        replyTo = {
          'id': replyId,
          'from': replyFrom,
          'text': replyText,
        };
      }
    }

    SocketService.instance.sendMessage(
      widget.targetUser,
      text,
      replyTo: replyTo,
    );

    _messageController.clear();

    if (_replyToMessage != null &&
        mounted) {
      setState(() {
        _replyToMessage = null;
      });
    }

    _focusMessageComposer();
  }

  // ========================================
  // ОТВЕТ НА СООБЩЕНИЕ
  // ========================================

  void _startReply(
    Map<String, dynamic> message,
  ) {
    if (!mounted) {
      return;
    }

    setState(() {
      _replyToMessage =
          Map<String, dynamic>.from(
        message,
      );
    });

    _focusMessageComposer();
  }

  void _cancelReply() {
    if (_replyToMessage == null ||
        !mounted) {
      return;
    }

    setState(() {
      _replyToMessage = null;
    });

    _focusMessageComposer();
  }

  Widget _buildReplyPreview(
    Map<String, dynamic> replyTo, {
    required bool isMe,
  }) {
    final replyFrom =
        replyTo['from']
                ?.toString()
                .trim() ??
            '';

    final replyText =
        replyTo['text']
                ?.toString()
                .trim() ??
            '';

    if (replyText.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentUser =
        SocketService.instance.currentUser ??
            '';

    final author =
        replyFrom == currentUser
            ? 'Вы'
            : replyFrom;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(
        bottom: 7,
      ),
      padding: const EdgeInsets.fromLTRB(
        10,
        7,
        10,
        7,
      ),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.black.withValues(
                alpha: 0.18,
              )
            : Colors.black.withValues(
                alpha: 0.32,
              ),
        borderRadius: BorderRadius.circular(
          10,
        ),
        border: Border.all(
          color:
              isMe
                  ? Colors.black54
                  : _gold.withValues(
                      alpha: 0.55,
                    ),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          if (author.isNotEmpty)
            Text(
              author,
              maxLines: 1,
              overflow:
                  TextOverflow.ellipsis,
              style: TextStyle(
                color: isMe
                    ? Colors.black87
                    : _gold,
                fontSize: 11,
                fontWeight:
                    FontWeight.w700,
              ),
            ),
          if (author.isNotEmpty)
            const SizedBox(
              height: 2,
            ),
          Text(
            replyText,
            maxLines: 2,
            overflow:
                TextOverflow.ellipsis,
            style: TextStyle(
              color: isMe
                  ? Colors.black87
                  : Colors.white70,
              fontSize: 11.5,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposerReplyPreview() {
    final reply =
        _replyToMessage;

    if (reply == null) {
      return const SizedBox.shrink();
    }

    final currentUser =
        SocketService.instance.currentUser ??
            '';

    final from =
        reply['from']
                ?.toString()
                .trim() ??
            '';

    final text =
        reply['text']
                ?.toString()
                .trim() ??
            '';

    final author =
        from == currentUser
            ? 'Вы'
            : from;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(
        14,
        8,
        8,
        8,
      ),
      decoration: BoxDecoration(
        color: const Color(
          0xF21A1A1A,
        ),
        border: Border(
          top: BorderSide(
            color: _gold.withValues(
              alpha: 0.22,
            ),
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 38,
            decoration: BoxDecoration(
              color: _gold,
              borderRadius:
                  BorderRadius.circular(
                3,
              ),
              boxShadow: [
                BoxShadow(
                  color: _gold.withValues(
                    alpha: 0.30,
                  ),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  author.isEmpty
                      ? 'Ответ'
                      : author,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style:
                      const TextStyle(
                    color: _gold,
                    fontSize: 12,
                    fontWeight:
                        FontWeight.w700,
                  ),
                ),
                const SizedBox(
                  height: 2,
                ),
                Text(
                  text,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style:
                      const TextStyle(
                    color:
                        Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (Platform.isWindows) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 3,
              ),
              decoration:
                  BoxDecoration(
                color:
                    _gold.withValues(
                  alpha: 0.08,
                ),
                borderRadius:
                    BorderRadius.circular(
                  5,
                ),
                border:
                    Border.all(
                  color:
                      _gold.withValues(
                    alpha: 0.18,
                  ),
                  width: 0.7,
                ),
              ),
              child:
                  const Text(
                'ESC',
                style:
                    TextStyle(
                  color:
                      Colors.white54,
                  fontSize: 9,
                  fontWeight:
                      FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(
              width: 2,
            ),
          ],
          IconButton(
            onPressed: _cancelReply,
            visualDensity:
                VisualDensity.compact,
            icon: const Icon(
              Icons.close_rounded,
              color: _gold,
              size: 21,
            ),
          ),
        ],
      ),
    );
  }

  // ========================================
  // ОТПРАВКА РЕАКЦИИ
  // ========================================

  void _sendReaction(
    Map<String, dynamic> message,
  ) {
    final currentUser =
        SocketService.instance.currentUser ??
            '';

    if (currentUser.isEmpty) {
      return;
    }

    if (!SocketService.instance.isConnected) {
      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Нет подключения к серверу',
          ),
          backgroundColor:
              Colors.red,
        ),
      );

      return;
    }

    final users =
        _getReactionUsers(
      message,
    );

    if (users.contains(currentUser)) {
      return;
    }

    if (users.length >= 2) {
      return;
    }

    final from =
        message['from']
                ?.toString()
                .trim() ??
            '';

    final to =
        message['to']
                ?.toString()
                .trim() ??
            '';

    if (from.isEmpty ||
        to.isEmpty) {
      return;
    }

    final messageId =
        _getMessageId(
      message,
    );

    if (messageId.isEmpty) {
      return;
    }

    SocketService.instance.sendMessageReaction(
      messageId: messageId,
      from: from,
      to: to,
      reaction: '❤️',
    );
  }

  // ========================================
  // ВРЕМЯ СООБЩЕНИЯ
  // ========================================

  String _formatTime(
    dynamic timeData,
  ) {
    if (timeData == null) {
      return '';
    }

    try {
      final time =
          DateTime.parse(
        timeData.toString(),
      ).toLocal();

      return '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  // ========================================
  // ФОН
  // ========================================

  Widget _buildBackground() {
    final backgroundPath =
        _backgroundPath;

    if (backgroundPath == null ||
        backgroundPath.isEmpty) {
      return const Positioned.fill(
        child: ColoredBox(
          color:
              Color(0xFF0A0A0A),
        ),
      );
    }

    final file =
        File(
      backgroundPath,
    );

    if (!file.existsSync()) {
      return const Positioned.fill(
        child: ColoredBox(
          color:
              Color(0xFF0A0A0A),
        ),
      );
    }

    return Positioned.fill(
      child: ColoredBox(
        color:
            const Color(
          0xFF0A0A0A,
        ),
        child: Opacity(
          opacity:
              _backgroundOpacity,
          child: Image.file(
            file,
            fit: BoxFit.cover,
            alignment:
                Alignment.center,
            gaplessPlayback:
                true,
            filterQuality:
                FilterQuality.medium,
          ),
        ),
      ),
    );
  }

  // ========================================
  // ОДНО ЗОЛОТОЕ СЕРДЕЧКО
  // ========================================

  Widget _buildHeartIcon({
    required bool filled,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      behavior:
          HitTestBehavior.opaque,
      onTap:
          enabled ? onTap : null,
      child: Container(
        width: 30,
        height: 30,
        alignment:
            Alignment.center,
        decoration:
            BoxDecoration(
          shape: BoxShape.circle,
          color:
              Colors.black.withValues(
            alpha: 0.72,
          ),
          border:
              Border.all(
            color:
                _gold.withValues(
              alpha:
                  enabled
                      ? 0.95
                      : 0.70,
            ),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color:
                  Colors.black.withValues(
                alpha: 0.35,
              ),
              blurRadius: 5,
              offset:
                  const Offset(
                0,
                2,
              ),
            ),
          ],
        ),
        child: Icon(
          filled
              ? Icons.favorite
              : Icons.favorite_border,
          color: _gold,
          size: 18,
        ),
      ),
    );
  }

  // ========================================
  // РЯД СЕРДЕЧЕК
  // ========================================

  Widget _buildReactionRow(
    Map<String, dynamic> message,
  ) {
    final currentUser =
        SocketService.instance.currentUser ??
            '';

    final users =
        _getReactionUsers(
      message,
    );

    final count = users.length;

    final currentUserReacted =
        users.contains(
      currentUser,
    );

    if (count == 0) {
      return _buildHeartIcon(
        filled: false,
        enabled:
            currentUser.isNotEmpty,
        onTap: () {
          _sendReaction(
            message,
          );
        },
      );
    }

    if (count == 1) {
      return Row(
        mainAxisSize:
            MainAxisSize.min,
        children: [
          _buildHeartIcon(
            filled: true,
            enabled: false,
            onTap: null,
          ),
          const SizedBox(
            width: 4,
          ),
          _buildHeartIcon(
            filled: false,
            enabled:
                currentUser.isNotEmpty &&
                    !currentUserReacted,
            onTap: () {
              _sendReaction(
                message,
              );
            },
          ),
        ],
      );
    }

    return Row(
      mainAxisSize:
          MainAxisSize.min,
      children: [
        _buildHeartIcon(
          filled: true,
          enabled: false,
          onTap: null,
        ),
        const SizedBox(
          width: 4,
        ),
        _buildHeartIcon(
          filled: true,
          enabled: false,
          onTap: null,
        ),
      ],
    );
  }

  // ========================================
  // ГАЛОЧКИ СТАТУСА
  // ========================================

  Widget _buildMessageStatus(
    Map<String, dynamic> message,
  ) {
    final status =
        message['status']
                ?.toString()
                .trim() ??
            'sent';

    final isRead =
        status == 'read';

    return Text(
      isRead ? '✓✓' : '✓',
      style:
          const TextStyle(
        color: _gold,
        fontSize: 14,
        fontWeight:
            FontWeight.w900,
        height: 1,
        shadows: [
          Shadow(
            color: _gold,
            blurRadius: 6,
          ),
          Shadow(
            color:
                Color(
              0x99FFF2A8,
            ),
            blurRadius: 10,
          ),
        ],
      ),
    );
  }

  // ========================================
  // МЕНЮ ПО ДОЛГОМУ НАЖАТИЮ
  // ========================================

  void _showComingSoon(
    String action,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(
          '$action — подключим следующим шагом',
        ),
        backgroundColor:
            const Color(
          0xFF1A1A1A,
        ),
        duration:
            const Duration(
          milliseconds: 1200,
        ),
      ),
    );
  }

  Future<void> _copyMessageText(
    Map<String, dynamic> message,
  ) async {
    final text =
        message['text']?.toString() ??
            '';

    if (text.isEmpty) {
      return;
    }

    await Clipboard.setData(
      ClipboardData(
        text: text,
      ),
    );

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      const SnackBar(
        content: Text(
          'Сообщение скопировано',
        ),
        backgroundColor:
            Color(
          0xFF1A1A1A,
        ),
        duration:
            Duration(
          milliseconds: 1000,
        ),
      ),
    );
  }

  Future<void> _editMessage(
    Map<String, dynamic> message,
  ) async {
    final currentUser =
        SocketService.instance.currentUser ??
            '';
    final messageFrom =
        message['from']?.toString().trim() ??
            '';
    final messageId =
        _getMessageId(message);
    final oldText =
        message['text']?.toString().trim() ??
            '';
    final forwardedFrom =
        message['forwardedFrom']
                ?.toString()
                .trim() ??
            '';

    if (currentUser.isEmpty ||
        messageFrom != currentUser ||
        messageId.isEmpty ||
        oldText.isEmpty ||
        forwardedFrom.isNotEmpty) {
      return;
    }

    if (!SocketService.instance.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(
          const SnackBar(
            content: Text(
              'Для редактирования нужен интернет',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final controller =
        TextEditingController(text: oldText);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );

    if (!mounted) {
      controller.dispose();
      return;
    }

    final newText =
        await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        var canSave = false;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final keyboardHeight =
                MediaQuery.viewInsetsOf(
              sheetContext,
            ).bottom;

            return AnimatedPadding(
              duration: const Duration(
                milliseconds: 180,
              ),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                bottom: keyboardHeight,
              ),
              child: SafeArea(
                top: false,
                child: Container(
                  decoration:
                      const BoxDecoration(
                    color: Color(0xFF161616),
                    borderRadius:
                        BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  padding:
                      const EdgeInsets.fromLTRB(
                    18,
                    10,
                    18,
                    18,
                  ),
                  child: Column(
                    mainAxisSize:
                        MainAxisSize.min,
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Align(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius:
                                BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Row(
                        children: [
                          Icon(
                            Icons.edit_rounded,
                            color: _gold,
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Изменить сообщение',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight:
                                  FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        minLines: 1,
                        maxLines: 5,
                        maxLength: 4000,
                        textCapitalization:
                            TextCapitalization.sentences,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                        cursorColor: _gold,
                        onChanged: (value) {
                          final next = value.trim();
                          final enabled =
                              next.isNotEmpty &&
                                  next != oldText;

                          if (enabled != canSave) {
                            setSheetState(() {
                              canSave = enabled;
                            });
                          }
                        },
                        decoration: InputDecoration(
                          hintText: 'Текст сообщения',
                          hintStyle:
                              const TextStyle(
                            color: Colors.white38,
                          ),
                          counterStyle:
                              const TextStyle(
                            color: Colors.white38,
                          ),
                          filled: true,
                          fillColor:
                              const Color(0xFF222222),
                          prefixIcon: const Icon(
                            Icons
                                .chat_bubble_outline_rounded,
                            color: _gold,
                          ),
                          enabledBorder:
                              OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: _gold.withValues(
                                alpha: 0.45,
                              ),
                            ),
                          ),
                          focusedBorder:
                              OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(16),
                            borderSide:
                                const BorderSide(
                              color: _gold,
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: canSave
                              ? () {
                                  Navigator.of(
                                    sheetContext,
                                  ).pop(
                                    controller.text.trim(),
                                  );
                                }
                              : null,
                          style:
                              ElevatedButton.styleFrom(
                            backgroundColor: _gold,
                            foregroundColor: Colors.black,
                            disabledBackgroundColor:
                                const Color(0xFF333333),
                            disabledForegroundColor:
                                Colors.white38,
                            shape:
                                RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(
                            Icons.check_rounded,
                          ),
                          label: const Text(
                            'Сохранить',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight:
                                  FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    controller.dispose();

    final editedText = newText?.trim() ?? '';

    if (editedText.isEmpty ||
        editedText == oldText) {
      return;
    }

    SocketService.instance.editMessage(
      messageId: messageId,
      to: widget.targetUser,
      newText: editedText,
    );
  }

  Future<void> _deleteMessageForMe(
    Map<String, dynamic> message,
  ) async {
    final messageId =
        _getMessageId(message);

    if (messageId.isEmpty || !mounted) {
      return;
    }

    final confirmed =
        await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            decoration:
                const BoxDecoration(
              color: Color(0xFF161616),
              borderRadius:
                  BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            padding:
                const EdgeInsets.fromLTRB(
              18,
              10,
              18,
              18,
            ),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius:
                        BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFFF5C5C),
                      size: 26,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Удалить сообщение?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Align(
                  alignment:
                      Alignment.centerLeft,
                  child: Text(
                    'Оно исчезнет только у вас. У собеседника сообщение останется.',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.of(
                            sheetContext,
                          ).pop(false);
                        },
                        style:
                            OutlinedButton.styleFrom(
                          foregroundColor:
                              Colors.white,
                          side: BorderSide(
                            color: _gold.withValues(
                              alpha: 0.55,
                            ),
                          ),
                          minimumSize:
                              const Size(0, 48),
                          shape:
                              RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(
                              14,
                            ),
                          ),
                        ),
                        child:
                            const Text('Отмена'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(
                            sheetContext,
                          ).pop(true);
                        },
                        icon: const Icon(
                          Icons.delete_rounded,
                        ),
                        label: const Text(
                          'Удалить у себя',
                        ),
                        style:
                            ElevatedButton.styleFrom(
                          backgroundColor:
                              const Color(
                            0xFFFF4D4D,
                          ),
                          foregroundColor:
                              Colors.white,
                          minimumSize:
                              const Size(0, 48),
                          shape:
                              RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(
                              14,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true || !mounted) {
      return;
    }

    final replyId = _replyToMessage == null
        ? ''
        : _getMessageId(_replyToMessage!);

    var removed = false;

    setState(() {
      final before = _messages.length;

      _messages.removeWhere(
        (item) =>
            _getMessageId(item) == messageId,
      );

      removed = _messages.length != before;

      if (replyId == messageId) {
        _replyToMessage = null;
      }
    });

    if (!removed) {
      return;
    }

    _saveMessages();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(
      const SnackBar(
        content: Text(
          'Сообщение удалено у вас',
        ),
        backgroundColor:
            Color(0xFF1A1A1A),
        duration: Duration(
          milliseconds: 1100,
        ),
      ),
    );
  }

  Future<void> _forwardMessage(
    Map<String, dynamic> message,
  ) async {
    final currentUser =
        SocketService.instance.currentUser ?? '';

    final text =
        message['text']?.toString().trim() ?? '';

    if (currentUser.isEmpty ||
        text.isEmpty) {
      return;
    }

    final users =
        StorageService.getChatUsers(
      currentUser,
    )
          ..removeWhere(
            (user) =>
                user.trim().isEmpty ||
                user == currentUser,
          )
          ..sort(
            (a, b) => a
                .toLowerCase()
                .compareTo(
                  b.toLowerCase(),
                ),
          );

    if (users.isEmpty) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context)
          .showSnackBar(
        const SnackBar(
          content: Text(
            'Нет других чатов для пересылки',
          ),
          backgroundColor:
              Color(0xFF1A1A1A),
        ),
      );

      return;
    }

    final forwardedFrom =
        message['forwardedFrom']
                    ?.toString()
                    .trim()
                    .isNotEmpty ==
                true
            ? message['forwardedFrom']
                .toString()
                .trim()
            : message['from']
                    ?.toString()
                    .trim() ??
                currentUser;

    final commentController =
        TextEditingController();

    final searchController =
        TextEditingController();

    final selectedUsers = <String>{};
    var searchQuery = '';

    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor:
          Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (
            context,
            setSheetState,
          ) {
            final filteredUsers = users
                .where(
                  (user) => user
                      .toLowerCase()
                      .contains(searchQuery),
                )
                .toList();

            final keyboardHeight =
                MediaQuery.viewInsetsOf(
              sheetContext,
            ).bottom;

            final screenHeight =
                MediaQuery.sizeOf(
              sheetContext,
            ).height;

            return AnimatedPadding(
              duration: const Duration(
                milliseconds: 180,
              ),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                bottom: keyboardHeight,
              ),
              child: SafeArea(
                child: Container(
            constraints: BoxConstraints(
              maxHeight:
                  (screenHeight -
                          keyboardHeight) *
                      0.92,
            ),
            decoration:
                const BoxDecoration(
              color: Color(0xFF161616),
              borderRadius:
                  BorderRadius.vertical(
                top: Radius.circular(24),
              ),
            ),
            child: Column(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius:
                        BorderRadius.circular(3),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(
                    18,
                    16,
                    18,
                    12,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.forward_rounded,
                        color: _gold,
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Переслать сообщение',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(
                  height: 1,
                  color: Color(0x33D4AF37),
                ),
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    8,
                  ),
                  child: TextField(
                    controller:
                        searchController,
                    onChanged: (value) {
                      setSheetState(() {
                        searchQuery = value
                            .trim()
                            .toLowerCase();
                      });
                    },
                    style: const TextStyle(
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'Поиск контакта',
                      hintStyle:
                          const TextStyle(
                        color: Colors.white38,
                      ),
                      prefixIcon:
                          const Icon(
                        Icons.search_rounded,
                        color: _gold,
                      ),
                      suffixIcon:
                          searchQuery.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    searchController
                                        .clear();
                                    setSheetState(
                                      () {
                                        searchQuery =
                                            '';
                                      },
                                    );
                                  },
                                  icon:
                                      const Icon(
                                    Icons.close,
                                    color:
                                        Colors.white54,
                                  ),
                                ),
                      filled: true,
                      fillColor:
                          const Color(
                        0xFF222222,
                      ),
                      contentPadding:
                          const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(
                          16,
                        ),
                        borderSide:
                            BorderSide.none,
                      ),
                      focusedBorder:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(
                          16,
                        ),
                        borderSide:
                            const BorderSide(
                          color: _gold,
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                if (selectedUsers.isNotEmpty)
                  SizedBox(
                    height: 42,
                    child: ListView(
                      scrollDirection:
                          Axis.horizontal,
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 14,
                      ),
                      children: selectedUsers
                          .map(
                            (user) => Padding(
                              padding:
                                  const EdgeInsets.only(
                                right: 7,
                              ),
                              child: InputChip(
                                label: Text(user),
                                labelStyle:
                                    const TextStyle(
                                  color: Colors.black,
                                  fontWeight:
                                      FontWeight.w600,
                                ),
                                backgroundColor:
                                    _gold,
                                deleteIconColor:
                                    Colors.black,
                                side:
                                    BorderSide.none,
                                onDeleted: () {
                                  setSheetState(
                                    () {
                                      selectedUsers
                                          .remove(user);
                                    },
                                  );
                                },
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount:
                        filteredUsers.length,
                    itemBuilder: (
                      context,
                      index,
                    ) {
                      final user =
                          filteredUsers[index];
                      final avatar =
                          StorageService
                              .getAvatar(user);
                      ImageProvider?
                          imageProvider;

                      if (avatar != null &&
                          avatar.isNotEmpty) {
                        try {
                          imageProvider =
                              MemoryImage(
                            base64Decode(
                              avatar,
                            ),
                          );
                        } catch (_) {
                          imageProvider =
                              null;
                        }
                      }

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              const Color(
                            0xFF292929,
                          ),
                          backgroundImage:
                              imageProvider,
                          child:
                              imageProvider ==
                                      null
                                  ? Text(
                                      user.isEmpty
                                          ? '?'
                                          : user[0]
                                              .toUpperCase(),
                                      style:
                                          const TextStyle(
                                        color: _gold,
                                        fontWeight:
                                            FontWeight
                                                .bold,
                                      ),
                                    )
                                  : null,
                        ),
                        title: Text(
                          user,
                          style:
                              const TextStyle(
                            color: Colors.white,
                            fontWeight:
                                FontWeight.w600,
                          ),
                        ),
                        trailing: AnimatedContainer(
                          duration:
                              const Duration(
                            milliseconds: 160,
                          ),
                          width: 27,
                          height: 27,
                          decoration: BoxDecoration(
                            color: selectedUsers
                                    .contains(user)
                                ? _gold
                                : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _gold,
                              width: 1.3,
                            ),
                          ),
                          child: selectedUsers
                                  .contains(user)
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.black,
                                  size: 18,
                                )
                              : null,
                        ),
                        onTap: () {
                          setSheetState(() {
                            if (!selectedUsers
                                .add(user)) {
                              selectedUsers
                                  .remove(user);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
                const Divider(
                  height: 1,
                  color: Color(0x33D4AF37),
                ),
                Container(
                  width: double.infinity,
                  margin:
                      const EdgeInsets.fromLTRB(
                    16,
                    10,
                    16,
                    8,
                  ),
                  padding:
                      const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(
                      0xFF202020,
                    ),
                    borderRadius:
                        BorderRadius.circular(14),
                    border: Border.all(
                      color: _gold.withValues(
                        alpha: 0.35,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        '↪ Переслано от $forwardedFrom',
                        maxLines: 1,
                        overflow:
                            TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _gold,
                          fontSize: 11,
                          fontWeight:
                              FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        text,
                        maxLines: 2,
                        overflow:
                            TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 16,
                  ),
                  child: TextField(
                    controller:
                        commentController,
                    minLines: 1,
                    maxLines: 3,
                    style: const TextStyle(
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      hintText:
                          'Добавить комментарий…',
                      hintStyle:
                          const TextStyle(
                        color: Colors.white38,
                      ),
                      prefixIcon:
                          const Icon(
                        Icons
                            .chat_bubble_outline_rounded,
                        color: _gold,
                      ),
                      filled: true,
                      fillColor:
                          const Color(
                        0xFF222222,
                      ),
                      border: OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(16),
                        borderSide:
                            BorderSide.none,
                      ),
                      focusedBorder:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(16),
                        borderSide:
                            const BorderSide(
                          color: _gold,
                          width: 1,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(
                    16,
                    10,
                    16,
                    14,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: selectedUsers.isEmpty
                          ? null
                          : () {
                              final comment =
                                  commentController
                                      .text
                                      .trim();
                              final recipients =
                                  selectedUsers
                                      .toList();

                              Navigator.of(
                                sheetContext,
                              ).pop();

                              for (final user
                                  in recipients) {
                                SocketService.instance
                                    .sendMessage(
                                  user,
                                  text,
                                  forwardedFrom:
                                      forwardedFrom,
                                  forwardComment:
                                      comment,
                                );
                              }

                              if (!mounted) {
                                return;
                              }

                              ScaffoldMessenger.of(
                                this.context,
                              ).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    recipients.length == 1
                                        ? 'Сообщение переслано'
                                        : 'Отправлено получателям: ${recipients.length}',
                                  ),
                                  backgroundColor:
                                      const Color(
                                    0xFF1A1A1A,
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(
                        Icons.send_rounded,
                      ),
                      label: Text(
                        selectedUsers.isEmpty
                            ? 'Выберите получателя'
                            : selectedUsers.length == 1
                                ? 'Отправить'
                                : 'Отправить (${selectedUsers.length})',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _gold,
                        foregroundColor:
                            Colors.black,
                        disabledBackgroundColor:
                            const Color(0xFF303030),
                        disabledForegroundColor:
                            Colors.white38,
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(
                            16,
                          ),
                        ),
                        textStyle:
                            const TextStyle(
                          fontSize: 15,
                          fontWeight:
                              FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
                  ),
                ),
              );
          },
        );
      },
    );

    commentController.dispose();
    searchController.dispose();
  }

  // ========================================
  // КОМПАКТНАЯ КНОПКА РЕАКЦИИ
  // ========================================

  Widget _buildQuickReactionButton({
    String? emoji,
    IconData? icon,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius:
          BorderRadius.circular(
        22,
      ),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment:
            Alignment.center,
        child: icon != null
            ? Icon(
                icon,
                color:
                    iconColor ??
                        Colors.white,
                size: 26,
              )
            : Text(
                emoji ?? '',
                style:
                    const TextStyle(
                  fontSize: 24,
                ),
              ),
      ),
    );
  }

  // ========================================
  // КОМПАКТНАЯ СТРОКА МЕНЮ
  // ========================================

  Widget _buildMessageMenuItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final color =
        danger
            ? const Color(
                0xFFFF4D4D,
              )
            : Colors.white;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 8,
        ),
        child: Row(
          children: [
            SizedBox(
              width: 37,
              child: Icon(
                icon,
                color:
                    danger
                        ? const Color(
                            0xFFFF4D4D,
                          )
                        : _gold,
                size: 22,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style:
                        TextStyle(
                      color: color,
                      fontSize: 15.5,
                      fontWeight:
                          FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null &&
                      subtitle.isNotEmpty) ...[
                    const SizedBox(
                      height: 1,
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow:
                          TextOverflow.ellipsis,
                      style:
                          TextStyle(
                        color:
                            danger
                                ? const Color(
                                    0xFFFF6A6A,
                                  )
                                : _gold.withValues(
                                    alpha: 0.78,
                                  ),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String>
      _buildDesktopMessageContextItem({
    required String value,
    required IconData icon,
    required String label,
    bool danger = false,
  }) {
    final itemColor =
        danger
            ? const Color(
                0xFFFF6262,
              )
            : Colors.white;

    return PopupMenuItem<String>(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color:
                danger
                    ? const Color(
                        0xFFFF6262,
                      )
                    : _gold,
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: itemColor,
                fontSize: 13.5,
                fontWeight:
                    FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void>
      _showDesktopMessageContextMenu(
    Map<String, dynamic> message,
    Offset globalPosition,
  ) async {
    if (!mounted ||
        !Platform.isWindows) {
      return;
    }

    final overlayState =
        Overlay.of(context);

    final overlayObject =
        overlayState.context.findRenderObject();

    if (overlayObject
        is! RenderBox) {
      return;
    }

    final localPosition =
        overlayObject.globalToLocal(
      globalPosition,
    );

    final isMe =
        message['isMe'] == true;

    final forwardedFrom =
        message['forwardedFrom']
                ?.toString()
                .trim() ??
            '';

    final result =
        await showMenu<String>(
      context: context,
      position:
          RelativeRect.fromLTRB(
        localPosition.dx,
        localPosition.dy,
        overlayObject.size.width -
            localPosition.dx,
        overlayObject.size.height -
            localPosition.dy,
      ),
      color:
          const Color(
        0xFF171717,
      ),
      elevation: 14,
      shadowColor:
          Colors.black.withValues(
        alpha: 0.72,
      ),
      shape:
          RoundedRectangleBorder(
        borderRadius:
            BorderRadius.circular(
          12,
        ),
        side:
            BorderSide(
          color:
              _gold.withValues(
            alpha: 0.34,
          ),
          width: 0.8,
        ),
      ),
      items: [
        _buildDesktopMessageContextItem(
          value: 'reply',
          icon:
              Icons.reply_rounded,
          label: 'Ответить',
        ),
        _buildDesktopMessageContextItem(
          value: 'copy',
          icon:
              Icons.copy_rounded,
          label: 'Копировать',
        ),
        _buildDesktopMessageContextItem(
          value: 'forward',
          icon:
              Icons.forward_rounded,
          label: 'Переслать',
        ),
        if (isMe &&
            forwardedFrom.isEmpty)
          _buildDesktopMessageContextItem(
            value: 'edit',
            icon:
                Icons.edit_rounded,
            label: 'Изменить',
          ),
        const PopupMenuDivider(
          height: 8,
        ),
        _buildDesktopMessageContextItem(
          value: 'heart',
          icon:
              Icons.favorite_rounded,
          label: 'Реакция ❤️',
        ),
        _buildDesktopMessageContextItem(
          value: 'translate',
          icon:
              Icons.translate_rounded,
          label: 'Перевести',
        ),
        _buildDesktopMessageContextItem(
          value: 'chatgpt',
          icon:
              Icons.auto_awesome_rounded,
          label: 'ChatGPT',
        ),
        _buildDesktopMessageContextItem(
          value: 'pin',
          icon:
              Icons.push_pin_rounded,
          label: 'Закрепить',
        ),
        const PopupMenuDivider(
          height: 8,
        ),
        if (isMe)
          _buildDesktopMessageContextItem(
            value: 'delete_everyone',
            icon:
                Icons.delete_sweep_rounded,
            label:
                'Удалить без следов',
            danger: true,
          ),
        _buildDesktopMessageContextItem(
          value: 'delete_me',
          icon:
              Icons.delete_rounded,
          label: 'Удалить',
          danger: true,
        ),
      ],
    );

    if (!mounted ||
        result == null) {
      return;
    }

    switch (result) {
      case 'reply':
        _startReply(
          message,
        );
        break;

      case 'copy':
        unawaited(
          _copyMessageText(
            message,
          ),
        );
        break;

      case 'forward':
        unawaited(
          _forwardMessage(
            message,
          ),
        );
        break;

      case 'edit':
        unawaited(
          _editMessage(
            message,
          ),
        );
        break;

      case 'heart':
        _sendReaction(
          message,
        );
        break;

      case 'translate':
        _showComingSoon(
          'Перевести',
        );
        break;

      case 'chatgpt':
        _showComingSoon(
          'ChatGPT',
        );
        break;

      case 'pin':
        _showComingSoon(
          'Закрепить',
        );
        break;

      case 'delete_everyone':
        _showComingSoon(
          'Удалить без следов',
        );
        break;

      case 'delete_me':
        unawaited(
          _deleteMessageForMe(
            message,
          ),
        );
        break;
    }
  }

  Future<void> _showMessageActionMenu(
    Map<String, dynamic> message,
  ) async {
    final isMe =
        message['isMe'] == true;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel:
          'Закрыть меню сообщения',
      barrierColor:
          Colors.black.withValues(
        alpha: 0.70,
      ),
      transitionDuration:
          const Duration(
        milliseconds: 170,
      ),
      pageBuilder: (
        dialogContext,
        animation,
        secondaryAnimation,
      ) {
        final screenWidth =
            MediaQuery.of(
          dialogContext,
        ).size.width;

        final screenHeight =
            MediaQuery.of(
          dialogContext,
        ).size.height;

        final menuWidth =
            screenWidth > 440
                ? 360.0
                : screenWidth - 46;

        void closeAndRun(
          VoidCallback action,
        ) {
          Navigator.of(
            dialogContext,
          ).pop();

          Future<void>.delayed(
            const Duration(
              milliseconds: 80,
            ),
            action,
          );
        }

        return SafeArea(
          child: Center(
            child: Material(
              color:
                  Colors.transparent,
              child: SizedBox(
                width: menuWidth,
                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  children: [
                    // =================================
                    // КОМПАКТНАЯ ПАНЕЛЬ РЕАКЦИЙ
                    // =================================
                    Container(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 3,
                      ),
                      decoration:
                          BoxDecoration(
                        color:
                            const Color(
                          0xF2161616,
                        ),
                        borderRadius:
                            BorderRadius.circular(
                          25,
                        ),
                        border:
                            Border.all(
                          color:
                              _gold.withValues(
                            alpha: 0.95,
                          ),
                          width: 1.1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                _gold.withValues(
                              alpha: 0.16,
                            ),
                            blurRadius: 13,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment
                                .spaceEvenly,
                        children: [
                          _buildQuickReactionButton(
                            icon:
                                Icons.favorite,
                            iconColor:
                                _gold,
                            onTap: () {
                              closeAndRun(
                                () {
                                  _sendReaction(
                                    message,
                                  );
                                },
                              );
                            },
                          ),
                          _buildQuickReactionButton(
                            emoji: '😂',
                            onTap: () {
                              closeAndRun(
                                () =>
                                    _showComingSoon(
                                  'Реакция 😂',
                                ),
                              );
                            },
                          ),
                          _buildQuickReactionButton(
                            emoji: '😮',
                            onTap: () {
                              closeAndRun(
                                () =>
                                    _showComingSoon(
                                  'Реакция 😮',
                                ),
                              );
                            },
                          ),
                          _buildQuickReactionButton(
                            emoji: '😢',
                            onTap: () {
                              closeAndRun(
                                () =>
                                    _showComingSoon(
                                  'Реакция 😢',
                                ),
                              );
                            },
                          ),
                          _buildQuickReactionButton(
                            emoji: '😡',
                            onTap: () {
                              closeAndRun(
                                () =>
                                    _showComingSoon(
                                  'Реакция 😡',
                                ),
                              );
                            },
                          ),
                          _buildQuickReactionButton(
                            emoji: '👍',
                            onTap: () {
                              closeAndRun(
                                () =>
                                    _showComingSoon(
                                  'Реакция 👍',
                                ),
                              );
                            },
                          ),
                          _buildQuickReactionButton(
                            icon:
                                Icons
                                    .add_circle_outline,
                            iconColor:
                                _gold,
                            onTap: () {
                              closeAndRun(
                                () =>
                                    _showComingSoon(
                                  'Другие реакции',
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(
                      height: 8,
                    ),

                    // =================================
                    // КОМПАКТНОЕ ОСНОВНОЕ МЕНЮ
                    // =================================
                    Container(
                      constraints:
                          BoxConstraints(
                        maxHeight:
                            screenHeight *
                                0.60,
                      ),
                      decoration:
                          BoxDecoration(
                        color:
                            const Color(
                          0xF2161616,
                        ),
                        borderRadius:
                            BorderRadius.circular(
                          20,
                        ),
                        border:
                            Border.all(
                          color:
                              _gold.withValues(
                            alpha: 0.95,
                          ),
                          width: 1.1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color:
                                Colors.black
                                    .withValues(
                              alpha: 0.50,
                            ),
                            blurRadius: 18,
                            spreadRadius: 1,
                          ),
                          BoxShadow(
                            color:
                                _gold.withValues(
                              alpha: 0.10,
                            ),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      clipBehavior:
                          Clip.antiAlias,
                      child:
                          SingleChildScrollView(
                        child: Column(
                          mainAxisSize:
                              MainAxisSize.min,
                          children: [
                            _buildMessageMenuItem(
                              icon:
                                  Icons
                                      .reply_rounded,
                              title:
                                  'Ответить',
                              subtitle:
                                  'Ответить на это сообщение',
                              onTap: () {
                                closeAndRun(
                                  () {
                                    _startReply(
                                      message,
                                    );
                                  },
                                );
                              },
                            ),

                            Divider(
                              height: 1,
                              thickness: 0.6,
                              color:
                                  _gold.withValues(
                                alpha: 0.15,
                              ),
                            ),

                            _buildMessageMenuItem(
                              icon:
                                  Icons
                                      .copy_rounded,
                              title:
                                  'Копировать',
                              subtitle:
                                  'Скопировать текст сообщения',
                              onTap: () {
                                Navigator.of(
                                  dialogContext,
                                ).pop();

                                unawaited(
                                  _copyMessageText(
                                    message,
                                  ),
                                );
                              },
                            ),

                            Divider(
                              height: 1,
                              thickness: 0.6,
                              color:
                                  _gold.withValues(
                                alpha: 0.15,
                              ),
                            ),

                            _buildMessageMenuItem(
                              icon:
                                  Icons
                                      .forward_rounded,
                              title:
                                  'Переслать',
                              subtitle:
                                  'Отправить сообщение другому',
                              onTap: () {
                                closeAndRun(
                                  () {
                                    unawaited(
                                      _forwardMessage(
                                        message,
                                      ),
                                    );
                                  },
                                );
                              },
                            ),

                            if (isMe &&
                                (message['forwardedFrom']
                                            ?.toString()
                                            .trim()
                                            .isEmpty ??
                                        true)) ...[
                              Divider(
                                height: 1,
                                thickness: 0.6,
                                color:
                                    _gold.withValues(
                                  alpha: 0.15,
                                ),
                              ),
                              _buildMessageMenuItem(
                                icon:
                                    Icons
                                        .edit_rounded,
                                title:
                                    'Изменить',
                                subtitle:
                                    'Изменить своё сообщение',
                                onTap: () {
                                  closeAndRun(
                                    () {
                                      unawaited(
                                        _editMessage(
                                          message,
                                        ),
                                      );
                                    },
                                  );
                                },
                              ),
                            ],

                            Divider(
                              height: 1,
                              thickness: 0.6,
                              color:
                                  _gold.withValues(
                                alpha: 0.15,
                              ),
                            ),

                            _buildMessageMenuItem(
                              icon:
                                  Icons
                                      .translate_rounded,
                              title:
                                  'Перевести',
                              subtitle:
                                  'Перевести текст сообщения',
                              onTap: () {
                                closeAndRun(
                                  () =>
                                      _showComingSoon(
                                    'Перевести',
                                  ),
                                );
                              },
                            ),

                            Divider(
                              height: 1,
                              thickness: 0.6,
                              color:
                                  _gold.withValues(
                                alpha: 0.15,
                              ),
                            ),

                            _buildMessageMenuItem(
                              icon:
                                  Icons
                                      .auto_awesome_rounded,
                              title:
                                  'ChatGPT',
                              subtitle:
                                  'Работа с сообщением через ChatGPT',
                              onTap: () {
                                closeAndRun(
                                  () =>
                                      _showComingSoon(
                                    'ChatGPT',
                                  ),
                                );
                              },
                            ),

                            Divider(
                              height: 1,
                              thickness: 0.6,
                              color:
                                  _gold.withValues(
                                alpha: 0.15,
                              ),
                            ),

                            _buildMessageMenuItem(
                              icon:
                                  Icons
                                      .push_pin_rounded,
                              title:
                                  'Закрепить',
                              subtitle:
                                  'Закрепить сообщение в чате',
                              onTap: () {
                                closeAndRun(
                                  () =>
                                      _showComingSoon(
                                    'Закрепить',
                                  ),
                                );
                              },
                            ),

                            if (isMe) ...[
                              Divider(
                                height: 1,
                                thickness: 0.6,
                                color:
                                    _gold.withValues(
                                  alpha: 0.15,
                                ),
                              ),
                              _buildMessageMenuItem(
                                icon:
                                    Icons
                                        .delete_sweep_rounded,
                                title:
                                    'Удалить без следов',
                                subtitle:
                                    'Удалить для всех',
                                danger: true,
                                onTap: () {
                                  closeAndRun(
                                    () =>
                                        _showComingSoon(
                                      'Удалить без следов',
                                    ),
                                  );
                                },
                              ),
                            ],

                            Divider(
                              height: 1,
                              thickness: 0.6,
                              color:
                                  const Color(
                                0xFFFF4D4D,
                              ).withValues(
                                alpha: 0.16,
                              ),
                            ),

                            _buildMessageMenuItem(
                              icon:
                                  Icons
                                      .delete_rounded,
                              title:
                                  'Удалить',
                              subtitle:
                                  'Удалить сообщение',
                              danger: true,
                              onTap: () {
                                closeAndRun(
                                  () {
                                    unawaited(
                                      _deleteMessageForMe(
                                        message,
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      transitionBuilder: (
        context,
        animation,
        secondaryAnimation,
        child,
      ) {
        final curved =
            CurvedAnimation(
          parent: animation,
          curve:
              Curves.easeOutBack,
        );

        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(
              begin: 0.95,
              end: 1.0,
            ).animate(
              curved,
            ),
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildDesktopQuickMessageAction({
    required IconData icon,
    required String tooltip,
    required bool isMe,
    required VoidCallback onTap,
  }) {
    final foreground =
        isMe
            ? Colors.black54
            : _gold.withValues(
                alpha: 0.88,
              );

    return Tooltip(
      message: tooltip,
      waitDuration:
          const Duration(
        milliseconds: 350,
      ),
      child:
          MouseRegion(
        cursor:
            SystemMouseCursors.click,
        child:
            GestureDetector(
          behavior:
              HitTestBehavior.opaque,
          onTap: onTap,
          child:
              Container(
            width: 24,
            height: 24,
            alignment:
                Alignment.center,
            decoration:
                BoxDecoration(
              shape:
                  BoxShape.circle,
              color:
                  isMe
                      ? Colors.black
                          .withValues(
                            alpha: 0.075,
                          )
                      : _gold.withValues(
                          alpha: 0.075,
                        ),
              border:
                  Border.all(
                color:
                    isMe
                        ? Colors.black
                            .withValues(
                              alpha: 0.14,
                            )
                        : _gold.withValues(
                            alpha: 0.16,
                          ),
                width: 0.7,
              ),
            ),
            child:
                Icon(
              icon,
              size: 14,
              color: foreground,
            ),
          ),
        ),
      ),
    );
  }

  // ========================================
  // ОДНО СООБЩЕНИЕ
  // ========================================

  Widget _buildMessageBubble(
    Map<String, dynamic> message,
  ) {
    final isMe =
        message['isMe'] == true;

    final text =
        message['text']
                ?.toString() ??
            '';

    final from =
        message['from']
                ?.toString() ??
            '';

    final forwardedFrom =
        message['forwardedFrom']
                ?.toString()
                .trim() ??
            '';

    final forwardComment =
        message['forwardComment']
                ?.toString()
                .trim() ??
            '';

    final isWindowsDesktop =
        Platform.isWindows;

    final messageId =
        _getMessageId(
      message,
    );

    final isHovered =
        isWindowsDesktop &&
            _hoveredMessageId ==
                messageId;

    final bubbleMaxWidth =
        isWindowsDesktop
            ? forwardedFrom.isNotEmpty
                ? 680.0
                : 620.0
            : MediaQuery.of(context)
                    .size
                    .width *
                0.7;

    final timeStr =
        _formatTime(
      message['time'],
    );

    final isEdited =
        message['isEdited'] == true ||
            (message['editedAt']
                        ?.toString()
                        .trim()
                        .isNotEmpty ??
                    false);

    Map<String, dynamic>? replyTo;

    final rawReplyTo =
        message['replyTo'];

    if (rawReplyTo is Map) {
      replyTo =
          Map<String, dynamic>.from(
        rawReplyTo,
      );
    }

    return Align(
      alignment:
          isMe
              ? Alignment.centerRight
              : Alignment.centerLeft,
      child: MouseRegion(
        cursor:
            isWindowsDesktop
                ? SystemMouseCursors.basic
                : MouseCursor.defer,
        onEnter:
            isWindowsDesktop
                ? (_) {
                    if (_hoveredMessageId !=
                        messageId) {
                      setState(
                        () {
                          _hoveredMessageId =
                              messageId;
                        },
                      );
                    }
                  }
                : null,
        onExit:
            isWindowsDesktop
                ? (_) {
                    if (_hoveredMessageId ==
                        messageId) {
                      setState(
                        () {
                          _hoveredMessageId =
                              null;
                        },
                      );
                    }
                  }
                : null,
        child: GestureDetector(
          behavior:
              HitTestBehavior.opaque,
          onLongPress: () {
            _showMessageActionMenu(
              message,
            );
          },
          onDoubleTap:
              isWindowsDesktop
                  ? () {
                      _startReply(
                        message,
                      );
                    }
                  : null,
          onSecondaryTapDown:
              isWindowsDesktop
                  ? (details) {
                      unawaited(
                        _showDesktopMessageContextMenu(
                          message,
                          details.globalPosition,
                        ),
                      );
                    }
                  : null,
          child: Padding(
          padding:
              EdgeInsets.only(
            top:
                isWindowsDesktop
                    ? 3
                    : 4,
            bottom:
                isWindowsDesktop
                    ? 12
                    : 18,
          ),
          child: Stack(
            clipBehavior:
                Clip.none,
            children: [
              AnimatedContainer(
                duration:
                    const Duration(
                  milliseconds: 150,
                ),
                curve:
                    Curves.easeOutCubic,
                padding:
                    const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                constraints:
                    BoxConstraints(
                  maxWidth:
                      bubbleMaxWidth,
                ),
                decoration:
                    BoxDecoration(
                  gradient:
                      isMe
                          ? const LinearGradient(
                              colors: [
                                _gold,
                                _darkGold,
                              ],
                            )
                          : const LinearGradient(
                              colors: [
                                Color(
                                  0xE61A1A1A,
                                ),
                                Color(
                                  0xE62A2A2A,
                                ),
                              ],
                            ),
                  borderRadius:
                      BorderRadius.circular(
                    16,
                  ),
                  border:
                      isHovered
                          ? Border.all(
                              color:
                                  isMe
                                      ? Colors.black
                                          .withValues(
                                            alpha:
                                                0.28,
                                          )
                                      : _gold
                                          .withValues(
                                            alpha:
                                                0.46,
                                          ),
                              width: 0.8,
                            )
                          : null,
                  boxShadow: [
                    BoxShadow(
                      color:
                          Colors.black
                              .withValues(
                        alpha:
                            isHovered
                                ? 0.34
                                : 0.20,
                      ),
                      blurRadius:
                          isHovered
                              ? 9
                              : 4,
                      offset:
                          const Offset(
                        0,
                        2,
                      ),
                    ),
                    if (isHovered)
                      BoxShadow(
                        color:
                            isMe
                                ? _gold
                                    .withValues(
                                      alpha:
                                          0.12,
                                    )
                                : _gold
                                    .withValues(
                                      alpha:
                                          0.10,
                                    ),
                        blurRadius: 14,
                        spreadRadius:
                            -2,
                      ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    if (!isMe &&
                        from.isNotEmpty &&
                        forwardedFrom.isEmpty)
                      Text(
                        from,
                        style:
                            const TextStyle(
                          fontSize: 10,
                          color: _gold,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),

                    if (!isMe &&
                        from.isNotEmpty &&
                        forwardedFrom.isEmpty)
                      const SizedBox(
                        height: 2,
                      ),

                    if (replyTo != null)
                      _buildReplyPreview(
                        replyTo,
                        isMe: isMe,
                      ),

                    if (forwardedFrom.isNotEmpty) ...[
                      Row(
                        mainAxisSize:
                            MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.forward_rounded,
                            size: 12,
                            color: isMe
                                ? Colors.black45
                                : _gold.withValues(
                                    alpha: 0.90,
                                  ),
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Переслано от $forwardedFrom',
                              maxLines: 1,
                              overflow:
                                  TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isMe
                                    ? Colors.black45
                                    : _gold.withValues(
                                        alpha: 0.90,
                                      ),
                                fontSize: 9.5,
                                fontWeight:
                                    FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        text,
                        style: TextStyle(
                          color: isMe
                              ? Colors.black
                              : Colors.white,
                          fontSize: 14,
                          height: 1.18,
                        ),
                      ),
                      if (forwardComment.isNotEmpty) ...[
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(
                            vertical: 6,
                          ),
                          child: Container(
                            height: 0.6,
                            color: isMe
                                ? Colors.black12
                                : _gold.withValues(
                                    alpha: 0.22,
                                  ),
                          ),
                        ),
                        Row(
                          mainAxisSize:
                              MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 11,
                              color: isMe
                                  ? Colors.black45
                                  : _gold.withValues(
                                      alpha: 0.82,
                                    ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                from.isNotEmpty
                                    ? from
                                    : 'Комментарий',
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isMe
                                      ? Colors.black45
                                      : _gold.withValues(
                                          alpha: 0.82,
                                        ),
                                  fontSize: 9.5,
                                  fontWeight:
                                      FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          forwardComment,
                          style: TextStyle(
                            color: isMe
                                ? Colors.black
                                : Colors.white,
                            fontSize: 14,
                            height: 1.18,
                          ),
                        ),
                      ],
                    ] else
                      Text(
                        text,
                        style: TextStyle(
                          color: isMe
                              ? Colors.black
                              : Colors.white,
                          fontSize: 14,
                        ),
                      ),

                    const SizedBox(
                      height: 4,
                    ),

                    Row(
                      mainAxisSize:
                          MainAxisSize.min,
                      children: [
                        if (timeStr.isNotEmpty)
                          Text(
                            timeStr,
                            style:
                                TextStyle(
                              color:
                                  isMe
                                      ? Colors.black54
                                      : Colors.white54,
                              fontSize: 10,
                            ),
                          ),

                        if (isEdited) ...[
                          const SizedBox(
                            width: 4,
                          ),
                          Text(
                            'изменено',
                            style: TextStyle(
                              color: isMe
                                  ? Colors.black45
                                  : Colors.white38,
                              fontSize: 9,
                              fontStyle:
                                  FontStyle.italic,
                            ),
                          ),
                        ],

                        if (isMe) ...[
                          const SizedBox(
                            width: 4,
                          ),
                          _buildMessageStatus(
                            message,
                          ),
                        ],

                        if (isWindowsDesktop) ...[
                          const SizedBox(
                            width: 8,
                          ),
                          AnimatedOpacity(
                            duration:
                                const Duration(
                              milliseconds:
                                  120,
                            ),
                            curve:
                                Curves
                                    .easeOutCubic,
                            opacity:
                                isHovered
                                    ? 1.0
                                    : 0.0,
                            child:
                                AnimatedScale(
                              duration:
                                  const Duration(
                                milliseconds:
                                    130,
                              ),
                              curve:
                                  Curves
                                      .easeOutCubic,
                              scale:
                                  isHovered
                                      ? 1.0
                                      : 0.90,
                              child:
                                  IgnorePointer(
                                ignoring:
                                    !isHovered,
                                child:
                                    Row(
                                  mainAxisSize:
                                      MainAxisSize
                                          .min,
                                  children: [
                                    _buildDesktopQuickMessageAction(
                                      icon:
                                          Icons
                                              .reply_rounded,
                                      tooltip:
                                          'Ответить',
                                      isMe:
                                          isMe,
                                      onTap: () {
                                        _startReply(
                                          message,
                                        );
                                      },
                                    ),
                                    const SizedBox(
                                      width: 4,
                                    ),
                                    _buildDesktopQuickMessageAction(
                                      icon:
                                          Icons
                                              .copy_rounded,
                                      tooltip:
                                          'Копировать',
                                      isMe:
                                          isMe,
                                      onTap: () {
                                        unawaited(
                                          _copyMessageText(
                                            message,
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(
                                      width: 4,
                                    ),
                                    _buildDesktopQuickMessageAction(
                                      icon:
                                          Icons
                                              .forward_rounded,
                                      tooltip:
                                          'Переслать',
                                      isMe:
                                          isMe,
                                      onTap: () {
                                        unawaited(
                                          _forwardMessage(
                                            message,
                                          ),
                                        );
                                      },
                                    ),
                                    if (isMe &&
                                        forwardedFrom.isEmpty) ...[
                                      const SizedBox(
                                        width: 4,
                                      ),
                                      _buildDesktopQuickMessageAction(
                                        icon:
                                            Icons
                                                .edit_rounded,
                                        tooltip:
                                            'Изменить',
                                        isMe:
                                            isMe,
                                        onTap: () {
                                          unawaited(
                                            _editMessage(
                                              message,
                                            ),
                                          );
                                        },
                                      ),
                                    ],
                                    const SizedBox(
                                      width: 4,
                                    ),
                                    _buildDesktopQuickMessageAction(
                                      icon:
                                          Icons
                                              .favorite_outline_rounded,
                                      tooltip:
                                          'Реакция ❤️',
                                      isMe:
                                          isMe,
                                      onTap: () {
                                        _sendReaction(
                                          message,
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              Positioned(
                bottom: -15,
                left:
                    isMe ? -15 : null,
                right:
                    isMe ? null : -15,
                child:
                    AnimatedSwitcher(
                  duration:
                      const Duration(
                    milliseconds: 180,
                  ),
                  transitionBuilder: (
                    child,
                    animation,
                  ) {
                    return ScaleTransition(
                      scale:
                          CurvedAnimation(
                        parent:
                            animation,
                        curve:
                            Curves.easeOutBack,
                      ),
                      child: child,
                    );
                  },
                  child: KeyedSubtree(
                    key: ValueKey<String>(
                      _getReactionUsers(
                        message,
                      ).join('|'),
                    ),
                    child:
                        _buildReactionRow(
                      message,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  void _handleMessageScroll() {
    if (!Platform.isWindows ||
        !_messageScrollController.hasClients ||
        !mounted) {
      return;
    }

    final shouldShow =
        _messageScrollController.position.pixels >
            180;

    final shouldResetCounter =
        !shouldShow &&
            _newMessagesWhileScrolledUp >
                0;

    if (shouldShow ==
            _showScrollToLatest &&
        !shouldResetCounter) {
      return;
    }

    setState(
      () {
        _showScrollToLatest =
            shouldShow;

        if (shouldResetCounter) {
          _newMessagesWhileScrolledUp =
              0;
        }
      },
    );
  }

  void _scrollToLatestMessage() {
    if (!_messageScrollController.hasClients) {
      return;
    }

    if (_newMessagesWhileScrolledUp >
            0 &&
        mounted) {
      setState(
        () {
          _newMessagesWhileScrolledUp =
              0;
        },
      );
    }

    _messageScrollController.animateTo(
      0,
      duration:
          const Duration(
        milliseconds: 280,
      ),
      curve:
          Curves.easeOutCubic,
    );
  }

  Widget _buildScrollToLatestButton() {
    if (!Platform.isWindows) {
      return const SizedBox.shrink();
    }

    return AnimatedSlide(
      duration:
          const Duration(
        milliseconds: 180,
      ),
      curve:
          Curves.easeOutCubic,
      offset:
          _showScrollToLatest
              ? Offset.zero
              : const Offset(
                  0,
                  0.45,
                ),
      child:
          AnimatedOpacity(
        duration:
            const Duration(
          milliseconds: 160,
        ),
        opacity:
            _showScrollToLatest
                ? 1
                : 0,
        child:
            IgnorePointer(
          ignoring:
              !_showScrollToLatest,
          child:
              Tooltip(
            message:
                _newMessagesWhileScrolledUp > 0
                    ? 'Новых сообщений: $_newMessagesWhileScrolledUp'
                    : 'К последним сообщениям',
            waitDuration:
                const Duration(
              milliseconds: 350,
            ),
            child:
                MouseRegion(
              cursor:
                  SystemMouseCursors.click,
              onEnter: (_) {
                if (!_scrollToLatestHovered) {
                  setState(
                    () {
                      _scrollToLatestHovered =
                          true;
                    },
                  );
                }
              },
              onExit: (_) {
                if (_scrollToLatestHovered) {
                  setState(
                    () {
                      _scrollToLatestHovered =
                          false;
                    },
                  );
                }
              },
              child:
                  GestureDetector(
                onTap:
                    _scrollToLatestMessage,
                child:
                    AnimatedScale(
                  duration:
                      const Duration(
                    milliseconds: 130,
                  ),
                  curve:
                      Curves.easeOutCubic,
                  scale:
                      _scrollToLatestHovered
                          ? 1.08
                          : 1,
                  child:
                      AnimatedContainer(
                    duration:
                        const Duration(
                      milliseconds: 150,
                    ),
                    width: 42,
                    height: 42,
                    alignment:
                        Alignment.center,
                    decoration:
                        BoxDecoration(
                      shape:
                          BoxShape.circle,
                      color:
                          const Color(
                        0xF21A1A1A,
                      ),
                      border:
                          Border.all(
                        color:
                            _gold.withValues(
                          alpha:
                              _scrollToLatestHovered
                                  ? 0.72
                                  : 0.40,
                        ),
                        width: 0.9,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color:
                              Colors.black
                                  .withValues(
                            alpha: 0.48,
                          ),
                          blurRadius: 12,
                          offset:
                              const Offset(
                            0,
                            4,
                          ),
                        ),
                        if (_scrollToLatestHovered)
                          BoxShadow(
                            color:
                                _gold.withValues(
                              alpha: 0.18,
                            ),
                            blurRadius: 16,
                          ),
                      ],
                    ),
                    child:
                        Stack(
                      clipBehavior:
                          Clip.none,
                      alignment:
                          Alignment.center,
                      children: [
                        const Icon(
                          Icons
                              .keyboard_arrow_down_rounded,
                          color: _gold,
                          size: 24,
                        ),
                        if (_newMessagesWhileScrolledUp >
                            0)
                          Positioned(
                            right: -7,
                            top: -7,
                            child:
                                AnimatedScale(
                              duration:
                                  const Duration(
                                milliseconds:
                                    150,
                              ),
                              curve:
                                  Curves
                                      .easeOutBack,
                              scale: 1,
                              child:
                                  Container(
                                constraints:
                                    const BoxConstraints(
                                  minWidth: 20,
                                  minHeight: 20,
                                ),
                                padding:
                                    const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                alignment:
                                    Alignment.center,
                                decoration:
                                    BoxDecoration(
                                  color: _gold,
                                  borderRadius:
                                      BorderRadius.circular(
                                    10,
                                  ),
                                  border:
                                      Border.all(
                                    color:
                                        Colors.black.withValues(
                                      alpha:
                                          0.72,
                                    ),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          _gold.withValues(
                                        alpha:
                                            0.32,
                                      ),
                                      blurRadius:
                                          8,
                                    ),
                                  ],
                                ),
                                child:
                                    Text(
                                  _newMessagesWhileScrolledUp >
                                          99
                                      ? '99+'
                                      : '$_newMessagesWhileScrolledUp',
                                  style:
                                      const TextStyle(
                                    color:
                                        Colors.black,
                                    fontSize:
                                        10,
                                    fontWeight:
                                        FontWeight.w800,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ========================================
  // СПИСОК СООБЩЕНИЙ
  // ========================================

  Widget _buildMessages() {
    if (_messages.isEmpty) {
      return const Center(
        child: Text(
          'Нет сообщений',
          style:
              TextStyle(
            color:
                Colors.white70,
            fontSize: 16,
            fontWeight:
                FontWeight.w500,
            shadows: [
              Shadow(
                blurRadius: 4,
                color:
                    Colors.black,
              ),
            ],
          ),
        ),
      );
    }

    final isWindowsDesktop =
        Platform.isWindows;

    return Stack(
      children: [
        Positioned.fill(
          child:
              isWindowsDesktop
                  ? ScrollbarTheme(
                      data:
                          ScrollbarThemeData(
                        thumbColor:
                            WidgetStateProperty.resolveWith<
                                Color?>(
                          (
                            states,
                          ) {
                            if (states.contains(
                              WidgetState.dragged,
                            )) {
                              return _gold.withValues(
                                alpha: 0.88,
                              );
                            }

                            if (states.contains(
                              WidgetState.hovered,
                            )) {
                              return _gold.withValues(
                                alpha: 0.72,
                              );
                            }

                            return _gold.withValues(
                              alpha: 0.34,
                            );
                          },
                        ),
                        thickness:
                            WidgetStateProperty.resolveWith<
                                double?>(
                          (
                            states,
                          ) {
                            if (states.contains(
                                  WidgetState.dragged,
                                ) ||
                                states.contains(
                                  WidgetState.hovered,
                                )) {
                              return 8;
                            }

                            return 5;
                          },
                        ),
                        radius:
                            const Radius.circular(
                          10,
                        ),
                        trackColor:
                            WidgetStatePropertyAll(
                          Colors.black26,
                        ),
                        trackBorderColor:
                            WidgetStatePropertyAll(
                          Colors.transparent,
                        ),
                      ),
                      child:
                          Scrollbar(
                        controller:
                            _messageScrollController,
                        thumbVisibility: true,
                        trackVisibility: false,
                        interactive: true,
                        child:
                            ListView.builder(
                          controller:
                              _messageScrollController,
                          reverse: true,
                          padding:
                              const EdgeInsets.fromLTRB(
                            30,
                            18,
                            18,
                            18,
                          ),
                          itemCount:
                              _messages.length,
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior
                                  .onDrag,
                          itemBuilder: (
                            context,
                            index,
                          ) {
                            final message =
                                _messages[
                                    _messages.length -
                                        1 -
                                        index];

                            return _buildMessageBubble(
                              message,
                            );
                          },
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller:
                          _messageScrollController,
                      reverse: true,
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      itemCount:
                          _messages.length,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior
                              .onDrag,
                      itemBuilder: (
                        context,
                        index,
                      ) {
                        final message =
                            _messages[
                                _messages.length -
                                    1 -
                                    index];

                        return _buildMessageBubble(
                          message,
                        );
                      },
                    ),
        ),

        if (isWindowsDesktop)
          Positioned(
            right: 24,
            bottom: 18,
            child:
                _buildScrollToLatestButton(),
          ),
      ],
    );
  }

  // ========================================
  // ПОЛЕ ВВОДА
  // ========================================

  Widget _buildMessageInput() {
    final isWindowsDesktop =
        Platform.isWindows;

    final screenWidth =
        MediaQuery.sizeOf(context).width;

    return Column(
      mainAxisSize:
          MainAxisSize.min,
      children: [
        _buildTypingIndicator(),

        _buildComposerReplyPreview(),

        Container(
          padding:
              EdgeInsets.fromLTRB(
            isWindowsDesktop
                ? 16
                : 8,
            isWindowsDesktop
                ? 10
                : 8,
            isWindowsDesktop
                ? 16
                : 8,
            isWindowsDesktop
                ? 12
                : 8,
          ),
          decoration:
              BoxDecoration(
            color:
                const Color(
              0xF21A1A1A,
            ),
            border:
                isWindowsDesktop
                    ? Border(
                        top:
                            BorderSide(
                          color:
                              _gold.withValues(
                            alpha: 0.18,
                          ),
                          width: 0.8,
                        ),
                      )
                    : null,
            boxShadow: [
              BoxShadow(
                color:
                    Colors.black
                        .withValues(
                  alpha: 0.28,
                ),
                blurRadius:
                    isWindowsDesktop
                        ? 14
                        : 8,
                offset:
                    const Offset(
                  0,
                  -2,
                ),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Center(
              child: ConstrainedBox(
                constraints:
                    BoxConstraints(
                  maxWidth:
                      isWindowsDesktop
                          ? 920
                          : screenWidth,
                ),
                child: Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child:
                          CallbackShortcuts(
                        bindings:
                            isWindowsDesktop
                                ? <ShortcutActivator,
                                    VoidCallback>{
                                    const SingleActivator(
                                      LogicalKeyboardKey.enter,
                                    ):
                                        _sendMessage,
                                    const SingleActivator(
                                      LogicalKeyboardKey.escape,
                                    ):
                                        _cancelReply,
                                  }
                                : const <
                                    ShortcutActivator,
                                    VoidCallback>{},
                        child:
                            TextField(
                        controller:
                            _messageController,
                        focusNode:
                            _messageFocusNode,
                        autofocus:
                            isWindowsDesktop,
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                        ),
                        keyboardType:
                            TextInputType
                                .multiline,
                        minLines: 1,
                        maxLines: 6,
                        textInputAction:
                            TextInputAction
                                .newline,
                        decoration:
                            InputDecoration(
                          hintText:
                              'Сообщение...',
                          hintStyle:
                              const TextStyle(
                            color:
                                Colors.white54,
                          ),
                          border:
                              OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(
                              30,
                            ),
                            borderSide:
                                BorderSide.none,
                          ),
                          enabledBorder:
                              OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(
                              30,
                            ),
                            borderSide:
                                isWindowsDesktop
                                    ? BorderSide(
                                        color:
                                            _gold.withValues(
                                          alpha: 0.16,
                                        ),
                                        width: 0.8,
                                      )
                                    : BorderSide.none,
                          ),
                          focusedBorder:
                              OutlineInputBorder(
                            borderRadius:
                                BorderRadius.circular(
                              30,
                            ),
                            borderSide:
                                isWindowsDesktop
                                    ? BorderSide(
                                        color:
                                            _gold.withValues(
                                          alpha: 0.55,
                                        ),
                                        width: 1.0,
                                      )
                                    : BorderSide.none,
                          ),
                          filled: true,
                          fillColor:
                              const Color(
                            0xFF242424,
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                        ),
                        onChanged:
                            _handleTextChanged,
                      ),
                      ),
                    ),

                    const SizedBox(
                      width: 10,
                    ),

                    Tooltip(
                      message:
                          isWindowsDesktop
                              ? 'Отправить — Enter\nНовая строка — Shift+Enter'
                              : 'Отправить',
                      waitDuration:
                          const Duration(
                        milliseconds: 450,
                      ),
                      child:
                          MouseRegion(
                        cursor:
                            isWindowsDesktop
                                ? SystemMouseCursors.click
                                : MouseCursor.defer,
                        onEnter:
                            isWindowsDesktop
                                ? (_) {
                                    if (!_sendButtonHovered) {
                                      setState(
                                        () {
                                          _sendButtonHovered =
                                              true;
                                        },
                                      );
                                    }
                                  }
                                : null,
                        onExit:
                            isWindowsDesktop
                                ? (_) {
                                    if (_sendButtonHovered) {
                                      setState(
                                        () {
                                          _sendButtonHovered =
                                              false;
                                        },
                                      );
                                    }
                                  }
                                : null,
                        child:
                            GestureDetector(
                          onTap:
                              _sendMessage,
                          child:
                              AnimatedScale(
                            duration:
                                const Duration(
                              milliseconds:
                                  130,
                            ),
                            curve:
                                Curves
                                    .easeOutCubic,
                            scale:
                                isWindowsDesktop &&
                                        _sendButtonHovered
                                    ? 1.075
                                    : 1.0,
                            child:
                                AnimatedContainer(
                              duration:
                                  const Duration(
                                milliseconds:
                                    150,
                              ),
                              curve:
                                  Curves
                                      .easeOutCubic,
                              width:
                                  isWindowsDesktop
                                      ? 48
                                      : null,
                              height:
                                  isWindowsDesktop
                                      ? 48
                                      : null,
                              padding:
                                  isWindowsDesktop
                                      ? EdgeInsets
                                          .zero
                                      : const EdgeInsets
                                          .all(
                                          12,
                                        ),
                              alignment:
                                  Alignment
                                      .center,
                              decoration:
                                  BoxDecoration(
                                shape:
                                    BoxShape
                                        .circle,
                                gradient:
                                    const LinearGradient(
                                  colors: [
                                    _gold,
                                    _darkGold,
                                  ],
                                ),
                                border:
                                    isWindowsDesktop &&
                                            _sendButtonHovered
                                        ? Border.all(
                                            color:
                                                Colors.white.withValues(
                                              alpha:
                                                  0.20,
                                            ),
                                            width:
                                                0.8,
                                          )
                                        : null,
                                boxShadow:
                                    isWindowsDesktop
                                        ? [
                                            BoxShadow(
                                              color:
                                                  _gold.withValues(
                                                alpha:
                                                    _sendButtonHovered
                                                        ? 0.38
                                                        : 0.24,
                                              ),
                                              blurRadius:
                                                  _sendButtonHovered
                                                      ? 18
                                                      : 12,
                                              spreadRadius:
                                                  _sendButtonHovered
                                                      ? 1
                                                      : 0,
                                            ),
                                          ]
                                        : null,
                              ),
                              child:
                                  const Icon(
                                Icons.send,
                                color:
                                    Colors.black,
                                size: 20,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
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

  @override
  Widget build(
    BuildContext context,
  ) {
    final keyboardHeight =
        MediaQuery.viewInsetsOf(
      context,
    ).bottom;

    return Scaffold(
      backgroundColor:
          const Color(
        0xFF0A0A0A,
      ),
      resizeToAvoidBottomInset:
          false,
      appBar: AppBar(
        automaticallyImplyLeading:
            !Platform.isWindows,
        toolbarHeight:
            Platform.isWindows
                ? 66
                : kToolbarHeight,
        titleSpacing:
            Platform.isWindows
                ? 22
                : 0,
        title: Row(
          children: [
            _buildContactAvatar(),

            const SizedBox(
              width: 10,
            ),

            Expanded(
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.targetUser,
                    maxLines: 1,
                    overflow:
                        TextOverflow.ellipsis,
                    style:
                        TextStyle(
                      color:
                          Colors.white,
                      fontSize:
                          Platform.isWindows
                              ? 18
                              : 17,
                      fontWeight:
                          FontWeight.w600,
                    ),
                  ),

                  const SizedBox(
                    height: 2,
                  ),

                  Platform.isWindows
                      ? AnimatedSwitcher(
                          duration:
                              const Duration(
                            milliseconds:
                                220,
                          ),
                          switchInCurve:
                              Curves
                                  .easeOutCubic,
                          switchOutCurve:
                              Curves
                                  .easeInCubic,
                          transitionBuilder: (
                            child,
                            animation,
                          ) {
                            return FadeTransition(
                              opacity:
                                  animation,
                              child:
                                  SlideTransition(
                                position:
                                    Tween<
                                        Offset>(
                                  begin:
                                      const Offset(
                                    0,
                                    0.18,
                                  ),
                                  end:
                                      Offset.zero,
                                ).animate(
                                  animation,
                                ),
                                child:
                                    child,
                              ),
                            );
                          },
                          child:
                              Row(
                            key:
                                ValueKey(
                              _contactIsTyping
                                  ? 'typing'
                                  : _contactOnline
                                      ? 'online'
                                      : _formatContactStatus(),
                            ),
                            mainAxisSize:
                                MainAxisSize
                                    .min,
                            children: [
                              AnimatedContainer(
                                duration:
                                    const Duration(
                                  milliseconds:
                                      220,
                                ),
                                width: 6,
                                height: 6,
                                decoration:
                                    BoxDecoration(
                                  shape:
                                      BoxShape
                                          .circle,
                                  color:
                                      _contactIsTyping
                                          ? _gold
                                          : _contactOnline
                                              ? Colors
                                                  .greenAccent
                                              : Colors
                                                  .white38,
                                  boxShadow:
                                      (_contactIsTyping ||
                                              _contactOnline)
                                          ? [
                                              BoxShadow(
                                                color:
                                                    (_contactIsTyping
                                                            ? _gold
                                                            : Colors.greenAccent)
                                                        .withValues(
                                                  alpha:
                                                      0.28,
                                                ),
                                                blurRadius:
                                                    8,
                                              ),
                                            ]
                                          : const [],
                                ),
                              ),
                              const SizedBox(
                                width: 6,
                              ),
                              Flexible(
                                child:
                                    Text(
                                  _contactIsTyping
                                      ? 'печатает...'
                                      : _formatContactStatus(),
                                  maxLines: 1,
                                  overflow:
                                      TextOverflow
                                          .ellipsis,
                                  style:
                                      TextStyle(
                                    color:
                                        _contactIsTyping
                                            ? _gold
                                            : _contactOnline
                                                ? Colors
                                                    .greenAccent
                                                : Colors
                                                    .white60,
                                    fontSize:
                                        12,
                                    fontWeight:
                                        _contactIsTyping
                                            ? FontWeight
                                                .w600
                                            : FontWeight
                                                .w400,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : Text(
                          _formatContactStatus(),
                          maxLines: 1,
                          overflow:
                              TextOverflow
                                  .ellipsis,
                          style:
                              TextStyle(
                            color:
                                _contactOnline
                                    ? Colors
                                        .greenAccent
                                    : Colors
                                        .white60,
                            fontSize: 11,
                            fontWeight:
                                FontWeight
                                    .w400,
                          ),
                        ),
                ],
              ),
            ),
          ],
        ),
        backgroundColor:
            const Color(
          0xFF111111,
        ),
        foregroundColor:
            Colors.white,
        elevation: 0,
        shadowColor:
            Colors.transparent,
        surfaceTintColor:
            Colors.transparent,
        shape:
            Platform.isWindows
                ? Border(
                    bottom:
                        BorderSide(
                      color:
                          (_contactIsTyping
                                  ? _gold
                                  : _contactOnline
                                      ? _gold
                                      : _gold)
                              .withValues(
                        alpha:
                            _contactIsTyping
                                ? 0.38
                                : _contactOnline
                                    ? 0.28
                                    : 0.22,
                      ),
                      width:
                          _contactIsTyping
                              ? 1.0
                              : 0.8,
                    ),
                  )
                : null,
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackground(),

          AnimatedPadding(
            duration:
                const Duration(
              milliseconds: 180,
            ),
            curve:
                Curves.easeOut,
            padding:
                EdgeInsets.only(
              bottom:
                  keyboardHeight,
            ),
            child: Column(
              children: [
                Expanded(
                  child:
                      _buildMessages(),
                ),
                _buildMessageInput(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
