import '../features/messages/domain/message_identity.dart';
import '../features/messages/domain/message_reactions.dart';
import '../features/messages/domain/message_date.dart';
import '../services/message_chronology.dart';
import '../theme/fenyvo_theme.dart';
import '../widgets/emoji_picker.dart';
import '../services/saved_messages_service.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../services/socket_service.dart';
import '../services/call_service.dart';
import '../services/call_history_service.dart';
import '../services/pulse_service.dart';
import '../services/fenyvo_shield_service.dart';
import '../services/fenyvo_trust_service.dart';
import '../services/storage_service.dart';
import '../services/screen_security_service.dart';
import '../services/media_cache_service.dart';
import '../services/download_service.dart';
import '../services/media_transfer_service.dart';
import '../services/app_language_service.dart';
import '../services/message_search_service.dart';
import '../services/e2ee_settings_service.dart';
import '../services/crypto/signal_e2ee_service.dart';
part '../widgets/private_video_widgets.dart';

String _chatText(String key, [Map<String, Object> values = const {}]) {
  var result = AppLanguageService.instance.text(key);
  for (final entry in values.entries) {
    result = result.replaceAll('{${entry.key}}', entry.value.toString());
  }
  return result;
}

class ChatScreen extends StatefulWidget {
  final String targetUser;

  const ChatScreen({super.key, required this.targetUser});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen>
    with SingleTickerProviderStateMixin {
  static final Map<String, String> _drafts = {};
  late final String _draftKey;
  final TextEditingController _messageController = TextEditingController();

  final FocusNode _messageFocusNode = FocusNode();
  bool _emojiVisible = false;

  final ScrollController _messageScrollController = ScrollController();

  final Map<String, GlobalKey> _messageItemKeys = <String, GlobalKey>{};

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  final List<Map<String, dynamic>> _messages = [];

  Map<String, dynamic>? _replyToMessage;

  String? _backgroundPath;
  double _backgroundOpacity = 0.35;
  String? _contactAvatarBase64;
  bool _contactOnline = false;
  DateTime? _contactLastSeen;
  bool _contactIsTyping = false;
  bool _typingSent = false;

  final ImagePicker _privateImagePicker = ImagePicker();
  bool _sendingPrivateMedia = false;
  List<String> _registeredUsers = const [];
  Completer<List<String>>? _registeredUsersCompleter;

  final AudioRecorder _voiceRecorder = AudioRecorder();
  final AudioPlayer _voicePlayer = AudioPlayer();

  Timer? _voiceRecordTimer;
  StreamSubscription<Duration>? _voicePositionSubscription;
  StreamSubscription<Duration>? _voiceDurationSubscription;
  StreamSubscription<PlayerState>? _voiceStateSubscription;
  StreamSubscription<void>? _voiceCompleteSubscription;

  bool _voicePressActive = false;
  bool _voiceStarting = false;
  bool _isRecordingVoice = false;
  bool _voiceRecordingLocked = false;
  Duration _voiceRecordDuration = Duration.zero;
  Offset? _voiceDragStart;
  String? _voiceRecordingPath;

  String? _playingVoiceMessageId;
  Duration _voicePlaybackPosition = Duration.zero;
  Duration _voicePlaybackDuration = Duration.zero;
  double _voicePlaybackRate = 1.0;
  bool _voiceIsPlaying = false;

  String? _hoveredMessageId;
  bool _contactAvatarHovered = false;
  bool _showScrollToLatest = false;
  bool _scrollToLatestHovered = false;
  int _newMessagesWhileScrolledUp = 0;

  String? _highlightedMessageId;
  bool _searchMode = false;
  String _searchQuery = '';
  List<String> _searchMatchIds = <String>[];
  int _searchMatchIndex = -1;

  final Map<String, Completer<String>> _chatGptCompleters =
      <String, Completer<String>>{};

  final Map<String, Completer<Map<String, dynamic>>> _fenyvoAiCompleters =
      <String, Completer<Map<String, dynamic>>>{};

  bool _autoReplyEnabled = false;
  bool _autoReplyLoading = true;
  String _autoReplyGoal =
      '\u041F\u043E\u0434\u0434\u0435\u0440\u0436\u0438\u0432\u0430\u0442\u044C \u043F\u043E\u043B\u0435\u0437\u043D\u044B\u0439, \u0443\u0432\u0430\u0436\u0438\u0442\u0435\u043B\u044C\u043D\u044B\u0439 \u0434\u0438\u0430\u043B\u043E\u0433 \u0438 \u043F\u043E\u043C\u043E\u0433\u0430\u0442\u044C \u043F\u0440\u0438\u0439\u0442\u0438 \u043A \u043D\u0443\u0436\u043D\u043E\u043C\u0443 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u0443.';
  String _autoReplyPrompt =
      '\u041E\u0442\u0432\u0435\u0447\u0430\u0439 \u043A\u043E\u0440\u043E\u0442\u043A\u043E, \u0435\u0441\u0442\u0435\u0441\u0442\u0432\u0435\u043D\u043D\u043E \u0438 \u0434\u0440\u0443\u0436\u0435\u043B\u044E\u0431\u043D\u043E. \u041E\u0442\u0432\u0435\u0447\u0430\u0439 \u043D\u0430 \u044F\u0437\u044B\u043A\u0435 \u0441\u043E\u0431\u0435\u0441\u0435\u0434\u043D\u0438\u043A\u0430. \u041D\u0435 \u0434\u043E\u0431\u0430\u0432\u043B\u044F\u0439 \u043F\u043E\u044F\u0441\u043D\u0435\u043D\u0438\u0439 \u043E\u0442 \u0441\u0435\u0431\u044F.';
  String _autoReplyContext = '';
  String _autoReplyBoundaries =
      '\u041D\u0435 \u0434\u0430\u0432\u0438, \u043D\u0435 \u0443\u0433\u0440\u043E\u0436\u0430\u0439, \u043D\u0435 \u043E\u0431\u043C\u0430\u043D\u044B\u0432\u0430\u0439 \u0438 \u043D\u0435 \u043C\u0430\u043D\u0438\u043F\u0443\u043B\u0438\u0440\u0443\u0439. \u0423\u0432\u0430\u0436\u0430\u0439 \u043E\u0442\u043A\u0430\u0437 \u0438 \u043F\u0440\u043E\u0441\u044C\u0431\u0443 \u043F\u0440\u0435\u043A\u0440\u0430\u0442\u0438\u0442\u044C \u043E\u0431\u0449\u0435\u043D\u0438\u0435.';
  String _autoReplyMode = 'auto';
  int _autoReplyIdleSeconds = 60;
  int _autoReplyDelaySeconds = 5;
  String? _dismissedShieldFingerprint;
  bool _contactTrusted = false;
  bool _contactBlocked = false;
  bool _contactReported = false;
  bool _e2eeActive = false;
  bool _e2eeVerified = false;
  bool _e2eeKeyChanged = false;
  bool _e2eeKeyChangeWarningShown = false;
  bool _changingE2ee = false;
  bool _screenSecurityEnabled = false;

  Timer? _typingStopTimer;
  Timer? _remoteTypingTimeoutTimer;
  Timer? _pinnedHighlightTimer;

  late final AnimationController _typingAnimationController;

  static const Color _gold = FenyvoPalette.gold;

  static const List<String> _supportedReactions = [
    '\u2764\uFE0F',
    '\u{1F602}',
    '\u{1F62E}',
    '\u{1F622}',
    '\u{1F621}',
    '\u{1F44D}',
    '\u{1F525}',
    '\u{1F389}',
    '\u{1F44F}',
    '\u{1F64F}',
    '\u{1F4AF}',
    '\u{1F923}',
    '\u{1F60A}',
    '\u{1F60D}',
    '\u{1F914}',
    '\u{1F60E}',
    '\u{1F62D}',
    '\u{1F631}',
    '\u{1F91D}',
    '\u{1F440}',
    '\u{1F4AA}',
    '\u2705',
    '\u2B50',
    '\u{1F494}',
  ];

  bool _handleWindowsTypeToPrivateChat(KeyEvent event) {
    if (!Platform.isWindows || !mounted || event is! KeyDownEvent) {
      return false;
    }

    final keyboard = HardwareKeyboard.instance;

    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return false;
    }

    if (_messageFocusNode.hasFocus ||
        _searchMode ||
        _searchFocusNode.hasFocus) {
      return false;
    }

    final focusedWidget = FocusManager.instance.primaryFocus?.context?.widget;

    if (focusedWidget is EditableText) {
      return false;
    }

    final character = event.character;

    if (character == null || character.isEmpty) {
      return false;
    }

    if (character.runes.any((rune) => rune < 0x20 || rune == 0x7F)) {
      return false;
    }

    final value = _messageController.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);

    final start = selection.start < 0
        ? value.text.length
        : selection.start > value.text.length
        ? value.text.length
        : selection.start;

    final end = selection.end < 0
        ? start
        : selection.end > value.text.length
        ? value.text.length
        : selection.end;

    final newText = value.text.replaceRange(start, end, character);
    final newOffset = start + character.length;

    _messageController.value = value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
      composing: TextRange.empty,
    );

    _handleTextChanged(newText);
    _messageFocusNode.requestFocus();

    return true;
  }

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      HardwareKeyboard.instance.addHandler(_handleWindowsTypeToPrivateChat);
    }
    AppLanguageService.instance.code.addListener(_refreshLanguage);
    CallHistoryService.changes.addListener(_refreshCallHistory);
    _draftKey =
        '${SocketService.instance.currentUser ?? ''}::${widget.targetUser}';
    _messageController.text = _drafts[_draftKey] ?? '';
    _messageController.selection = TextSelection.collapsed(
      offset: _messageController.text.length,
    );

    SocketService.instance.setActiveChatUser(widget.targetUser);
    _e2eeActive = SocketService.instance.isE2eeActiveWith(widget.targetUser);

    _typingAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _messageScrollController.addListener(_handleMessageScroll);

    _voicePositionSubscription = _voicePlayer.onPositionChanged.listen((
      position,
    ) {
      if (!mounted || _playingVoiceMessageId == null) {
        return;
      }

      setState(() {
        _voicePlaybackPosition = position;
      });
    });

    _voiceDurationSubscription = _voicePlayer.onDurationChanged.listen((
      duration,
    ) {
      if (!mounted || _playingVoiceMessageId == null) {
        return;
      }

      setState(() {
        _voicePlaybackDuration = duration;
      });
    });

    _voiceStateSubscription = _voicePlayer.onPlayerStateChanged.listen((state) {
      if (!mounted) {
        return;
      }

      setState(() {
        _voiceIsPlaying = state == PlayerState.playing;
      });
    });

    _voiceCompleteSubscription = _voicePlayer.onPlayerComplete.listen((_) {
      if (!mounted) {
        return;
      }

      setState(() {
        _voiceIsPlaying = false;
        _voicePlaybackPosition = Duration.zero;
        _playingVoiceMessageId = null;
      });
    });

    _loadMessages();
    _loadBackgroundSettings();
    if (Platform.isAndroid || Platform.isWindows) {
      unawaited(_loadScreenSecuritySetting());
    }
    _loadContactAvatar();
    unawaited(_loadTrustState());

    SocketService.instance.addMessageHandler(_handleMessage);

    SocketService.instance.requestAutoReplySettings(widget.targetUser);

    _clearUnread();

    SocketService.instance.requestAvatar(widget.targetUser);

    SocketService.instance.getUserStatus(widget.targetUser);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_refreshE2eeVerification(showChangedWarning: true));
    });
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      HardwareKeyboard.instance.removeHandler(_handleWindowsTypeToPrivateChat);
    }
    AppLanguageService.instance.code.removeListener(_refreshLanguage);
    CallHistoryService.changes.removeListener(_refreshCallHistory);
    SocketService.instance.clearActiveChatUser(widget.targetUser);
    if (Platform.isAndroid || Platform.isWindows) {
      unawaited(ScreenSecurityService.setSecure(false));
    }

    if (_typingSent) {
      SocketService.instance.sendTyping(widget.targetUser, false);
    }

    _typingStopTimer?.cancel();
    _remoteTypingTimeoutTimer?.cancel();
    _pinnedHighlightTimer?.cancel();

    for (final completer in _chatGptCompleters.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('\u0427\u0430\u0442 \u0437\u0430\u043A\u0440\u044B\u0442'),
        );
      }
    }
    _chatGptCompleters.clear();

    for (final completer in _fenyvoAiCompleters.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          StateError('\u0427\u0430\u0442 \u0437\u0430\u043A\u0440\u044B\u0442'),
        );
      }
    }
    _fenyvoAiCompleters.clear();

    _typingAnimationController.dispose();

    SocketService.instance.removeMessageHandler(_handleMessage);

    _messageScrollController.removeListener(_handleMessageScroll);
    _messageScrollController.dispose();

    _messageFocusNode.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _drafts[_draftKey] = _messageController.text;
    _messageController.dispose();

    _voiceRecordTimer?.cancel();
    _voicePositionSubscription?.cancel();
    _voiceDurationSubscription?.cancel();
    _voiceStateSubscription?.cancel();
    _voiceCompleteSubscription?.cancel();
    unawaited(_voiceRecorder.dispose());
    unawaited(_voicePlayer.dispose());

    super.dispose();
  }

  void _refreshLanguage() {
    if (mounted) setState(() {});
  }

  // ========================================
  // \u0417\u0410\u0413\u0420\u0423\u0417\u041A\u0410 \u0424\u041E\u041D\u0410
  // ========================================

  Future<void> _loadBackgroundSettings() async {
    final background = await StorageService.getLightBackground();

    final opacity = await StorageService.getBackgroundOpacity();

    if (!mounted) {
      return;
    }

    String? validBackground;

    if (background != null && background.isNotEmpty) {
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
  // \u0410\u0412\u0410\u0422\u0410\u0420 \u041A\u041E\u041D\u0422\u0410\u041A\u0422\u0410
  // ========================================

  void _loadContactAvatar() {
    final avatar = StorageService.getAvatar(widget.targetUser);

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

    if (avatar != null && avatar.isNotEmpty) {
      try {
        imageProvider = MemoryImage(base64Decode(avatar));
      } catch (_) {
        imageProvider = null;
      }
    }

    final ringColor = _contactTrusted
        ? FenyvoPalette.gold
        : _contactOnline
        ? FenyvoPalette.online
        : FenyvoPalette.line;
    final avatarStack = Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor, width: 2),
        boxShadow: (_contactTrusted || _contactOnline)
            ? [
                BoxShadow(
                  color: ringColor.withValues(alpha: .24),
                  blurRadius: 10,
                ),
              ]
            : const [],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          CircleAvatar(
            radius: Platform.isWindows ? 22 : 20,
            backgroundColor: FenyvoPalette.surface,
            backgroundImage: imageProvider,
            child: imageProvider == null
                ? Text(
                    widget.targetUser.isNotEmpty
                        ? widget.targetUser[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),
          if (_contactOnline)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: Platform.isWindows ? 13 : 12,
                height: Platform.isWindows ? 13 : 12,
                decoration: BoxDecoration(
                  color: FenyvoPalette.online,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: FenyvoPalette.canvasDeep,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    if (!Platform.isWindows) {
      return avatarStack;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.basic,
      onEnter: (_) {
        if (!_contactAvatarHovered) {
          setState(() {
            _contactAvatarHovered = true;
          });
        }
      },
      onExit: (_) {
        if (_contactAvatarHovered) {
          setState(() {
            _contactAvatarHovered = false;
          });
        }
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        scale: _contactAvatarHovered ? 1.045 : 1.0,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow:
                (_contactOnline || _contactIsTyping || _contactAvatarHovered)
                ? [
                    BoxShadow(
                      color:
                          (_contactIsTyping
                                  ? _gold
                                  : _contactOnline
                                  ? Colors.greenAccent
                                  : _gold)
                              .withValues(
                                alpha: _contactAvatarHovered ? 0.24 : 0.18,
                              ),
                      blurRadius: _contactAvatarHovered ? 18 : 14,
                      spreadRadius: _contactAvatarHovered ? 1.5 : 1,
                    ),
                  ]
                : const [],
          ),
          child: avatarStack,
        ),
      ),
    );
  }

  // ========================================
  // \u0421\u0422\u0410\u0422\u0423\u0421 \u041A\u041E\u041D\u0422\u0410\u041A\u0422\u0410
  // ========================================

  String _formatContactStatus() {
    if (_contactOnline) {
      return _chatText('online');
    }

    final lastSeen = _contactLastSeen;

    if (lastSeen == null) {
      return _chatText('offline');
    }

    final local = lastSeen.toLocal();

    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    final seenDay = DateTime(local.year, local.month, local.day);

    final difference = today.difference(seenDay).inDays;

    final time =
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';

    if (difference == 0) {
      return _chatText('lastSeenToday', {'time': time});
    }

    if (difference == 1) {
      return _chatText('lastSeenYesterday', {'time': time});
    }

    final date =
        '${local.day.toString().padLeft(2, '0')}.'
        '${local.month.toString().padLeft(2, '0')}.'
        '${local.year}';

    return _chatText('lastSeenDate', {'date': date, 'time': time});
  }

  // ========================================
  // TYPING \u2014 \u041E\u0422\u041F\u0420\u0410\u0412\u041A\u0410
  // ========================================

  void _handleTextChanged(String value) {
    if (mounted) {
      setState(() {});
    }

    final hasText = value.trim().isNotEmpty;

    _typingStopTimer?.cancel();

    if (!hasText) {
      _stopTyping();
      return;
    }

    if (!_typingSent) {
      _typingSent = true;

      SocketService.instance.sendTyping(widget.targetUser, true);
    }

    _typingStopTimer = Timer(const Duration(milliseconds: 1400), _stopTyping);
  }

  void _stopTyping() {
    _typingStopTimer?.cancel();
    _typingStopTimer = null;

    if (!_typingSent) {
      return;
    }

    _typingSent = false;

    SocketService.instance.sendTyping(widget.targetUser, false);
  }

  // ========================================
  // TYPING \u2014 \u041F\u041E\u041B\u0423\u0427\u0415\u041D\u0418\u0415
  // ========================================

  void _setContactTyping(bool isTyping) {
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
      _remoteTypingTimeoutTimer = Timer(const Duration(seconds: 4), () {
        if (!mounted) {
          return;
        }

        setState(() {
          _contactIsTyping = false;
        });
      });
    }
  }

  // ========================================
  // \u0410\u041D\u0418\u041C\u0418\u0420\u041E\u0412\u0410\u041D\u041D\u042B\u0415 \u0422\u041E\u0427\u041A\u0418
  // ========================================

  Widget _buildTypingDots() {
    return AnimatedBuilder(
      animation: _typingAnimationController,
      builder: (context, child) {
        final progress = _typingAnimationController.value;

        final activeIndex = (progress * 3).floor() % 3;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (index) {
            final active = index == activeIndex;

            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: active ? 7 : 5,
              height: active ? 7 : 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: FenyvoPalette.blue.withValues(
                  alpha: active ? 1.0 : 0.40,
                ),
                boxShadow: active
                    ? [
                        BoxShadow(
                          color: _gold.withValues(alpha: 0.06),
                          blurRadius: 5,
                        ),
                      ]
                    : null,
              ),
            );
          }),
        );
      },
    );
  }

  Widget _buildTypingIndicator() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: !_contactIsTyping
          ? const SizedBox.shrink()
          : Container(
              key: const ValueKey('typing_indicator'),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 7, 18, 5),
              color: FenyvoPalette.surface,
              child: Row(
                children: [
                  const Icon(Icons.edit_outlined, size: 14, color: _gold),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      '${widget.targetUser} \u043F\u0435\u0447\u0430\u0442\u0430\u0435\u0442',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: FenyvoPalette.secondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  _buildTypingDots(),
                ],
              ),
            ),
    );
  }

  // ========================================
  // \u0417\u0410\u0413\u0420\u0423\u0417\u041A\u0410 \u0421\u041E\u041E\u0411\u0429\u0415\u041D\u0418\u0419
  // ========================================

  void _loadMessages() {
    final currentUser = SocketService.instance.currentUser;

    if (currentUser == null || currentUser.isEmpty) {
      return;
    }

    final savedMessages = StorageService.getMessages(
      currentUser,
      widget.targetUser,
    );
    final pinnedMessageIds = StorageService.getPinnedMessages(
      currentUser,
      widget.targetUser,
    ).map((item) => item['messageId']?.toString().trim() ?? '').toSet();

    setState(() {
      _messages.clear();

      for (final savedMessage in savedMessages) {
        final message = Map<String, dynamic>.from(savedMessage);

        if (pinnedMessageIds.contains(_getMessageId(message))) {
          message['isPinned'] = true;
        }

        _normalizeReactionUsers(message);

        final isMe =
            message['isMe'] == true ||
            message['from']?.toString() == currentUser;

        message['isMe'] = isMe;

        if (isMe) {
          final status = message['status']?.toString().trim() ?? '';

          if (status.isEmpty) {
            message['status'] = 'sent';
          }
        }

        _messages.add(message);
      }

      _messages.addAll(_callHistoryMessages(currentUser));

      _sortMessagesChronologically();
    });

    _markIncomingMessagesRead();
  }

  void _sortMessagesChronologically() {
    MessageChronology.sort(_messages);
  }

  List<Map<String, dynamic>> _callHistoryMessages(String owner) {
    return CallHistoryService.items(owner)
        .where((item) => item['peer']?.toString() == widget.targetUser)
        .map(
          (item) => <String, dynamic>{
            'id': 'local-call-${item['id']}',
            'time': item['time'],
            'isMe': item['incoming'] != true,
            'from': item['incoming'] == true ? widget.targetUser : owner,
            'messageType': 'call',
            'localCallEntry': true,
            'call': Map<String, dynamic>.from(item),
          },
        )
        .toList();
  }

  void _refreshCallHistory() {
    if (!mounted) return;
    final owner = SocketService.instance.currentUser ?? '';
    setState(() {
      _messages.removeWhere((item) => item['localCallEntry'] == true);
      _messages.addAll(_callHistoryMessages(owner));
      _sortMessagesChronologically();
    });
  }

  // ========================================
  // \u0421\u041E\u0425\u0420\u0410\u041D\u0415\u041D\u0418\u0415 \u0421\u041E\u041E\u0411\u0429\u0415\u041D\u0418\u0419
  // ========================================

  void _saveMessages() {
    final currentUser = SocketService.instance.currentUser;

    if (currentUser == null || currentUser.isEmpty) {
      return;
    }

    StorageService.saveMessages(
      currentUser,
      widget.targetUser,
      _messages.where((message) => message['localCallEntry'] != true).toList(),
    );
  }

  // ========================================
  // \u041E\u0427\u0418\u0421\u0422\u041A\u0410 \u041D\u0415\u041F\u0420\u041E\u0427\u0418\u0422\u0410\u041D\u041D\u042B\u0425
  // ========================================

  void _clearUnread() {
    final currentUser = SocketService.instance.currentUser;

    if (currentUser == null || currentUser.isEmpty) {
      return;
    }

    StorageService.clearUnreadCount(currentUser, widget.targetUser);
  }

  // ========================================
  // \u0421\u0422\u0410\u0422\u0423\u0421 \u0421\u041E\u041E\u0411\u0429\u0415\u041D\u0418\u042F
  // ========================================

  int _messageStatusRank(String status) {
    switch (status) {
      case 'read':
        return 5;
      case 'delivered':
        return 4;
      case 'sent':
        return 3;
      case 'sending':
        return 2;
      case 'queued':
        return 1;
      default:
        return 0;
    }
  }

  void _syncConfirmedMessageTime(String messageId, String serverTime) {
    final id = messageId.trim();
    final parsedTime = DateTime.tryParse(serverTime);
    if (id.isEmpty || parsedTime == null || !mounted) return;

    final index = _messages.indexWhere(
      (message) => message['id']?.toString().trim() == id,
    );
    if (index < 0 || _messages[index]['isMe'] != true) return;

    setState(() {
      _messages[index]['time'] = parsedTime.toUtc().toIso8601String();
      _sortMessagesChronologically();
    });
    _saveMessages();
  }

  void _updateMessageStatus(String messageId, String newStatus) {
    final id = messageId.trim();

    if (id.isEmpty) {
      return;
    }

    final messageIndex = _messages.indexWhere(
      (message) => message['id']?.toString().trim() == id,
    );

    if (messageIndex == -1) {
      return;
    }

    final message = _messages[messageIndex];

    if (message['isMe'] != true) {
      return;
    }

    final oldStatus = message['status']?.toString().trim() ?? '';

    if (_messageStatusRank(newStatus) <= _messageStatusRank(oldStatus)) {
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _messages[messageIndex]['status'] = newStatus;
    });

    _saveMessages();
  }

  // ========================================
  // \u041F\u0420\u041E\u0427\u0422\u0415\u041D\u0418\u0415 \u0412\u0425\u041E\u0414\u042F\u0429\u0418\u0425 \u0421\u041E\u041E\u0411\u0429\u0415\u041D\u0418\u0419
  // ========================================

  void _markIncomingMessagesRead() {
    final currentUser = SocketService.instance.currentUser ?? '';

    if (currentUser.isEmpty || !SocketService.instance.isConnected) {
      return;
    }

    bool changed = false;

    for (final message in _messages) {
      final from = message['from']?.toString().trim() ?? '';

      final to = message['to']?.toString().trim() ?? '';

      final messageId = message['id']?.toString().trim() ?? '';

      final alreadyRead = message['readByMe'] == true;

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
  // ID \u0421\u041E\u041E\u0411\u0429\u0415\u041D\u0418\u042F
  // ========================================

  String _getMessageId(Map<String, dynamic> message) {
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
  // \u0420\u0415\u0410\u041A\u0426\u0418\u0418 \u041F\u041E\u041B\u042C\u0417\u041E\u0412\u0410\u0422\u0415\u041B\u0415\u0419
  // ========================================

  Map<String, String> _getMessageReactions(Map<String, dynamic> message) {
    return parseStoredMessageReactions(message, _supportedReactions);
  }

  void _normalizeReactionUsers(Map<String, dynamic> message) {
    message['reactions'] = _getMessageReactions(message);
    message.remove('reactionUsers');
    message.remove('reaction');
  }

  String _reactionStateKey(Map<String, dynamic> message) {
    final reactions = _getMessageReactions(message).entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return reactions.map((entry) => '${entry.key}:${entry.value}').join('|');
  }

  // ========================================
  // \u041F\u041E\u041B\u0423\u0427\u0415\u041D\u0418\u0415 \u0421\u041E\u0411\u042B\u0422\u0418\u0419 \u041E\u0422 \u0421\u0415\u0420\u0412\u0415\u0420\u0410
  // ========================================

  void _showE2eeNotice(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _loadScreenSecuritySetting() async {
    if (!Platform.isAndroid && !Platform.isWindows) return;

    // Keep the chat protected while its stored preference is loading.
    await ScreenSecurityService.setSecure(true);

    final currentUser = SocketService.instance.currentUser ?? '';
    if (currentUser.isEmpty) {
      if (mounted) await ScreenSecurityService.setSecure(false);
      return;
    }

    final enabled = await StorageService.getChatScreenSecurity(
      currentUser,
      widget.targetUser,
    );

    if (!mounted) return;

    await ScreenSecurityService.setSecure(enabled);
    if (!mounted) return;

    setState(() {
      _screenSecurityEnabled = enabled;
    });
  }

  Future<void> _toggleScreenSecurity() async {
    if (!Platform.isAndroid && !Platform.isWindows) return;

    final currentUser = SocketService.instance.currentUser ?? '';
    if (currentUser.isEmpty) return;

    final enabled = !_screenSecurityEnabled;

    await ScreenSecurityService.setSecure(enabled);
    await StorageService.setChatScreenSecurity(
      currentUser,
      widget.targetUser,
      enabled,
    );

    if (!mounted) return;

    setState(() {
      _screenSecurityEnabled = enabled;
    });
  }

  Future<void> _toggleChatE2ee() async {
    if (_changingE2ee) return;
    if (_e2eeActive) {
      final disable = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_chatText('e2eeChatDisable')),
          content: Text(
            '${widget.targetUser}: ${_chatText('e2eeChatDisable')}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_chatText('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(_chatText('e2eeDisableAction')),
            ),
          ],
        ),
      );
      if (disable != true || !mounted) return;
      setState(() => _changingE2ee = true);
      final sent = await SocketService.instance.respondToE2eeInvite(
        widget.targetUser,
        false,
      );
      if (!mounted) return;
      setState(() {
        _changingE2ee = false;
        if (sent) _e2eeActive = false;
      });
      if (!sent) _showE2eeNotice(_chatText('noServerConnection'));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.lock_rounded, color: _gold, size: 42),
        title: Text(_chatText('e2eeBeforeTitle')),
        content: SingleChildScrollView(
          child: Text(_chatText('e2eeBeforeText')),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_chatText('e2eeNotNow')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.lock_rounded),
            label: Text(_chatText('e2eeEnable')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _changingE2ee = true);
    final sent = await SocketService.instance.inviteE2ee(widget.targetUser);
    if (!mounted) return;
    setState(() => _changingE2ee = false);
    _showE2eeNotice(
      sent ? _chatText('e2eeInviteSent') : _chatText('e2eeEnableError'),
    );
  }

  Future<void> _showIncomingE2eeInvite(String from) async {
    final accepted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(_chatText('e2eeInviteTitle')),
        content: Text(_chatText('e2eeInviteText', {'user': from})),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_chatText('e2eeDecline')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.lock_rounded),
            label: Text(_chatText('e2eeAccept')),
          ),
        ],
      ),
    );
    if (!mounted) return;
    setState(() => _changingE2ee = true);
    final sent = await SocketService.instance.respondToE2eeInvite(
      from,
      accepted == true,
    );
    if (!mounted) return;
    setState(() {
      _changingE2ee = false;
      if (sent) _e2eeActive = accepted == true;
    });
    if (!sent) _showE2eeNotice(_chatText('e2eeEnableError'));
  }

  Future<void> _refreshE2eeVerification({
    bool showChangedWarning = false,
  }) async {
    final currentUser = SocketService.instance.currentUser?.trim() ?? '';
    if (currentUser.isEmpty || !_e2eeActive) {
      if (mounted) {
        setState(() {
          _e2eeVerified = false;
          _e2eeKeyChanged = false;
        });
      }
      return;
    }

    try {
      final safety = await SignalE2eeService.instance.safetyNumber(
        widget.targetUser,
      );
      final stored = await E2eeSettingsService.instance.verifiedFingerprint(
        currentUser,
        widget.targetUser,
      );
      final verified = stored != null && stored == safety.display;
      final changed = stored != null && stored != safety.display;
      if (!mounted) return;
      setState(() {
        _e2eeVerified = verified;
        _e2eeKeyChanged = changed;
      });
      if (changed && showChangedWarning && !_e2eeKeyChangeWarningShown) {
        _e2eeKeyChangeWarningShown = true;
        await _showE2eeKeyChangedWarning();
      }
    } on E2eeSessionMissing {
      // The safety number becomes available after the first protected message.
    } catch (_) {
      // Verification is optional; a temporary read error must not block chat.
    }
  }

  Future<void> _showE2eeKeyChangedWarning() async {
    if (!mounted) return;
    final verifyNow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(
          Icons.warning_amber_rounded,
          color: Colors.orange,
          size: 46,
        ),
        title: Text(_chatText('e2eeKeyChangedTitle')),
        content: Text(
          _chatText('e2eeKeyChangedText', {'user': widget.targetUser}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(_chatText('e2eeContinueUnverified')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.verified_user_rounded),
            label: Text(_chatText('e2eeVerifyNewCode')),
          ),
        ],
      ),
    );
    if (verifyNow == true && mounted) {
      await _showE2eeSafetyNumber();
    }
  }

  Future<void> _showE2eeSafetyNumber() async {
    final currentUser = SocketService.instance.currentUser?.trim() ?? '';
    if (currentUser.isEmpty || !_e2eeActive) return;
    try {
      final safety = await SignalE2eeService.instance.safetyNumber(
        widget.targetUser,
      );
      final verified = await E2eeSettingsService.instance.isFingerprintVerified(
        currentUser,
        widget.targetUser,
        safety.display,
      );
      if (!mounted) return;
      final markVerified = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_chatText('e2eeVerifyTitle')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _chatText('e2eeVerifyExplanation', {
                    'user': widget.targetUser,
                  }),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.white,
                  child: QrImageView(
                    data: safety.scannable,
                    version: QrVersions.auto,
                    size: 190,
                    backgroundColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 18),
                SelectableText(
                  safety.display,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.55,
                    letterSpacing: 1.1,
                  ),
                ),
                if (verified) ...[
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.verified_rounded, color: Colors.green),
                      const SizedBox(width: 8),
                      Text(_chatText('e2eeVerified')),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: safety.display));
              },
              icon: const Icon(Icons.copy_rounded),
              label: Text(_chatText('copy')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(_chatText('close')),
            ),
            FilledButton.icon(
              onPressed: verified ? null : () => Navigator.pop(context, true),
              icon: const Icon(Icons.verified_user_rounded),
              label: Text(_chatText('e2eeCodesMatch')),
            ),
          ],
        ),
      );
      if (markVerified == true) {
        await E2eeSettingsService.instance.setFingerprintVerified(
          currentUser,
          widget.targetUser,
          safety.display,
        );
        if (mounted) {
          setState(() {
            _e2eeVerified = true;
            _e2eeKeyChanged = false;
          });
          _showE2eeNotice(_chatText('e2eeVerified'));
        }
      } else if (mounted) {
        setState(() => _e2eeVerified = verified);
      }
    } on E2eeSessionMissing {
      _showE2eeNotice(_chatText('e2eeVerifyNeedsMessage'));
    } catch (_) {
      _showE2eeNotice(_chatText('e2eeVerifyError'));
    }
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final type = msg['type']?.toString() ?? '';

    final rawData = msg['data'];

    final Map<String, dynamic> data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};

    final currentUser = SocketService.instance.currentUser ?? '';

    // PRESENCE_STEP13: a disconnected socket cannot confirm peer presence.
    if (type == 'disconnected') {
      if (mounted) {
        setState(() {
          _contactOnline = false;
          _contactLastSeen = null;
        });
      }
      return;
    }

    // Re-query the peer status after successful authentication.
    if (type == 'login_success') {
      if (mounted) {
        setState(() {
          _contactOnline = false;
          _contactLastSeen = null;
        });
        SocketService.instance.getUserStatus(widget.targetUser);
      }
      return;
    }
    if (type == 'registered_users') {
      final rawUsers = data['users'];
      if (rawUsers is List) {
        final me = currentUser.trim().toLowerCase();
        final users =
            rawUsers
                .map((e) => e?.toString().trim() ?? '')
                .where((e) => e.isNotEmpty && e.toLowerCase() != me)
                .toSet()
                .toList()
              ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        _registeredUsers = users;
        final completer = _registeredUsersCompleter;
        if (completer != null && !completer.isCompleted) {
          completer.complete(users);
        }
      }
      return;
    }

    if (type == 'e2ee_invite' &&
        data['from']?.toString().trim() == widget.targetUser) {
      unawaited(_showIncomingE2eeInvite(widget.targetUser));
      return;
    }

    if (type == 'e2ee_invite_response' &&
        data['from']?.toString().trim() == widget.targetUser) {
      final accepted = data['accepted'] == true;
      if (mounted) setState(() => _e2eeActive = accepted);
      if (accepted) {
        unawaited(_refreshE2eeVerification(showChangedWarning: true));
      }
      _showE2eeNotice(
        accepted
            ? _chatText('e2eeInviteAccepted')
            : _chatText('e2eeInviteDeclined'),
      );
      return;
    }

    if (type == 'e2ee_invite_status' &&
        data['to']?.toString().trim() == widget.targetUser &&
        data['sent'] != true) {
      _showE2eeNotice(
        data['reason']?.toString().trim().isNotEmpty == true
            ? data['reason'].toString()
            : _chatText('e2eeEnableError'),
      );
      return;
    }

    if (type == 'trust_state' || type == 'trust_updated') {
      final contact = data['contact']?.toString().trim() ?? '';
      if (contact != widget.targetUser ||
          (type == 'trust_state' && data['hasState'] != true)) {
        return;
      }
      unawaited(_applyRemoteTrustState(data));
      return;
    }

    if (type == 'spartan_ai_result' || type == 'spartan_ai_history') {
      final requestId = data['requestId']?.toString().trim() ?? '';

      final completer = _fenyvoAiCompleters.remove(requestId);

      if (completer != null && !completer.isCompleted) {
        completer.complete(data);
      }

      return;
    }

    if (type == 'spartan_ai_error') {
      final requestId = data['requestId']?.toString().trim() ?? '';
      final reason = data['reason']?.toString().trim() ?? 'FENYVO AI error';

      final completer = _fenyvoAiCompleters.remove(requestId);

      if (completer != null && !completer.isCompleted) {
        completer.completeError(Exception(reason));
      }

      return;
    }

    if (type == 'chatgpt_result') {
      final requestId = data['requestId']?.toString().trim() ?? '';
      final result = data['result']?.toString().trim() ?? '';

      final completer = _chatGptCompleters.remove(requestId);

      if (completer != null && !completer.isCompleted) {
        if (result.isEmpty) {
          completer.completeError(
            Exception(
              'ChatGPT \u0432\u0435\u0440\u043D\u0443\u043B \u043F\u0443\u0441\u0442\u043E\u0439 \u043E\u0442\u0432\u0435\u0442',
            ),
          );
        } else {
          completer.complete(result);
        }
      }

      return;
    }

    if (type == 'chatgpt_error') {
      final requestId = data['requestId']?.toString().trim() ?? '';
      final reason =
          data['reason']?.toString().trim() ??
          '\u041E\u0448\u0438\u0431\u043A\u0430 ChatGPT';

      final completer = _chatGptCompleters.remove(requestId);

      if (completer != null && !completer.isCompleted) {
        completer.completeError(Exception(reason));
      }

      return;
    }

    if (type == 'auto_reply_settings') {
      final peer = data['peer']?.toString().trim() ?? '';

      if (peer != widget.targetUser) {
        return;
      }

      final goal = data['goal']?.toString().trim() ?? '';
      final prompt = data['prompt']?.toString().trim() ?? '';
      final aiContext = data['context']?.toString().trim() ?? '';
      final boundaries = data['boundaries']?.toString().trim() ?? '';

      final mode = data['mode']?.toString().trim() ?? 'auto';

      final rawIdle = data['idleSeconds'];

      final idle = rawIdle is int
          ? rawIdle
          : int.tryParse(rawIdle?.toString() ?? '') ?? 60;

      final rawDelay = data['delaySeconds'];

      final delay = rawDelay is int
          ? rawDelay
          : int.tryParse(rawDelay?.toString() ?? '') ?? 5;

      if (mounted) {
        setState(() {
          _autoReplyEnabled = data['enabled'] == true;
          _autoReplyGoal = goal.isNotEmpty ? goal : _autoReplyGoal;
          _autoReplyPrompt = prompt.isNotEmpty ? prompt : _autoReplyPrompt;
          _autoReplyContext = aiContext;
          _autoReplyBoundaries = boundaries.isNotEmpty
              ? boundaries
              : _autoReplyBoundaries;
          _autoReplyMode =
              <String>{'auto', 'suggest', 'idle', 'until_goal'}.contains(mode)
              ? mode
              : 'auto';
          _autoReplyIdleSeconds = <int>[30, 60, 120, 300].contains(idle)
              ? idle
              : 60;
          _autoReplyDelaySeconds = <int>[3, 5, 10].contains(delay) ? delay : 5;
          _autoReplyLoading = false;
        });

        if (data['saved'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _autoReplyEnabled
                    ? '\u{1F916} FENYVO AI \u0430\u0432\u0442\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u0435 \u0432\u043A\u043B\u044E\u0447\u0435\u043D\u043E \u0434\u043B\u044F ${widget.targetUser}'
                    : 'FENYVO AI \u0430\u0432\u0442\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u0435 \u0432\u044B\u043A\u043B\u044E\u0447\u0435\u043D\u043E \u0434\u043B\u044F ${widget.targetUser}',
              ),
              backgroundColor: FenyvoPalette.surface,
              duration: const Duration(milliseconds: 1700),
            ),
          );
        }
      }

      return;
    }

    if (type == 'auto_reply_suggestion') {
      final peer = data['peer']?.toString().trim() ?? '';
      final suggestion = data['text']?.toString().trim() ?? '';

      if (peer != widget.targetUser || suggestion.isEmpty) {
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 10),
            backgroundColor: FenyvoPalette.surface,
            content: Text(
              '\u{1F916} FENYVO AI \u043F\u0440\u0435\u0434\u043B\u0430\u0433\u0430\u0435\u0442: $suggestion',
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
            action: SnackBarAction(
              label: '\u0412\u0441\u0442\u0430\u0432\u0438\u0442\u044C',
              textColor: _gold,
              onPressed: () {
                _messageController.text = suggestion;
                _messageController.selection = TextSelection.collapsed(
                  offset: suggestion.length,
                );
              },
            ),
          ),
        );
      }

      return;
    }

    if (type == 'auto_reply_goal_reached') {
      final peer = data['peer']?.toString().trim() ?? '';

      if (peer != widget.targetUser) {
        return;
      }

      if (mounted) {
        setState(() {
          _autoReplyEnabled = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: FenyvoPalette.surface,
            content: Text(
              '\u2705 FENYVO AI: \u0446\u0435\u043B\u044C \u0434\u0438\u0430\u043B\u043E\u0433\u0430 \u0434\u043E\u0441\u0442\u0438\u0433\u043D\u0443\u0442\u0430. \u0410\u0432\u0442\u043E\u0440\u0435\u0436\u0438\u043C \u043E\u0441\u0442\u0430\u043D\u043E\u0432\u043B\u0435\u043D.',
            ),
          ),
        );
      }

      return;
    }

    if (type == 'auto_reply_history_cleared') {
      final peer = data['peer']?.toString().trim() ?? '';

      if (peer != widget.targetUser) {
        return;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '\u041F\u0430\u043C\u044F\u0442\u044C FENYVO AI \u044D\u0442\u043E\u0433\u043E \u0434\u0438\u0430\u043B\u043E\u0433\u0430 \u043E\u0447\u0438\u0449\u0435\u043D\u0430',
            ),
            backgroundColor: FenyvoPalette.surface,
          ),
        );
      }

      return;
    }

    if (type == 'auto_reply_error') {
      final peer = data['peer']?.toString().trim() ?? '';

      if (peer.isNotEmpty && peer != widget.targetUser) {
        return;
      }

      final reason =
          data['reason']?.toString().trim() ??
          '\u041E\u0448\u0438\u0431\u043A\u0430 \u0430\u0432\u0442\u043E\u043E\u0442\u0432\u0435\u0442\u0430 ChatGPT';

      if (mounted) {
        setState(() {
          _autoReplyLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(reason), backgroundColor: Colors.red.shade800),
        );
      }

      return;
    }

    if (type == 'avatar_data') {
      final username = data['username']?.toString().trim() ?? '';

      if (username == widget.targetUser) {
        _loadContactAvatar();
      }

      return;
    }

    if (type == 'avatar_updated') {
      final username = data['username']?.toString().trim() ?? '';

      if (username == widget.targetUser) {
        SocketService.instance.requestAvatar(widget.targetUser);
      }

      return;
    }

    if (type == 'user_status') {
      final username = data['username']?.toString().trim() ?? '';

      if (username != widget.targetUser) {
        return;
      }

      final online = data['online'] == true;

      final lastSeenRaw = data['lastSeen']?.toString().trim() ?? '';

      DateTime? lastSeen;

      if (lastSeenRaw.isNotEmpty) {
        lastSeen = DateTime.tryParse(lastSeenRaw);
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
      final from = data['from']?.toString().trim() ?? '';

      final to = data['to']?.toString().trim() ?? '';

      final isTyping = data['isTyping'] == true;

      final belongsToThisChat = from == widget.targetUser && to == currentUser;

      if (!belongsToThisChat) {
        return;
      }

      _setContactTyping(isTyping);

      return;
    }

    if (type == 'pinned_message_updated') {
      final peer = data['peer']?.toString().trim() ?? '';
      final messageId = data['messageId']?.toString().trim() ?? '';
      final pinned = data['pinned'] == true;

      if (peer != widget.targetUser || messageId.isEmpty || !mounted) {
        return;
      }

      var changed = false;
      setState(() {
        for (final message in _messages) {
          if (_getMessageId(message) != messageId) {
            continue;
          }
          if (_isMessagePinned(message) != pinned) {
            message['isPinned'] = pinned;
            changed = true;
          }
          break;
        }
      });

      if (changed) {
        _saveMessages();
      }
      return;
    }

    if (type == 'message_edited') {
      final messageId = data['messageId']?.toString().trim() ?? '';

      final from = data['from']?.toString().trim() ?? '';

      final to = data['to']?.toString().trim() ?? '';

      final newText = data['newText']?.toString().trim() ?? '';

      final editedAt =
          data['editedAt']?.toString().trim() ??
          DateTime.now().toIso8601String();

      final belongsToThisChat =
          (from == widget.targetUser && to == currentUser) ||
          (from == currentUser && to == widget.targetUser);

      if (!belongsToThisChat || messageId.isEmpty || newText.isEmpty) {
        return;
      }

      var changed = false;

      if (mounted) {
        setState(() {
          for (final message in _messages) {
            final id = message['id']?.toString().trim() ?? '';

            if (id == messageId) {
              message['text'] = newText;
              message['isEdited'] = true;
              message['editedAt'] = editedAt;
              changed = true;
            }

            final rawReply = message['replyTo'];

            if (rawReply is Map &&
                rawReply['id']?.toString().trim() == messageId) {
              final reply = Map<String, dynamic>.from(rawReply);

              reply['text'] = newText;
              message['replyTo'] = reply;
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

    if (type == 'message_deleted') {
      final currentUser = SocketService.instance.currentUser ?? '';

      final messageId = data['messageId']?.toString().trim() ?? '';

      final from = data['from']?.toString().trim() ?? '';

      final to = data['to']?.toString().trim() ?? '';

      if (currentUser.isEmpty || messageId.isEmpty) {
        return;
      }

      final belongsToThisChat =
          (from == currentUser && to == widget.targetUser) ||
          (from == widget.targetUser && to == currentUser);

      if (!belongsToThisChat) {
        return;
      }

      final replyId = _replyToMessage == null
          ? ''
          : _getMessageId(_replyToMessage!);

      var changed = false;

      if (!mounted) {
        return;
      }

      setState(() {
        final before = _messages.length;

        _messages.removeWhere((message) => _getMessageId(message) == messageId);

        if (_messages.length != before) {
          changed = true;
        }

        for (final message in _messages) {
          final rawReply = message['replyTo'];

          if (rawReply is Map &&
              rawReply['id']?.toString().trim() == messageId) {
            message.remove('replyTo');
            changed = true;
          }
        }

        if (replyId == messageId) {
          _replyToMessage = null;
          changed = true;
        }
      });

      if (changed) {
        _saveMessages();
      }

      if (from == currentUser && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '\u0421\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u0435 \u0443\u0434\u0430\u043B\u0435\u043D\u043E \u0431\u0435\u0437 \u0441\u043B\u0435\u0434\u043E\u0432',
            ),
            backgroundColor: FenyvoPalette.surface,
            duration: Duration(milliseconds: 1100),
          ),
        );
      }

      return;
    }

    if (type == 'message') {
      final id = data['id']?.toString().trim() ?? '';

      final from = data['from']?.toString() ?? '';

      final to = data['to']?.toString() ?? '';

      final text = data['text']?.toString() ?? '';

      final time = data['time']?.toString() ?? DateTime.now().toIso8601String();

      final belongsToThisChat =
          (from == widget.targetUser && to == currentUser) ||
          (from == currentUser && to == widget.targetUser);

      if (!belongsToThisChat) {
        return;
      }

      if (_contactBlocked && from == widget.targetUser) {
        return;
      }

      if (from == widget.targetUser) {
        _setContactTyping(false);
      }

      if (data['e2ee'] == true) {
        unawaited(_refreshE2eeVerification(showChangedWarning: true));
      }

      _addMessageIfNotExists({
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
        if (data['e2eeMedia'] is Map)
          'e2eeMedia': Map<String, dynamic>.from(data['e2eeMedia'] as Map),
        'isMe': from == currentUser,
        'time': time,
        'reactionUsers': <String>[],
        'readByMe': from == widget.targetUser && to == currentUser,
        if (data['e2ee'] == true) 'e2ee': true,
        if (data['e2eeError'] == true) 'e2eeError': true,
        if (data['replyTo'] is Map)
          'replyTo': Map<String, dynamic>.from(data['replyTo'] as Map),
        if (data['forwardedFrom'] != null)
          'forwardedFrom': data['forwardedFrom'].toString(),
        if (data['forwardComment'] != null)
          'forwardComment': data['forwardComment'].toString(),
        if (data['isEdited'] == true) 'isEdited': true,
        if (data['editedAt'] != null) 'editedAt': data['editedAt'].toString(),
      });

      if (from == widget.targetUser && to == currentUser && id.isNotEmpty) {
        SocketService.instance.sendMessageRead(
          messageId: id,
          from: from,
          to: to,
        );
      }

      return;
    }

    if (type == 'outbox_queued' ||
        type == 'outbox_sending' ||
        type == 'outbox_failed') {
      final id = data['id']?.toString().trim() ?? '';
      final to = data['to']?.toString().trim() ?? '';
      if (id.isEmpty || to != widget.targetUser) return;
      final status = type == 'outbox_queued'
          ? 'queued'
          : type == 'outbox_failed'
          ? 'failed'
          : 'sending';
      _addMessageIfNotExists({
        'id': id,
        'from': currentUser,
        'to': to,
        'text': data['text']?.toString() ?? '',
        'time': data['time']?.toString() ?? DateTime.now().toIso8601String(),
        'isMe': true,
        'status': status,
        'reactionUsers': <String>[],
        if (data['e2ee'] == true) 'e2ee': true,
        if (data['messageType'] != null)
          'messageType': data['messageType'].toString(),
        if (data['mediaId'] != null) 'mediaId': data['mediaId'].toString(),
        if (data['fileName'] != null) 'fileName': data['fileName'].toString(),
        if (data['fileSize'] != null) 'fileSize': data['fileSize'],
        if (data['mimeType'] != null) 'mimeType': data['mimeType'].toString(),
        if (data['voiceDurationMs'] != null)
          'voiceDurationMs': data['voiceDurationMs'],
        if (data['voiceMimeType'] != null)
          'voiceMimeType': data['voiceMimeType'].toString(),
        if (data['e2eeMedia'] is Map)
          'e2eeMedia': Map<String, dynamic>.from(data['e2eeMedia'] as Map),
        if (data['replyTo'] is Map)
          'replyTo': Map<String, dynamic>.from(data['replyTo'] as Map),
        if (data['forwardedFrom'] != null)
          'forwardedFrom': data['forwardedFrom'].toString(),
        if (data['forwardComment'] != null)
          'forwardComment': data['forwardComment'].toString(),
      });
      _updateMessageStatus(id, status);
      if (type == 'outbox_failed') {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['reason']?.toString() ??
                  'Защищённое сообщение не отправлено',
            ),
          ),
        );
      }
      return;
    }

    if (type == 'message_sent') {
      final id = data['id']?.toString().trim() ?? '';

      final from = data['from']?.toString() ?? '';

      final to = data['to']?.toString() ?? '';

      final text = data['text']?.toString() ?? '';

      final time = data['time']?.toString() ?? DateTime.now().toIso8601String();

      if (from != currentUser || to != widget.targetUser) {
        return;
      }

      // Подтверждение сервера переводит локально queued/sending в sent.
      _updateMessageStatus(id, 'sent');
      _syncConfirmedMessageTime(id, time);

      _addMessageIfNotExists({
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
        if (data['e2eeMedia'] is Map)
          'e2eeMedia': Map<String, dynamic>.from(data['e2eeMedia'] as Map),
        'isMe': true,
        'time': time,
        'status': 'sent',
        'reactionUsers': <String>[],
        if (data['e2ee'] == true) 'e2ee': true,
        if (data['replyTo'] is Map)
          'replyTo': Map<String, dynamic>.from(data['replyTo'] as Map),
        if (data['forwardedFrom'] != null)
          'forwardedFrom': data['forwardedFrom'].toString(),
        if (data['forwardComment'] != null)
          'forwardComment': data['forwardComment'].toString(),
        if (data['isEdited'] == true) 'isEdited': true,
        if (data['editedAt'] != null) 'editedAt': data['editedAt'].toString(),
      });

      return;
    }

    if (type == 'message_delivered') {
      final messageId = data['messageId']?.toString().trim() ?? '';

      final from = data['from']?.toString().trim() ?? '';

      final to = data['to']?.toString().trim() ?? '';

      if (messageId.isEmpty || from != currentUser || to != widget.targetUser) {
        return;
      }

      _updateMessageStatus(messageId, 'delivered');

      return;
    }

    if (type == 'message_read') {
      final messageId = data['messageId']?.toString().trim() ?? '';

      final from = data['from']?.toString().trim() ?? '';

      final to = data['to']?.toString().trim() ?? '';

      if (messageId.isEmpty || from != currentUser || to != widget.targetUser) {
        return;
      }

      _updateMessageStatus(messageId, 'read');

      return;
    }

    if (type == 'reaction_update') {
      final messageId = data['messageId']?.toString().trim() ?? '';
      final from = data['from']?.toString().trim() ?? '';
      final to = data['to']?.toString().trim() ?? '';

      if (messageId.isEmpty) {
        return;
      }

      final belongsToThisChat =
          (from == currentUser && to == widget.targetUser) ||
          (from == widget.targetUser && to == currentUser);

      if (!belongsToThisChat) {
        return;
      }

      final reactions = <String, String>{};
      final rawReactions = data['reactions'];

      if (rawReactions is Map) {
        rawReactions.forEach((rawUser, rawReaction) {
          final user = rawUser.toString().trim();
          final reaction = rawReaction.toString().trim();
          if (user.isEmpty || !_supportedReactions.contains(reaction)) {
            return;
          }
          reactions[user] = reaction;
        });
      } else {
        final legacyUsers = data['users'];
        if (legacyUsers is List) {
          for (final rawUser in legacyUsers) {
            final user = rawUser.toString().trim();
            if (user.isNotEmpty) {
              reactions[user] = '\u2764\uFE0F';
            }
          }
        }
      }

      final messageIndex = _messages.indexWhere(
        (message) => _getMessageId(message) == messageId,
      );

      if (messageIndex == -1 || !mounted) {
        return;
      }

      final reaction = data['reaction']?.toString().trim() ?? '';
      final reactionAdded = data['reactionAdded'] == true;
      final changedBy = data['changedBy']?.toString().trim() ?? '';

      setState(() {
        _messages[messageIndex]['reactions'] = reactions;
        _messages[messageIndex].remove('reactionUsers');
        _messages[messageIndex].remove('reaction');
      });

      _saveMessages();

      if (reactionAdded && _supportedReactions.contains(reaction)) {
        _showReactionBurst(reaction);

        if (changedBy.isNotEmpty && changedBy != currentUser) {
          unawaited(_jumpToPinnedMessage(_messages[messageIndex]));
        }
      }

      return;
    }
  }

  // ========================================
  // \u0414\u041E\u0411\u0410\u0412\u041B\u0415\u041D\u0418\u0415 \u0421\u041E\u041E\u0411\u0429\u0415\u041D\u0418\u042F \u0411\u0415\u0417 \u0414\u0423\u0411\u041B\u0415\u0419
  // ========================================

  void _addMessageIfNotExists(Map<String, dynamic> newMessage) {
    _normalizeReactionUsers(newMessage);

    final exists = _messages.any(
      (message) => isSameStoredMessage(message, newMessage),
    );

    if (exists) {
      return;
    }

    if (!mounted) {
      return;
    }

    final isIncomingMessage = newMessage['isMe'] != true;

    final shouldCountAsNew =
        Platform.isWindows && isIncomingMessage && _showScrollToLatest;

    setState(() {
      _messages.add(newMessage);
      _sortMessagesChronologically();

      if (shouldCountAsNew) {
        _newMessagesWhileScrolledUp++;
      }
    });

    _saveMessages();
    _clearUnread();
  }

  void _focusMessageComposer() {
    if (_searchMode || _searchFocusNode.hasFocus) return;
    if (!Platform.isWindows || !mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          !_messageFocusNode.canRequestFocus ||
          _searchMode ||
          _searchFocusNode.hasFocus) {
        return;
      }

      _messageFocusNode.requestFocus();
    });
  }

  // ========================================
  // V618 — МЕДИА В ЛИЧНОМ ЧАТЕ
  // ========================================

  String _privateMessageType(Map<String, dynamic> message) {
    final type = message['messageType']?.toString().trim().toLowerCase() ?? '';
    return type.isEmpty ? 'text' : type;
  }

  Uint8List? _privateMediaBytes(Map<String, dynamic> message) {
    return MediaCacheService.readBytesSync(message);
  }

  String? _privateMediaPath(Map<String, dynamic> message) {
    return MediaCacheService.existingLocalPath(message);
  }

  String _privateBasename(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.isEmpty ? path : parts.last;
  }

  String _privateSafeFileName(String name) {
    final clean = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    return clean.isEmpty
        ? 'spartan_${DateTime.now().millisecondsSinceEpoch}.bin'
        : clean;
  }

  String _privateMimeFromName(String name, String fallback) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt')) return 'text/plain';
    return fallback;
  }

  String _privateHumanSize(dynamic raw) {
    final bytes = raw is num
        ? raw.toInt()
        : int.tryParse(raw?.toString() ?? '') ?? 0;
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes Б';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} КБ';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} МБ';
  }

  void _privateMediaSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: FenyvoPalette.surface),
    );
  }

  Future<void> _showPrivateAttachmentMenu() async {
    if (_sendingPrivateMedia || _isRecordingVoice) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: FenyvoPalette.surface,
      showDragHandle: true,
      builder: (sheetContext) {
        Widget item(
          IconData icon,
          String title,
          Future<void> Function() action,
        ) {
          return ListTile(
            leading: Icon(icon, color: _gold),
            title: Text(
              title,
              style: const TextStyle(
                color: FenyvoPalette.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: () {
              Navigator.of(sheetContext).pop();
              Future<void>.delayed(const Duration(milliseconds: 80), () {
                if (mounted) unawaited(action());
              });
            },
          );
        }

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              item(
                Icons.photo_library_outlined,
                _chatText('photo'),
                _pickPrivateImage,
              ),
              item(
                Icons.video_library_outlined,
                _chatText('video'),
                _pickPrivateVideo,
              ),
              item(
                Icons.attach_file_rounded,
                _chatText('file'),
                _pickPrivateFile,
              ),
              item(
                Icons.person_outline_rounded,
                'Контакт',
                _showShareContactPicker,
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showShareContactPicker() async {
    if (_sendingPrivateMedia || _isRecordingVoice) return;

    final completer = Completer<List<String>>();
    _registeredUsersCompleter = completer;
    SocketService.instance.getRegisteredUsers();

    List<String> users = _registeredUsers;
    try {
      users = await completer.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      users = _registeredUsers;
    } finally {
      if (identical(_registeredUsersCompleter, completer)) {
        _registeredUsersCompleter = null;
      }
    }

    if (!mounted) return;
    if (users.isEmpty) {
      _privateMediaSnack('Контакты не найдены');
      return;
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: FenyvoPalette.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * .65,
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(
                  'Поделиться контактом',
                  style: TextStyle(
                    color: FenyvoPalette.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(user.substring(0, 1).toUpperCase()),
                      ),
                      title: Text(
                        user,
                        style: const TextStyle(
                          color: FenyvoPalette.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '@$user',
                        style: const TextStyle(color: FenyvoPalette.secondary),
                      ),
                      trailing: Icon(Icons.send_rounded, color: _gold),
                      onTap: () => Navigator.of(sheetContext).pop(user),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || selected == null || selected.trim().isEmpty) return;

    final username = selected.trim();
    SocketService.instance.sendMessage(
      widget.targetUser,
      'Контакт: @$username',
      sharedContact: <String, dynamic>{'username': username, 'name': username},
    );
  }

  Future<void> _pickPrivateImage() async {
    try {
      if (Platform.isWindows) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.image,
          allowMultiple: false,
          withData: false,
        );
        if (result == null || result.files.isEmpty) return;
        final picked = result.files.single;
        final path = picked.path?.trim() ?? '';
        if (path.isEmpty) {
          _privateMediaSnack(_chatText('photoPathError'));
          return;
        }
        await _sendPrivateMediaFile(
          messageType: 'image',
          path: path,
          fileName: picked.name,
          mimeType: _privateMimeFromName(picked.name, 'image/jpeg'),
          text: '📷 ${_chatText('photo')}',
          maxBytes: 20 * 1024 * 1024,
        );
        return;
      }

      final picked = await _privateImagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
      );
      if (picked == null) return;
      await _sendPrivateMediaFile(
        messageType: 'image',
        path: picked.path,
        fileName: _privateBasename(picked.path),
        mimeType: _privateMimeFromName(picked.path, 'image/jpeg'),
        text: '📷 ${_chatText('photo')}',
        maxBytes: 20 * 1024 * 1024,
      );
    } catch (error) {
      _privateMediaSnack(_chatText('photoPickError', {'error': error}));
    }
  }

  Future<void> _pickPrivateVideo() async {
    try {
      if (Platform.isWindows) {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.video,
          allowMultiple: false,
          withData: false,
        );
        if (result == null || result.files.isEmpty) return;
        final picked = result.files.single;
        final path = picked.path?.trim() ?? '';
        if (path.isEmpty) {
          _privateMediaSnack(_chatText('videoPathError'));
          return;
        }
        await _sendPrivateMediaFile(
          messageType: 'video',
          path: path,
          fileName: picked.name,
          mimeType: _privateMimeFromName(picked.name, 'video/mp4'),
          text: '🎥 ${_chatText('video')}',
          maxBytes: 1024 * 1024 * 1024,
        );
        return;
      }

      final picked = await _privateImagePicker.pickVideo(
        source: ImageSource.gallery,
      );
      if (picked == null) return;
      await _sendPrivateMediaFile(
        messageType: 'video',
        path: picked.path,
        fileName: _privateBasename(picked.path),
        mimeType: _privateMimeFromName(picked.path, 'video/mp4'),
        text: '🎥 ${_chatText('video')}',
        maxBytes: 1024 * 1024 * 1024,
      );
    } catch (error) {
      _privateMediaSnack(_chatText('videoPickError', {'error': error}));
    }
  }

  Future<void> _pickPrivateFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      final path = picked.path?.trim() ?? '';
      if (path.isEmpty) {
        _privateMediaSnack(_chatText('filePathError'));
        return;
      }
      final name = picked.name.trim().isEmpty ? 'file.bin' : picked.name.trim();
      final mime = _privateMimeFromName(name, 'application/octet-stream');
      final isVideo = mime.startsWith('video/');
      await _sendPrivateMediaFile(
        messageType: isVideo ? 'video' : 'file',
        path: path,
        fileName: name,
        mimeType: mime,
        text: isVideo ? '🎥 ${_chatText('video')}' : '📎 $name',
        maxBytes: isVideo ? 1024 * 1024 * 1024 : 512 * 1024 * 1024,
      );
    } catch (error) {
      _privateMediaSnack(_chatText('filePickError', {'error': error}));
    }
  }

  Future<void> _sendPrivateMediaFile({
    required String messageType,
    required String path,
    required String fileName,
    required String mimeType,
    required String text,
    required int maxBytes,
  }) async {
    if (!SocketService.instance.isConnected) {
      _privateMediaSnack(_chatText('noServerConnection'));
      return;
    }
    if (!MediaTransferService.isReady) {
      _privateMediaSnack(_chatText('mediaServerNotReady'));
      return;
    }
    if (mounted) setState(() => _sendingPrivateMedia = true);
    try {
      final protectWithE2ee = SocketService.instance.isE2eeActiveWith(
        widget.targetUser,
      );
      final upload = await MediaTransferService.uploadFile(
        path: path,
        fileName: _privateSafeFileName(fileName),
        mimeType: mimeType,
        messageType: messageType,
        maxBytes: maxBytes,
        encryptForE2ee: protectWithE2ee,
      );
      SocketService.instance.sendMediaMessage(
        widget.targetUser,
        messageType: messageType,
        mediaId: upload.mediaId,
        fileName: upload.fileName,
        fileSize: upload.fileSize,
        mimeType: upload.mimeType,
        text: text,
        replyTo: _currentReplyPayload(),
        e2eeMedia: upload.e2eeMedia,
      );
      if (_replyToMessage != null && mounted) {
        setState(() => _replyToMessage = null);
      }
    } catch (error) {
      _privateMediaSnack(_chatText('fileSendError', {'error': error}));
    } finally {
      if (mounted) setState(() => _sendingPrivateMedia = false);
    }
  }

  String _privateAttachmentName(Map<String, dynamic> message) {
    final name = message['fileName']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;
    switch (_privateMessageType(message)) {
      case 'image':
        return 'photo.jpg';
      case 'video':
        return 'video.mp4';
      default:
        return 'file.bin';
    }
  }

  Future<void> _savePrivateAttachment(Map<String, dynamic> message) async {
    final bytes = await MediaCacheService.readBytes(message);
    if (bytes == null || bytes.isEmpty) {
      _privateMediaSnack(_chatText('attachmentDamaged'));
      return;
    }

    final original = _privateSafeFileName(_privateAttachmentName(message));
    final mime =
        message['mimeType']?.toString().trim() ??
        message['voiceMimeType']?.toString().trim() ??
        _privateMimeFromName(original, 'application/octet-stream');

    try {
      final savedPath = await FenyvoDownloadService.saveBytes(
        bytes: bytes,
        fileName: original,
        mimeType: mime,
      );
      _privateMediaSnack(_chatText('savedToFenyvo', {'path': savedPath}));
    } catch (error) {
      _privateMediaSnack(_chatText('fileSaveError', {'error': error}));
    }
  }

  Future<void> _openPrivateImage(Map<String, dynamic> source) async {
    var message = Map<String, dynamic>.from(source);
    var path = _privateMediaPath(message);
    var bytes = path == null ? _privateMediaBytes(message) : null;
    var networkUrl = MediaCacheService.remoteUrl(message);

    // Protected media on the server is ciphertext and must never be passed to
    // Image.network. Download and authenticate/decrypt it on this device first.
    if (path == null &&
        (bytes == null || bytes.isEmpty) &&
        networkUrl != null &&
        MediaCacheService.e2eeMediaMetadata(message) != null) {
      try {
        message = await MediaCacheService.cacheRemoteMedia(message);
        path = _privateMediaPath(message);
        bytes = path == null ? _privateMediaBytes(message) : null;
        networkUrl = null;
      } catch (error) {
        if (mounted) {
          _privateMediaSnack(_chatText('fileSaveError', {'error': error}));
        }
        return;
      }
    }

    if (!mounted) return;
    if (path == null &&
        (bytes == null || bytes.isEmpty) &&
        networkUrl == null) {
      _privateMediaSnack(_chatText('photoDamaged'));
      return;
    }

    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          backgroundColor: Colors.black,
          child: Stack(
            children: [
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 5,
                  child: Center(
                    child: path != null
                        ? Image.file(
                            File(path),
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          )
                        : bytes != null && bytes.isNotEmpty
                        ? Image.memory(
                            bytes,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          )
                        : Image.network(
                            networkUrl!,
                            headers: MediaCacheService.remoteHeaders,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                          ),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.filled(
                      tooltip: _chatText('download'),
                      onPressed: () =>
                          unawaited(_savePrivateAttachment(message)),
                      icon: const Icon(Icons.download_rounded),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      tooltip: _chatText('close'),
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPrivateMediaBody(
    Map<String, dynamic> message, {
    required bool isMe,
  }) {
    final type = _privateMessageType(message);
    final path = _privateMediaPath(message);
    final bytes = path == null ? _privateMediaBytes(message) : null;
    final networkUrl = MediaCacheService.remoteUrl(message);

    if (type == 'image') {
      if (path == null &&
          (bytes == null || bytes.isEmpty) &&
          networkUrl == null) {
        return Text(
          '📷 ${_chatText('photoUnavailable')}',
          style: TextStyle(
            color: isMe ? FenyvoPalette.ink : FenyvoPalette.ink,
          ),
        );
      }
      return Stack(
        children: [
          GestureDetector(
            onTap: () => unawaited(_openPrivateImage(message)),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minWidth: 150,
                  maxWidth: 340,
                  maxHeight: 330,
                ),
                child:
                    path == null &&
                        (bytes == null || bytes.isEmpty) &&
                        networkUrl != null &&
                        MediaCacheService.e2eeMediaMetadata(message) != null
                    ? FutureBuilder<Map<String, dynamic>>(
                        future: MediaCacheService.cacheRemoteMedia(message),
                        builder: (context, snapshot) {
                          final decryptedPath = snapshot.hasData
                              ? MediaCacheService.existingLocalPath(
                                  snapshot.data!,
                                )
                              : null;
                          if (decryptedPath != null) {
                            return Image.file(
                              File(decryptedPath),
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (_, __, ___) => const SizedBox(
                                width: 220,
                                height: 120,
                                child: Center(
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    size: 42,
                                  ),
                                ),
                              ),
                            );
                          }
                          if (snapshot.hasError) {
                            return const SizedBox(
                              width: 220,
                              height: 120,
                              child: Center(
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  size: 42,
                                ),
                              ),
                            );
                          }
                          return const SizedBox(
                            width: 220,
                            height: 120,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        },
                      )
                    : path != null
                    ? Image.file(
                        File(path),
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 220,
                          height: 120,
                          child: Center(
                            child: Icon(Icons.broken_image_outlined, size: 42),
                          ),
                        ),
                      )
                    : bytes != null && bytes.isNotEmpty
                    ? Image.memory(
                        bytes,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 220,
                          height: 120,
                          child: Center(
                            child: Icon(Icons.broken_image_outlined, size: 42),
                          ),
                        ),
                      )
                    : Image.network(
                        networkUrl!,
                        headers: MediaCacheService.remoteHeaders,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                        errorBuilder: (_, __, ___) => const SizedBox(
                          width: 220,
                          height: 120,
                          child: Center(
                            child: Icon(Icons.broken_image_outlined, size: 42),
                          ),
                        ),
                      ),
              ),
            ),
          ),
          Positioned(
            right: 6,
            top: 6,
            child: Material(
              color: FenyvoPalette.surface.withValues(alpha: 0.68),
              shape: const CircleBorder(),
              child: IconButton(
                tooltip: _chatText('download'),
                visualDensity: VisualDensity.compact,
                onPressed: () => unawaited(_savePrivateAttachment(message)),
                icon: const Icon(
                  Icons.download_rounded,
                  color: FenyvoPalette.ink,
                  size: 21,
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (type == 'video') {
      if (path == null &&
          (bytes == null || bytes.isEmpty) &&
          networkUrl == null) {
        return Text(
          '🎥 ${_chatText('videoUnavailable')}',
          style: TextStyle(
            color: isMe ? FenyvoPalette.ink : FenyvoPalette.ink,
          ),
        );
      }
      return _InlinePrivateVideo(
        key: ValueKey<String>('private_video_${_getMessageId(message)}'),
        bytes: bytes,
        filePath: path,
        fileName: _privateAttachmentName(message),
        networkUrl: networkUrl,
        httpHeaders: MediaCacheService.remoteHeaders,
        mediaMessage: Map<String, dynamic>.from(message),
        isMe: isMe,
        gold: FenyvoPalette.mediaAccent,
        onDownload: () => unawaited(_savePrivateAttachment(message)),
      );
    }

    final name = _privateAttachmentName(message);
    final size = _privateHumanSize(message['fileSize']);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => unawaited(_savePrivateAttachment(message)),
      child: Container(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 330),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: FenyvoPalette.surface.withValues(alpha: isMe ? 0.08 : 0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              color: isMe ? FenyvoPalette.ink : _gold,
              size: 30,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isMe ? FenyvoPalette.ink : FenyvoPalette.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (size.isNotEmpty)
                    Text(
                      size,
                      style: TextStyle(
                        color: isMe
                            ? FenyvoPalette.secondary
                            : FenyvoPalette.secondary,
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.download_rounded,
              color: isMe ? FenyvoPalette.secondary : FenyvoPalette.secondary,
            ),
          ],
        ),
      ),
    );
  }

  // ========================================
  // V617 — УЛУЧШЕННЫЕ ГОЛОСОВЫЕ
  // ========================================

  bool _isVoiceMessage(Map<String, dynamic> message) {
    final isVoice = message['messageType']?.toString().trim() == 'voice';
    if (!isVoice) return false;
    if (MediaCacheService.existingLocalPath(message) != null) return true;
    if (MediaCacheService.hasRemoteMedia(message)) return true;
    return message['voiceData']?.toString().trim().isNotEmpty ?? false;
  }

  String _formatVoiceDuration(Duration duration) {
    final seconds = duration.inSeconds.clamp(0, 359999);

    final minutes = seconds ~/ 60;

    final rest = seconds % 60;

    return '${minutes.toString().padLeft(1, '0')}:'
        '${rest.toString().padLeft(2, '0')}';
  }

  int _voiceDurationMs(Map<String, dynamic> message) {
    final raw = message['voiceDurationMs'];

    if (raw is int) {
      return raw;
    }

    if (raw is num) {
      return raw.toInt();
    }

    return int.tryParse(raw?.toString() ?? '') ?? 0;
  }

  Map<String, dynamic>? _currentReplyPayload() {
    final selectedReply = _replyToMessage;

    if (selectedReply == null) {
      return null;
    }

    final replyId = _getMessageId(selectedReply);

    final replyFrom = selectedReply['from']?.toString().trim() ?? '';

    final replyText = selectedReply['text']?.toString().trim() ?? '';

    if (replyId.isEmpty || replyFrom.isEmpty || replyText.isEmpty) {
      return null;
    }

    return {'id': replyId, 'from': replyFrom, 'text': replyText};
  }

  Future<void> _startVoiceRecording() async {
    if (_voiceStarting || _isRecordingVoice) {
      return;
    }

    if (!SocketService.instance.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '\u041d\u0435\u0442 \u043f\u043e\u0434\u043a\u043b\u044e\u0447\u0435\u043d\u0438\u044f \u043a \u0441\u0435\u0440\u0432\u0435\u0440\u0443',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }

      return;
    }

    _voiceStarting = true;

    try {
      final allowed = await _voiceRecorder.hasPermission();

      if (!mounted || !_voicePressActive) {
        return;
      }

      if (!allowed) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '\u041d\u0443\u0436\u0435\u043d \u0434\u043e\u0441\u0442\u0443\u043f \u043a \u043c\u0438\u043a\u0440\u043e\u0444\u043e\u043d\u0443',
            ),
            backgroundColor: Colors.red,
          ),
        );

        return;
      }

      final tempDirectory = await getTemporaryDirectory();

      final voiceDirectory = Directory(
        '${tempDirectory.path}${Platform.pathSeparator}spartan_voice',
      );

      if (!voiceDirectory.existsSync()) {
        await voiceDirectory.create(recursive: true);
      }

      final path =
          '${voiceDirectory.path}${Platform.pathSeparator}'
          'voice_${DateTime.now().microsecondsSinceEpoch}.m4a';

      await _voiceRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: path,
      );

      if (!mounted || !_voicePressActive) {
        final stoppedPath = await _voiceRecorder.stop();

        final abandonedPath = stoppedPath ?? path;

        final abandonedFile = File(abandonedPath);

        if (await abandonedFile.exists()) {
          await abandonedFile.delete();
        }

        return;
      }

      _stopTyping();

      setState(() {
        _isRecordingVoice = true;
        // FIX6: once recording is visible, it is always in explicit-control
        // mode. Releasing the finger must never be required to finish it.
        _voiceRecordingLocked = true;
        _voiceRecordDuration = Duration.zero;
        _voiceRecordingPath = path;
      });

      _voiceRecordTimer?.cancel();

      _voiceRecordTimer = Timer.periodic(const Duration(milliseconds: 250), (
        _,
      ) {
        if (!mounted || !_isRecordingVoice) {
          return;
        }

        final next = _voiceRecordDuration + const Duration(milliseconds: 250);

        setState(() {
          _voiceRecordDuration = next;
        });

        if (next >= const Duration(minutes: 5)) {
          unawaited(_finishVoiceRecording(send: true));
        }
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u043d\u0430\u0447\u0430\u0442\u044c \u0437\u0430\u043f\u0438\u0441\u044c: $error',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _voiceStarting = false;
    }
  }

  Future<void> _finishVoiceRecording({required bool send}) async {
    if (!_isRecordingVoice) {
      return;
    }

    _voiceRecordTimer?.cancel();
    _voiceRecordTimer = null;

    final duration = _voiceRecordDuration;

    final fallbackPath = _voiceRecordingPath;

    // IMPORTANT: release the recording UI immediately. Previously the
    // long-press widget could disappear while the pointer was still down,
    // leaving the recorder active with no usable controls.
    _voicePressActive = false;

    if (mounted) {
      setState(() {
        _isRecordingVoice = false;
        _voiceRecordingLocked = false;
        _voiceRecordDuration = Duration.zero;
        _voiceRecordingPath = null;
        _voiceDragStart = null;
      });
    } else {
      _isRecordingVoice = false;
      _voiceRecordingLocked = false;
      _voiceRecordDuration = Duration.zero;
      _voiceRecordingPath = null;
      _voiceDragStart = null;
    }

    String? stoppedPath;

    try {
      stoppedPath = await _voiceRecorder.stop();
    } catch (_) {
      stoppedPath = fallbackPath;
    }

    final path = stoppedPath ?? fallbackPath;

    if (path == null || path.isEmpty) {
      return;
    }

    final file = File(path);

    if (!send || duration < const Duration(milliseconds: 650)) {
      if (await file.exists()) {
        await file.delete();
      }

      return;
    }

    if (!SocketService.instance.isConnected) {
      if (await file.exists()) {
        await file.delete();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '\u0413\u043e\u043b\u043e\u0441\u043e\u0432\u043e\u0435 \u043d\u0435 \u043e\u0442\u043f\u0440\u0430\u0432\u043b\u0435\u043d\u043e: \u043d\u0435\u0442 \u0441\u0432\u044f\u0437\u0438',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }

      return;
    }

    try {
      final fileSize = await file.length();
      if (fileSize > 20 * 1024 * 1024) {
        _privateMediaSnack('Голосовое слишком большое');
        return;
      }

      final protectWithE2ee = SocketService.instance.isE2eeActiveWith(
        widget.targetUser,
      );
      final upload = await MediaTransferService.uploadFile(
        path: file.path,
        fileName: _privateBasename(file.path),
        mimeType: 'audio/mp4',
        messageType: 'voice',
        maxBytes: 20 * 1024 * 1024,
        encryptForE2ee: protectWithE2ee,
      );

      SocketService.instance.sendVoiceMessage(
        widget.targetUser,
        mediaId: upload.mediaId,
        fileName: upload.fileName,
        fileSize: upload.fileSize,
        mimeType: upload.mimeType,
        durationMs: duration.inMilliseconds,
        replyTo: _currentReplyPayload(),
        e2eeMedia: upload.e2eeMedia,
      );

      if (_replyToMessage != null && mounted) {
        setState(() {
          _replyToMessage = null;
        });
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '\u041e\u0448\u0438\u0431\u043a\u0430 \u043e\u0442\u043f\u0440\u0430\u0432\u043a\u0438 \u0433\u043e\u043b\u043e\u0441\u043e\u0432\u043e\u0433\u043e: $error',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (await file.exists()) {
        await file.delete();
      }
    }
  }

  void _handleVoiceLongPressStart(LongPressStartDetails details) {
    if (_voiceStarting || _isRecordingVoice) {
      return;
    }

    _voiceDragStart = details.globalPosition;

    // FIX5: a long press now enters the same locked recording mode as a
    // normal tap. This leaves the recording composer on screen with explicit
    // Cancel and Send buttons instead of depending on a release/swipe gesture.
    unawaited(_startLockedVoiceRecording());
  }

  void _handleVoiceDragPosition(Offset globalPosition) {
    final start = _voiceDragStart;

    if (!_voicePressActive ||
        start == null ||
        !_isRecordingVoice ||
        _voiceRecordingLocked) {
      return;
    }

    final delta = globalPosition - start;

    if (delta.dx <= -105) {
      _voicePressActive = false;

      unawaited(_finishVoiceRecording(send: false));

      return;
    }

    if (delta.dy <= -90) {
      _voicePressActive = false;

      setState(() {
        _voiceRecordingLocked = true;
      });
    }
  }

  void _handleVoiceLongPressMove(LongPressMoveUpdateDetails details) {
    _handleVoiceDragPosition(details.globalPosition);
  }

  void _finishVoicePointerGesture({required bool send}) {
    // FIX6: pointer-up/cancel no longer stops a recording. Recording is
    // controlled only by the visible Cancel and Send buttons. Keeping this
    // bridge as a no-op avoids gesture races during a long press.
    if (send) {
      return;
    }
  }

  void _handleVoiceLongPressEnd(LongPressEndDetails details) {
    _finishVoicePointerGesture(send: true);
  }

  Widget _withVoicePointerBridge(Widget child) {
    if (Platform.isWindows) {
      return child;
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerMove: (event) {
        _handleVoiceDragPosition(event.position);
      },
      onPointerUp: (_) {
        _finishVoicePointerGesture(send: true);
      },
      onPointerCancel: (_) {
        _finishVoicePointerGesture(send: false);
      },
      child: child,
    );
  }

  Future<String> _voiceCachePath(Map<String, dynamic> message) async {
    final existing = MediaCacheService.existingLocalPath(message);
    if (existing != null) return existing;

    final cached = MediaCacheService.hasRemoteMedia(message)
        ? await MediaCacheService.cacheRemoteMedia(message)
        : await MediaCacheService.cacheEmbeddedMedia(message);
    final path = MediaCacheService.existingLocalPath(cached);
    if (path == null) {
      throw StateError('Голосовое сообщение недоступно');
    }
    return path;
  }

  Future<void> _toggleVoicePlayback(Map<String, dynamic> message) async {
    final id = _getMessageId(message);

    if (id.isEmpty || !_isVoiceMessage(message)) {
      return;
    }

    if (_playingVoiceMessageId == id) {
      if (_voiceIsPlaying) {
        await _voicePlayer.pause();
      } else {
        await _voicePlayer.resume();
      }

      return;
    }

    try {
      await _voicePlayer.stop();

      final path = await _voiceCachePath(message);

      if (!mounted) {
        return;
      }

      setState(() {
        _playingVoiceMessageId = id;
        _voicePlaybackPosition = Duration.zero;
        _voicePlaybackDuration = Duration(
          milliseconds: _voiceDurationMs(message),
        );
        _voiceIsPlaying = true;
      });

      await _voicePlayer.play(DeviceFileSource(path));

      await _voicePlayer.setPlaybackRate(_voicePlaybackRate);
    } catch (error) {
      if (mounted) {
        setState(() {
          _voiceIsPlaying = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '\u041d\u0435 \u0443\u0434\u0430\u043b\u043e\u0441\u044c \u0432\u043e\u0441\u043f\u0440\u043e\u0438\u0437\u0432\u0435\u0441\u0442\u0438 \u0433\u043e\u043b\u043e\u0441\u043e\u0432\u043e\u0435',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _seekVoiceMessage(
    Map<String, dynamic> message,
    double fraction,
  ) async {
    final id = _getMessageId(message);

    if (_playingVoiceMessageId != id) {
      await _toggleVoicePlayback(message);
    }

    final duration = _voicePlaybackDuration.inMilliseconds > 0
        ? _voicePlaybackDuration
        : Duration(milliseconds: _voiceDurationMs(message));

    if (duration.inMilliseconds <= 0) {
      return;
    }

    final safeFraction = fraction.clamp(0.0, 1.0);

    await _voicePlayer.seek(
      Duration(milliseconds: (duration.inMilliseconds * safeFraction).round()),
    );
  }

  Future<void> _cycleVoicePlaybackRate(Map<String, dynamic> message) async {
    final next = _voicePlaybackRate < 1.25
        ? 1.5
        : _voicePlaybackRate < 1.75
        ? 2.0
        : 1.0;

    if (mounted) {
      setState(() {
        _voicePlaybackRate = next;
      });
    }

    if (_playingVoiceMessageId == _getMessageId(message)) {
      await _voicePlayer.setPlaybackRate(next);
    }
  }

  Widget _buildVoiceMessagePlayer(
    Map<String, dynamic> message, {
    required bool isMe,
  }) {
    final messageId = _getMessageId(message);

    final selected = _playingVoiceMessageId == messageId;

    final rawDuration = Duration(milliseconds: _voiceDurationMs(message));

    final duration = selected && _voicePlaybackDuration.inMilliseconds > 0
        ? _voicePlaybackDuration
        : rawDuration;

    final position = selected ? _voicePlaybackPosition : Duration.zero;

    final progress = duration.inMilliseconds <= 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    final foreground = isMe ? FenyvoPalette.ink : _gold;

    final inactive = isMe
        ? FenyvoPalette.ink.withValues(alpha: 0.24)
        : FenyvoPalette.ink.withValues(alpha: 0.23);

    final secondaryText = isMe
        ? FenyvoPalette.ink.withValues(alpha: 0.58)
        : FenyvoPalette.ink.withValues(alpha: 0.62);

    final waveformSeed = messageId.hashCode.abs();

    const barCount = 36;

    return SizedBox(
      width: 272,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(25),
            onTap: () {
              unawaited(_toggleVoicePlayback(message));
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected && _voiceIsPlaying
                    ? foreground.withValues(alpha: 0.18)
                    : foreground.withValues(alpha: 0.10),
                border: Border.all(
                  color: foreground.withValues(alpha: selected ? 0.88 : 0.55),
                  width: selected ? 1.4 : 1.0,
                ),
              ),
              child: Icon(
                selected && _voiceIsPlaying
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                color: foreground,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 36,
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      void seekAt(double x) {
                        final width = constraints.maxWidth;

                        if (width <= 0) {
                          return;
                        }

                        final fraction = (x / width).clamp(0.0, 1.0);

                        unawaited(_seekVoiceMessage(message, fraction));
                      }

                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapDown: (details) {
                          seekAt(details.localPosition.dx);
                        },
                        onHorizontalDragUpdate: (details) {
                          seekAt(details.localPosition.dx);
                        },
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: List.generate(barCount, (index) {
                            final mixed =
                                (waveformSeed + index * 31 + index * index * 7)
                                    .abs();

                            final height = 7.0 + (mixed % 25).toDouble();

                            final active = ((index + 1) / barCount) <= progress;

                            return Expanded(
                              child: Align(
                                alignment: Alignment.center,
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 90),
                                  curve: Curves.easeOut,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 0.55,
                                  ),
                                  height: height,
                                  decoration: BoxDecoration(
                                    color: active ? foreground : inactive,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      '${_formatVoiceDuration(position)} / ${_formatVoiceDuration(duration)}',
                      style: TextStyle(
                        color: secondaryText,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        unawaited(_cycleVoicePlaybackRate(message));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: foreground.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: foreground.withValues(alpha: 0.34),
                          ),
                        ),
                        child: Text(
                          '${_voicePlaybackRate.toStringAsFixed(_voicePlaybackRate == 1.0 ? 0 : 1)}x',
                          style: TextStyle(
                            color: foreground,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            height: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _startLockedVoiceRecording() async {
    if (_isRecordingVoice) {
      _voicePressActive = false;
      await _finishVoiceRecording(send: true);
      return;
    }

    _voicePressActive = true;

    await _startVoiceRecording();

    if (!mounted) {
      _voicePressActive = false;
      return;
    }

    if (_isRecordingVoice) {
      setState(() {
        _voiceRecordingLocked = true;
      });
    }

    _voicePressActive = false;
  }

  Widget _buildVoiceRecordButton() => Tooltip(
    message: 'Нажмите или удерживайте для записи',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(_startLockedVoiceRecording()),
      onLongPressStart: _handleVoiceLongPressStart,
      onLongPressMoveUpdate: _handleVoiceLongPressMove,
      onLongPressEnd: _handleVoiceLongPressEnd,
      child: Container(
        width: 48,
        height: 48,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: FenyvoPalette.gold,
        ),
        child: const Icon(
          Icons.mic_rounded,
          color: FenyvoPalette.onGold,
          size: 24,
        ),
      ),
    ),
  );

  Widget _buildVoiceRecordingComposer() {
    final tick = _voiceRecordDuration.inMilliseconds ~/ 250;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildComposerReplyPreview(),
        Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: const BoxDecoration(color: FenyvoPalette.surface),
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color(0xFFFF5252),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 48,
                  child: Text(
                    _formatVoiceDuration(_voiceRecordDuration),
                    style: const TextStyle(
                      color: FenyvoPalette.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 34,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: List.generate(18, (index) {
                        final height =
                            7.0 + ((index * 11 + tick * 3) % 24).toDouble();

                        return Expanded(
                          child: Align(
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 140),
                              margin: const EdgeInsets.symmetric(horizontal: 1),
                              height: height,
                              decoration: BoxDecoration(
                                color: FenyvoPalette.blue,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: '\u041e\u0442\u043c\u0435\u043d\u0438\u0442\u044c',
                  onPressed: () {
                    unawaited(_finishVoiceRecording(send: false));
                  },
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFFF6B6B),
                  ),
                ),
                Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [FenyvoPalette.blue, FenyvoPalette.blueDeep],
                    ),
                  ),
                  child: IconButton(
                    tooltip: '\u041e\u0442\u043f\u0440\u0430\u0432\u0438\u0442\u044c',
                    onPressed: () {
                      unawaited(_finishVoiceRecording(send: true));
                    },
                    icon: const Icon(
                      Icons.send_rounded,
                      color: FenyvoPalette.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ========================================
  // \u041E\u0422\u041F\u0420\u0410\u0412\u041A\u0410 \u0421\u041E\u041E\u0411\u0429\u0415\u041D\u0418\u042F
  // ========================================

  void _sendMessage() {
    final text = _messageController.text.trim();

    if (text.isEmpty) {
      return;
    }

    if (_contactBlocked) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_chatText('unblockFirst'))));
      return;
    }

    _stopTyping();

    final wasConnected = SocketService.instance.isConnected;

    Map<String, dynamic>? replyTo;

    final selectedReply = _replyToMessage;

    if (selectedReply != null) {
      final replyId = _getMessageId(selectedReply);

      final replyFrom = selectedReply['from']?.toString().trim() ?? '';

      final replyText = selectedReply['text']?.toString().trim() ?? '';

      if (replyId.isNotEmpty && replyFrom.isNotEmpty && replyText.isNotEmpty) {
        replyTo = {'id': replyId, 'from': replyFrom, 'text': replyText};
      }
    }

    SocketService.instance.sendMessage(
      widget.targetUser,
      text,
      replyTo: replyTo,
    );

    if (!wasConnected && mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_chatText('messageQueued'))));
    }

    _messageController.clear();

    if (mounted) {
      setState(() {
        _replyToMessage = null;
      });
    }

    _focusMessageComposer();
  }

  // ========================================
  // \u041E\u0422\u0412\u0415\u0422 \u041D\u0410 \u0421\u041E\u041E\u0411\u0429\u0415\u041D\u0418\u0415
  // ========================================

  void _startReply(Map<String, dynamic> message) {
    if (!mounted) {
      return;
    }

    setState(() {
      _replyToMessage = Map<String, dynamic>.from(message);
    });

    _focusMessageComposer();
  }

  void _cancelReply() {
    if (_replyToMessage == null || !mounted) {
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
    final replyFrom = replyTo['from']?.toString().trim() ?? '';

    final replyText = replyTo['text']?.toString().trim() ?? '';

    if (replyText.isEmpty) {
      return const SizedBox.shrink();
    }

    final currentUser = SocketService.instance.currentUser ?? '';

    final author = replyFrom == currentUser ? '\u0412\u044B' : replyFrom;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: isMe
            ? FenyvoPalette.surface.withValues(alpha: 0.18)
            : FenyvoPalette.surface.withValues(alpha: 0.32),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isMe
              ? FenyvoPalette.secondary
              : _gold.withValues(alpha: 0.55),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (author.isNotEmpty)
            Text(
              author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: isMe ? FenyvoPalette.ink : _gold,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          if (author.isNotEmpty) const SizedBox(height: 2),
          Text(
            replyText,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isMe ? FenyvoPalette.ink : FenyvoPalette.secondary,
              fontSize: 11.5,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposerReplyPreview() {
    final reply = _replyToMessage;

    if (reply == null) {
      return const SizedBox.shrink();
    }

    final currentUser = SocketService.instance.currentUser ?? '';

    final from = reply['from']?.toString().trim() ?? '';

    final text = reply['text']?.toString().trim() ?? '';

    final author = from == currentUser ? '\u0412\u044B' : from;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: FenyvoPalette.surface,
        border: Border(
          top: BorderSide(color: _gold.withValues(alpha: 0.22), width: 0.8),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 38,
            decoration: BoxDecoration(
              color: FenyvoPalette.blue,
              borderRadius: BorderRadius.circular(3),
              boxShadow: [
                BoxShadow(color: _gold.withValues(alpha: 0.06), blurRadius: 6),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  author.isEmpty ? '\u041E\u0442\u0432\u0435\u0442' : author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: FenyvoPalette.secondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (Platform.isWindows) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: FenyvoPalette.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: _gold.withValues(alpha: 0.18),
                  width: 0.7,
                ),
              ),
              child: const Text(
                'ESC',
                style: TextStyle(
                  color: FenyvoPalette.secondary,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 2),
          ],
          IconButton(
            onPressed: _cancelReply,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, color: _gold, size: 21),
          ),
        ],
      ),
    );
  }

  // ========================================
  // \u041E\u0422\u041F\u0420\u0410\u0412\u041A\u0410 \u0420\u0415\u0410\u041A\u0426\u0418\u0418
  // ========================================

  void _sendReaction(Map<String, dynamic> message, String reaction) {
    final currentUser = SocketService.instance.currentUser ?? '';

    if (currentUser.isEmpty || !_supportedReactions.contains(reaction)) {
      return;
    }

    if (!SocketService.instance.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u041D\u0435\u0442 \u043F\u043E\u0434\u043A\u043B\u044E\u0447\u0435\u043D\u0438\u044F \u043A \u0441\u0435\u0440\u0432\u0435\u0440\u0443',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final from = message['from']?.toString().trim() ?? '';
    final to = message['to']?.toString().trim() ?? '';
    if (from.isEmpty || to.isEmpty) {
      return;
    }

    final messageId = _getMessageId(message);
    if (messageId.isEmpty) {
      return;
    }

    final reactions = _getMessageReactions(message);
    if (reactions[currentUser] == reaction) {
      reactions.remove(currentUser);
    } else {
      reactions[currentUser] = reaction;
    }

    final messageIndex = _messages.indexWhere(
      (item) => _getMessageId(item) == messageId,
    );

    if (messageIndex >= 0) {
      setState(() {
        _messages[messageIndex]['reactions'] = reactions;
        _messages[messageIndex].remove('reactionUsers');
        _messages[messageIndex].remove('reaction');
      });
      _saveMessages();
    }

    SocketService.instance.sendMessageReaction(
      messageId: messageId,
      from: from,
      to: to,
      reaction: reaction,
    );
  }

  void _showReactionBurst(String reaction) {
    if (!mounted || !_supportedReactions.contains(reaction)) {
      return;
    }

    final overlay = Overlay.of(context, rootOverlay: true);

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        final size = MediaQuery.sizeOf(context);
        final centerX = size.width / 2;
        final centerY = size.height / 2;
        final particles = <Offset>[
          const Offset(-110, -160),
          const Offset(110, -145),
          const Offset(-145, -10),
          const Offset(145, -8),
          const Offset(-95, 145),
          const Offset(95, 155),
          const Offset(0, -210),
          const Offset(0, 200),
        ];

        return IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: TweenAnimationBuilder<double>(
              duration: const Duration(milliseconds: 1350),
              tween: Tween(begin: 0, end: 1),
              builder: (context, value, child) {
                final fadeOut = value < 0.70
                    ? 1.0
                    : (1.0 - ((value - 0.70) / 0.30)).clamp(0.0, 1.0);
                final centerScale =
                    0.35 + (value < 0.40 ? value / 0.40 : 1.0) * 0.85;
                final centerLift = (1 - value) * 30;

                return Stack(
                  children: [
                    Positioned.fill(
                      child: Container(
                        color: FenyvoPalette.surface.withValues(
                          alpha: 0.12 * fadeOut,
                        ),
                      ),
                    ),
                    Positioned(
                      left: centerX - 70,
                      top: centerY - 90 - centerLift,
                      child: Opacity(
                        opacity: fadeOut,
                        child: Transform.scale(
                          scale: centerScale,
                          child: Text(
                            reaction,
                            style: const TextStyle(fontSize: 112),
                          ),
                        ),
                      ),
                    ),
                    for (var i = 0; i < particles.length; i++)
                      Positioned(
                        left: centerX - 24 + (particles[i].dx * value),
                        top: centerY - 24 + (particles[i].dy * value),
                        child: Opacity(
                          opacity: (1 - value).clamp(0.0, 1.0),
                          child: Transform.scale(
                            scale: 0.55 + (1 - value) * 0.65,
                            child: Text(
                              reaction,
                              style: const TextStyle(fontSize: 34),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    overlay.insert(entry);
    Future<void>.delayed(const Duration(milliseconds: 1380), () {
      try {
        entry.remove();
      } catch (_) {}
    });
  }

  // ========================================
  // \u0412\u0420\u0415\u041C\u042F \u0421\u041E\u041E\u0411\u0429\u0415\u041D\u0418\u042F
  // ========================================

  String _formatTime(dynamic timeData) {
    if (timeData == null) {
      return '';
    }

    try {
      final time = DateTime.parse(timeData.toString()).toLocal();

      return '${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  DateTime? _parseMessageLocalDate(dynamic timeData) {
    return parseMessageLocalDate(timeData);
  }

  bool _isSameMessageDay(dynamic firstTime, dynamic secondTime) {
    final first = _parseMessageLocalDate(firstTime);
    final second = _parseMessageLocalDate(secondTime);
    if (first == null || second == null) return false;
    return isSameMessageCalendarDay(first, second);
  }

  String _formatMessageDateLabel(dynamic timeData) {
    final date = _parseMessageLocalDate(timeData);

    if (date == null) {
      return '';
    }

    final now = DateTime.now();

    final today = DateTime(now.year, now.month, now.day);

    final messageDay = DateTime(date.year, date.month, date.day);

    final difference = today.difference(messageDay).inDays;

    if (difference == 0) {
      return _chatText('today');
    }

    if (difference == 1) {
      return _chatText('yesterday');
    }

    return MaterialLocalizations.of(context).formatMediumDate(date);
  }

  Widget _buildMessageDateSeparator(dynamic timeData) {
    final label = _formatMessageDateLabel(timeData);

    if (label.isEmpty) {
      return const SizedBox.shrink();
    }

    final isWindowsDesktop = Platform.isWindows;

    return Padding(
      padding: EdgeInsets.only(
        top: isWindowsDesktop ? 12 : 9,
        bottom: isWindowsDesktop ? 12 : 9,
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: FenyvoPalette.blue.withValues(alpha: 0.12),
            ),
          ),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 10),
            padding: EdgeInsets.symmetric(
              horizontal: isWindowsDesktop ? 12 : 10,
              vertical: isWindowsDesktop ? 5 : 4,
            ),
            decoration: BoxDecoration(
              color: FenyvoPalette.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _gold.withValues(alpha: 0.24),
                width: 0.8,
              ),
              boxShadow: isWindowsDesktop
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Text(
              label.toUpperCase(),
              style: TextStyle(
                color: _gold.withValues(alpha: 0.88),
                fontSize: isWindowsDesktop ? 11 : 10.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: FenyvoPalette.blue.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageListItem(int reverseIndex) {
    final messageIndex = _messages.length - 1 - reverseIndex;

    final message = _messages[messageIndex];

    final isFirstMessage = messageIndex == 0;

    final previousMessage = isFirstMessage ? null : _messages[messageIndex - 1];

    final showDateSeparator =
        isFirstMessage ||
        previousMessage == null ||
        !_isSameMessageDay(message['time'], previousMessage['time']);

    final messageId = _getMessageId(message);

    return KeyedSubtree(
      key: _messageItemKey(messageId),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDateSeparator) _buildMessageDateSeparator(message['time']),
          _buildMessageBubble(message),
        ],
      ),
    );
  }

  GlobalKey _messageItemKey(String messageId) {
    return _messageItemKeys.putIfAbsent(messageId, GlobalKey.new);
  }

  void _recalculateSearchMatches() {
    final previousId =
        _searchMatchIndex >= 0 && _searchMatchIndex < _searchMatchIds.length
        ? _searchMatchIds[_searchMatchIndex]
        : '';

    _searchMatchIds = _messages
        .where((message) => MessageSearchService.matches(message, _searchQuery))
        .map(_getMessageId)
        .where((id) => id.isNotEmpty)
        .toList(growable: false);

    if (_searchMatchIds.isEmpty) {
      _searchMatchIndex = -1;
      return;
    }

    final previousIndex = previousId.isEmpty
        ? -1
        : _searchMatchIds.indexOf(previousId);
    _searchMatchIndex = previousIndex >= 0
        ? previousIndex
        : _searchMatchIds.length - 1;
  }

  void _openMessageSearch() {
    setState(() {
      _searchMode = true;
      _searchQuery = _searchController.text.trim();
      _recalculateSearchMatches();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeMessageSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _searchMode = false;
      _searchQuery = '';
      _searchMatchIds = <String>[];
      _searchMatchIndex = -1;
    });
  }

  void _onMessageSearchChanged(String value) {
    setState(() {
      _searchQuery = value.trim();
      _recalculateSearchMatches();
    });

    if (_searchMatchIndex >= 0) {
      unawaited(_jumpToCurrentSearchMatch());
    }
  }

  Future<void> _jumpToCurrentSearchMatch() async {
    if (_searchMatchIndex < 0 || _searchMatchIndex >= _searchMatchIds.length) {
      return;
    }

    final id = _searchMatchIds[_searchMatchIndex];
    final index = _messages.indexWhere(
      (message) => _getMessageId(message) == id,
    );
    if (index >= 0) await _jumpToPinnedMessage(_messages[index]);
  }

  Future<void> _nextMessageSearchMatch({required bool newer}) async {
    if (_searchMatchIds.isEmpty) return;

    setState(() {
      if (_searchMatchIndex < 0) {
        _searchMatchIndex = _searchMatchIds.length - 1;
      } else if (newer) {
        _searchMatchIndex = (_searchMatchIndex + 1) % _searchMatchIds.length;
      } else {
        _searchMatchIndex =
            (_searchMatchIndex - 1 + _searchMatchIds.length) %
            _searchMatchIds.length;
      }
    });

    await _jumpToCurrentSearchMatch();
  }

  Widget _buildMessageSearchBar() {
    final matchCount = _searchMatchIds.length;
    final current = _searchMatchIndex >= 0 ? _searchMatchIndex + 1 : 0;

    return Container(
      color: FenyvoPalette.surface,
      padding: EdgeInsets.fromLTRB(
        Platform.isWindows ? 16 : 10,
        7,
        Platform.isWindows ? 16 : 10,
        7,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              onChanged: _onMessageSearchChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(color: FenyvoPalette.ink),
              decoration: InputDecoration(
                hintText: _chatText('searchConversationHint'),
                hintStyle: const TextStyle(color: FenyvoPalette.muted),
                prefixIcon: const Icon(Icons.search_rounded, color: _gold),
                suffixText: _searchQuery.isEmpty
                    ? null
                    : '$current/$matchCount',
                suffixStyle: const TextStyle(
                  color: _gold,
                  fontWeight: FontWeight.w700,
                ),
                filled: true,
                fillColor: FenyvoPalette.canvasDeep,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: _chatText('previousMatch'),
            onPressed: matchCount == 0
                ? null
                : () => unawaited(_nextMessageSearchMatch(newer: false)),
            icon: const Icon(Icons.keyboard_arrow_up_rounded, color: _gold),
          ),
          IconButton(
            tooltip: _chatText('nextMatch'),
            onPressed: matchCount == 0
                ? null
                : () => unawaited(_nextMessageSearchMatch(newer: true)),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _gold),
          ),
          IconButton(
            tooltip: _chatText('closeSearch'),
            onPressed: _closeMessageSearch,
            icon: const Icon(
              Icons.close_rounded,
              color: FenyvoPalette.secondary,
            ),
          ),
        ],
      ),
    );
  }

  bool _isMessagePinned(Map<String, dynamic> message) {
    return message['isPinned'] == true;
  }

  List<Map<String, dynamic>> _getPinnedMessages() {
    return _messages.where(_isMessagePinned).take(10).toList(growable: false);
  }

  void _togglePinnedMessage(Map<String, dynamic> message) {
    final targetId = _getMessageId(message);

    if (targetId.isEmpty) {
      return;
    }

    final wasPinned = _isMessagePinned(message);

    final pinnedCount = _messages.where(_isMessagePinned).length;

    if (!wasPinned && pinnedCount >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_chatText('pinLimit')),
          backgroundColor: FenyvoPalette.surface,
        ),
      );
      return;
    }

    setState(() {
      for (final item in _messages) {
        if (_getMessageId(item) == targetId) {
          item['isPinned'] = !wasPinned;
          break;
        }
      }
    });

    _saveMessages();

    final currentUser = SocketService.instance.currentUser?.trim() ?? '';
    if (currentUser.isNotEmpty) {
      if (wasPinned) {
        StorageService.removePinnedMessage(
          currentUser,
          widget.targetUser,
          targetId,
        );
      } else {
        StorageService.addPinnedMessage(currentUser, widget.targetUser, {
          'messageId': targetId,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }
    }

    SocketService.instance.setPinnedMessage(
      messageId: targetId,
      to: widget.targetUser,
      pinned: !wasPinned,
      messageFrom: message['from']?.toString() ?? '',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1100),
        behavior: SnackBarBehavior.floating,
        backgroundColor: FenyvoPalette.surface,
        content: Row(
          children: [
            Icon(
              wasPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
              color: _gold,
              size: 18,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                wasPinned
                    ? '\u0421\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u0435 \u043E\u0442\u043A\u0440\u0435\u043F\u043B\u0435\u043D\u043E'
                    : '\u0421\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u0435 \u0437\u0430\u043A\u0440\u0435\u043F\u043B\u0435\u043D\u043E',
                style: const TextStyle(color: FenyvoPalette.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _jumpToPinnedMessage(Map<String, dynamic> message) async {
    final targetId = _getMessageId(message);

    if (targetId.isEmpty) {
      return;
    }

    final messageIndex = _messages.indexWhere(
      (item) => _getMessageId(item) == targetId,
    );

    if (messageIndex < 0) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u0421\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u0435 \u0431\u043E\u043B\u044C\u0448\u0435 \u043D\u0435\u0434\u043E\u0441\u0442\u0443\u043F\u043D\u043E',
          ),
        ),
      );

      return;
    }

    _pinnedHighlightTimer?.cancel();

    if (mounted) {
      setState(() {
        _highlightedMessageId = targetId;
      });
    }

    await Future<void>.delayed(const Duration(milliseconds: 35));

    if (_messageScrollController.hasClients) {
      final targetReverseIndex = _messages.length - 1 - messageIndex;

      final position = _messageScrollController.position;

      final maxExtent = position.maxScrollExtent;

      final estimatedOffset = _messages.length <= 1
          ? 0.0
          : maxExtent * targetReverseIndex / (_messages.length - 1);

      await _messageScrollController.animateTo(
        estimatedOffset.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );

      for (var attempt = 0; attempt < 24; attempt++) {
        if (!mounted || !_messageScrollController.hasClients) {
          break;
        }

        await Future<void>.delayed(const Duration(milliseconds: 35));

        final itemContext = _messageItemKeys[targetId]?.currentContext;

        if (itemContext != null) {
          await Scrollable.ensureVisible(
            itemContext,
            alignment: 0.50,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          );

          break;
        }

        final builtReverseIndices = <int>[];

        for (
          var reverseIndex = 0;
          reverseIndex < _messages.length;
          reverseIndex++
        ) {
          final index = _messages.length - 1 - reverseIndex;

          final id = _getMessageId(_messages[index]);

          if (id.isEmpty) {
            continue;
          }

          if (_messageItemKeys[id]?.currentContext != null) {
            builtReverseIndices.add(reverseIndex);
          }
        }

        final currentPosition = _messageScrollController.position;

        final viewport = currentPosition.viewportDimension;

        final step = viewport > 220 ? viewport * 0.78 : 220.0;

        var nextOffset = currentPosition.pixels;

        if (builtReverseIndices.isEmpty) {
          nextOffset = estimatedOffset;
        } else {
          builtReverseIndices.sort();

          final firstBuilt = builtReverseIndices.first;

          final lastBuilt = builtReverseIndices.last;

          if (targetReverseIndex > lastBuilt) {
            nextOffset += step;
          } else if (targetReverseIndex < firstBuilt) {
            nextOffset -= step;
          } else {
            nextOffset = estimatedOffset;
          }
        }

        final clampedOffset = nextOffset.clamp(
          currentPosition.minScrollExtent,
          currentPosition.maxScrollExtent,
        );

        if ((clampedOffset - currentPosition.pixels).abs() < 1.0) {
          break;
        }

        await _messageScrollController.animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
        );
      }

      final finalContext = _messageItemKeys[targetId]?.currentContext;

      if (finalContext != null) {
        await Scrollable.ensureVisible(
          finalContext,
          alignment: 0.50,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    }

    _pinnedHighlightTimer = Timer(const Duration(milliseconds: 2200), () {
      if (!mounted || _highlightedMessageId != targetId) {
        return;
      }

      setState(() {
        _highlightedMessageId = null;
      });
    });
  }

  Widget _buildPinnedMessageBanner() {
    final pinned = _getPinnedMessages();
    if (pinned.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        color: FenyvoPalette.surface,
        border: Border(
          bottom: BorderSide(color: FenyvoPalette.line, width: .5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(
            Icons.push_pin_outlined,
            size: 18,
            color: FenyvoPalette.gold,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: pinned.length,
              separatorBuilder: (_, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final message = pinned[index];
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: InkWell(
                          onTap: () => unawaited(_jumpToPinnedMessage(message)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              message['text']?.toString() ??
                                  _chatText('message'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: FenyvoPalette.ink,
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: _chatText('unpin'),
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        onPressed: () => _togglePinnedMessage(message),
                        icon: const Icon(Icons.close_rounded, size: 16),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Text(
            '${pinned.length}/10',
            style: const TextStyle(
              color: FenyvoPalette.secondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackground() {
    final backgroundPath = _backgroundPath;

    if (backgroundPath == null || backgroundPath.isEmpty) {
      return const Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [FenyvoPalette.canvasDeep, FenyvoPalette.canvas],
            ),
          ),
        ),
      );
    }

    final file = File(backgroundPath);

    if (!file.existsSync()) {
      return const Positioned.fill(
        child: ColoredBox(color: FenyvoPalette.canvas),
      );
    }

    return Positioned.fill(
      child: ColoredBox(
        color: FenyvoPalette.canvas,
        child: Opacity(
          opacity: _backgroundOpacity,
          child: Image.file(
            file,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }

  // ========================================
  // \u041E\u0414\u041D\u041E \u0417\u041E\u041B\u041E\u0422\u041E\u0415 \u0421\u0415\u0420\u0414\u0415\u0427\u041A\u041E
  // ========================================

  Widget _buildHeartIcon({
    required bool filled,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: FenyvoPalette.surface.withValues(alpha: 0.72),
          border: Border.all(
            color: _gold.withValues(alpha: enabled ? 0.95 : 0.70),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          filled ? Icons.favorite : Icons.favorite_border,
          color: _gold,
          size: 18,
        ),
      ),
    );
  }

  Widget _buildReactionChip({
    required String reaction,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? FenyvoPalette.blue.withValues(alpha: 0.22)
              : FenyvoPalette.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _gold.withValues(alpha: selected ? 1.0 : 0.75),
            width: selected ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? _gold.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: selected ? 8 : 5,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(reaction, style: const TextStyle(fontSize: 16, height: 1)),
            if (count > 1) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: const TextStyle(
                  color: FenyvoPalette.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ========================================
  // \u0420\u042F\u0414 \u0420\u0415\u0410\u041A\u0426\u0418\u0419
  // ========================================

  Widget _buildReactionRow(Map<String, dynamic> message) {
    final currentUser = SocketService.instance.currentUser ?? '';
    final reactions = _getMessageReactions(message);

    if (reactions.isEmpty) return const SizedBox.shrink();

    final counts = countMessageReactions(reactions.values);

    final widgets = <Widget>[];
    for (final reaction in _supportedReactions) {
      final count = counts[reaction] ?? 0;
      if (count == 0) continue;
      if (widgets.isNotEmpty) widgets.add(const SizedBox(width: 4));
      widgets.add(
        _buildReactionChip(
          reaction: reaction,
          count: count,
          selected: reactions[currentUser] == reaction,
          onTap: () {
            _sendReaction(message, reaction);
          },
        ),
      );
    }

    if (currentUser.isNotEmpty && !reactions.containsKey(currentUser)) {
      if (widgets.isNotEmpty) widgets.add(const SizedBox(width: 4));
      widgets.add(
        _buildHeartIcon(
          filled: false,
          enabled: true,
          onTap: () {
            _sendReaction(message, '\u2764\uFE0F');
          },
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: widgets);
  }

  // ========================================
  // \u0413\u0410\u041B\u041E\u0427\u041A\u0418 \u0421\u0422\u0410\u0422\u0423\u0421\u0410
  // ========================================

  Widget _buildMessageStatus(Map<String, dynamic> message) {
    final status = message['status']?.toString().trim() ?? 'sent';

    final isRead = status == 'read';

    if (status == 'queued') {
      return Icon(
        Icons.schedule_rounded,
        size: 15,
        color: FenyvoPalette.secondary,
        semanticLabel: _chatText('waitingToSend'),
      );
    }
    if (status == 'sending') {
      return Icon(
        Icons.sync_rounded,
        size: 15,
        color: FenyvoPalette.secondary,
        semanticLabel: _chatText('sending'),
      );
    }
    if (status == 'failed') {
      return Icon(
        Icons.error_outline_rounded,
        size: 15,
        color: Colors.red,
        semanticLabel: _chatText('notSent'),
      );
    }

    return Icon(
      isRead || status == 'delivered'
          ? Icons.done_all_rounded
          : Icons.done_rounded,
      size: 15,
      color: isRead ? FenyvoPalette.gold : FenyvoPalette.secondary,
      semanticLabel: isRead
          ? _chatText('read')
          : status == 'delivered'
          ? _chatText('delivered')
          : _chatText('sent'),
    );
  }

  // ========================================
  // \u041C\u0415\u041D\u042E \u041F\u041E \u0414\u041E\u041B\u0413\u041E\u041C\u0423 \u041D\u0410\u0416\u0410\u0422\u0418\u042E
  // ========================================

  Future<void> _copyMessageText(Map<String, dynamic> message) async {
    final text = message['text']?.toString() ?? '';

    if (text.isEmpty) {
      return;
    }

    await Clipboard.setData(ClipboardData(text: text));

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '\u0421\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u0435 \u0441\u043A\u043E\u043F\u0438\u0440\u043E\u0432\u0430\u043D\u043E',
        ),
        backgroundColor: FenyvoPalette.surface,
        duration: Duration(milliseconds: 1000),
      ),
    );
  }

  Future<String> _requestTranslation({
    required String text,
    required String targetLanguage,
  }) async {
    final cleanText = text.trim();

    if (cleanText.isEmpty) {
      return '';
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);

    try {
      final uri = Uri.https('translate.googleapis.com', '/translate_a/single', {
        'client': 'gtx',
        'sl': 'auto',
        'tl': targetLanguage,
        'dt': 't',
        'q': cleanText,
      });

      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 12));

      request.headers.set(
        HttpHeaders.userAgentHeader,
        'Mozilla/5.0 FenyvoChat/1.0',
      );

      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}');
      }

      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 12));

      final decoded = jsonDecode(body);

      if (decoded is! List || decoded.isEmpty || decoded.first is! List) {
        throw const FormatException(
          '\u041D\u0435\u043A\u043E\u0440\u0440\u0435\u043A\u0442\u043D\u044B\u0439 \u043E\u0442\u0432\u0435\u0442 \u043F\u0435\u0440\u0435\u0432\u043E\u0434\u0447\u0438\u043A\u0430',
        );
      }

      final translated = StringBuffer();

      for (final segment in decoded.first as List) {
        if (segment is List && segment.isNotEmpty && segment.first != null) {
          translated.write(segment.first.toString());
        }
      }

      final result = translated.toString().trim();

      if (result.isEmpty) {
        throw const FormatException(
          '\u041F\u0443\u0441\u0442\u043E\u0439 \u043F\u0435\u0440\u0435\u0432\u043E\u0434',
        );
      }

      return result;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _translateMessage(Map<String, dynamic> message) async {
    final originalText = message['text']?.toString().trim() ?? '';

    if (originalText.isEmpty || !mounted) {
      return;
    }

    var targetLanguage = 'uk';
    var translatedText = '';
    var isLoading = false;
    String? errorText;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> performTranslation() async {
              if (isLoading) {
                return;
              }

              setSheetState(() {
                isLoading = true;
                errorText = null;
              });

              try {
                final result = await _requestTranslation(
                  text: originalText,
                  targetLanguage: targetLanguage,
                );

                if (!sheetContext.mounted) {
                  return;
                }

                setSheetState(() {
                  translatedText = result;
                  isLoading = false;
                });
              } catch (_) {
                if (!sheetContext.mounted) {
                  return;
                }

                setSheetState(() {
                  translatedText = '';
                  isLoading = false;
                  errorText = '\u041D\u0435 \u0443\u0434\u0430\u043B\u043E\u0441\u044C \u043F\u0435\u0440\u0435\u0432\u0435\u0441\u0442\u0438. \u041F\u0440\u043E\u0432\u0435\u0440\u044C \u0438\u043D\u0442\u0435\u0440\u043D\u0435\u0442 \u0438 \u043F\u043E\u043F\u0440\u043E\u0431\u0443\u0439 \u0435\u0449\u0451 \u0440\u0430\u0437.';
                });
              }
            }

            Widget languageButton({
              required String code,
              required String label,
            }) {
              final selected = targetLanguage == code;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: OutlinedButton(
                    onPressed: isLoading
                        ? null
                        : () {
                            setSheetState(() {
                              targetLanguage = code;
                              translatedText = '';
                              errorText = null;
                            });
                          },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: selected
                          ? FenyvoPalette.ink
                          : FenyvoPalette.ink,
                      backgroundColor: selected
                          ? FenyvoPalette.blue
                          : FenyvoPalette.surface,
                      side: BorderSide(
                        color: selected ? _gold : _gold.withValues(alpha: 0.45),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              );
            }

            return SafeArea(
              top: false,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.88,
                ),
                decoration: const BoxDecoration(
                  color: FenyvoPalette.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(top: BorderSide(color: _gold, width: 1.2)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: FenyvoPalette.line,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Row(
                        children: [
                          Icon(Icons.translate_rounded, color: _gold),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '\u041F\u0435\u0440\u0435\u0432\u043E\u0434 \u0441\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u044F',
                              style: TextStyle(
                                color: FenyvoPalette.ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        '\u041E\u0420\u0418\u0413\u0418\u041D\u0410\u041B',
                        style: TextStyle(
                          color: _gold,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: FenyvoPalette.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _gold.withValues(alpha: 0.30),
                          ),
                        ),
                        child: SelectableText(
                          originalText,
                          style: const TextStyle(
                            color: FenyvoPalette.ink,
                            fontSize: 15,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        '\u041F\u0415\u0420\u0415\u0412\u0415\u0421\u0422\u0418 \u041D\u0410',
                        style: TextStyle(
                          color: _gold,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          languageButton(
                            code: 'uk',
                            label: '\u0423\u043A\u0440\u0430\u0457\u043D\u0441\u044C\u043A\u0430',
                          ),
                          languageButton(
                            code: 'ru',
                            label: '\u0420\u0443\u0441\u0441\u043A\u0438\u0439',
                          ),
                          languageButton(code: 'en', label: 'English'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          languageButton(
                            code: 'ar',
                            label: '\u0627\u0644\u0639\u0631\u0628\u064A\u0629',
                          ),
                          languageButton(code: 'zh-CN', label: '\u4E2D\u6587'),
                          languageButton(
                            code: 'ja',
                            label: '\u65E5\u672C\u8A9E',
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: isLoading ? null : performTranslation,
                          style: FilledButton.styleFrom(
                            backgroundColor: FenyvoPalette.blue,
                            foregroundColor: FenyvoPalette.ink,
                            disabledBackgroundColor: _gold.withValues(
                              alpha: 0.35,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          icon: isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: FenyvoPalette.ink,
                                  ),
                                )
                              : const Icon(Icons.translate_rounded),
                          label: Text(
                            isLoading
                                ? '\u041F\u0435\u0440\u0435\u0432\u043E\u0434\u0438\u043C...'
                                : '\u041F\u0435\u0440\u0435\u0432\u0435\u0441\u0442\u0438',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.redAccent.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Text(
                            errorText!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                      if (translatedText.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        const Text(
                          '\u041F\u0415\u0420\u0415\u0412\u041E\u0414',
                          style: TextStyle(
                            color: _gold,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: FenyvoPalette.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _gold.withValues(alpha: 0.55),
                            ),
                          ),
                          child: SelectableText(
                            translatedText,
                            textDirection: targetLanguage == 'ar'
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            textAlign: targetLanguage == 'ar'
                                ? TextAlign.right
                                : TextAlign.left,
                            style: const TextStyle(
                              color: FenyvoPalette.ink,
                              fontSize: 16,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: translatedText),
                              );

                              if (!sheetContext.mounted) {
                                return;
                              }

                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    '\u041F\u0435\u0440\u0435\u0432\u043E\u0434 \u0441\u043A\u043E\u043F\u0438\u0440\u043E\u0432\u0430\u043D',
                                  ),
                                  backgroundColor: FenyvoPalette.surface,
                                  duration: Duration(milliseconds: 1000),
                                ),
                              );
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _gold,
                              side: BorderSide(
                                color: _gold.withValues(alpha: 0.65),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            icon: const Icon(Icons.copy_rounded),
                            label: const Text(
                              '\u0421\u043A\u043E\u043F\u0438\u0440\u043E\u0432\u0430\u0442\u044C \u043F\u0435\u0440\u0435\u0432\u043E\u0434',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _fenyvoAiRequestId(String suffix) {
    return '${DateTime.now().microsecondsSinceEpoch}_${suffix.hashCode.abs()}';
  }

  Future<Map<String, dynamic>> _waitForFenyvoAiRequest({
    required String requestId,
    required void Function() sendRequest,
  }) async {
    if (!SocketService.instance.isConnected) {
      throw Exception(
        '\u041D\u0435\u0442 \u043F\u043E\u0434\u043A\u043B\u044E\u0447\u0435\u043D\u0438\u044F \u043A \u0441\u0435\u0440\u0432\u0435\u0440\u0443',
      );
    }

    final completer = Completer<Map<String, dynamic>>();

    _fenyvoAiCompleters[requestId] = completer;

    sendRequest();

    try {
      return await completer.future.timeout(
        const Duration(seconds: 65),
        onTimeout: () {
          throw TimeoutException(
            'FENYVO AI \u043D\u0435 \u043E\u0442\u0432\u0435\u0442\u0438\u043B \u0432\u043E\u0432\u0440\u0435\u043C\u044F',
          );
        },
      );
    } finally {
      _fenyvoAiCompleters.remove(requestId);
    }
  }

  Future<List<Map<String, String>>> _getFenyvoAiHistory() async {
    final requestId = _fenyvoAiRequestId('history');

    final data = await _waitForFenyvoAiRequest(
      requestId: requestId,
      sendRequest: () {
        SocketService.instance.requestFenyvoAiHistory(requestId: requestId);
      },
    );

    final rawMessages = data['messages'];

    if (rawMessages is! List) {
      return <Map<String, String>>[];
    }

    final result = <Map<String, String>>[];

    for (final item in rawMessages) {
      if (item is! Map) {
        continue;
      }

      final map = Map<String, dynamic>.from(item);
      final role = map['role']?.toString().trim() ?? '';
      final text = map['text']?.toString().trim() ?? '';

      if ((role == 'user' || role == 'assistant') && text.isNotEmpty) {
        result.add({'role': role, 'text': text});
      }
    }

    return result;
  }

  Future<String> _requestFenyvoAi(String text) async {
    final cleanText = text.trim();

    if (cleanText.isEmpty) {
      throw Exception(
        '\u041F\u0443\u0441\u0442\u043E\u0439 \u0432\u043E\u043F\u0440\u043E\u0441',
      );
    }

    final requestId = _fenyvoAiRequestId('ask');

    final data = await _waitForFenyvoAiRequest(
      requestId: requestId,
      sendRequest: () {
        SocketService.instance.sendFenyvoAiRequest(
          requestId: requestId,
          text: cleanText,
          peer: widget.targetUser,
        );
      },
    );

    final result = data['result']?.toString().trim() ?? '';

    if (result.isEmpty) {
      throw Exception(
        'FENYVO AI \u0432\u0435\u0440\u043D\u0443\u043B \u043F\u0443\u0441\u0442\u043E\u0439 \u043E\u0442\u0432\u0435\u0442',
      );
    }

    return result;
  }

  Future<void> _clearFenyvoAi() async {
    final requestId = _fenyvoAiRequestId('clear');

    await _waitForFenyvoAiRequest(
      requestId: requestId,
      sendRequest: () {
        SocketService.instance.clearFenyvoAiHistory(requestId: requestId);
      },
    );
  }

  Future<void> _showFenyvoAiSheet() async {
    if (!mounted) {
      return;
    }

    List<Map<String, String>> messages = <Map<String, String>>[];
    String? initialError;

    try {
      messages = await _getFenyvoAiHistory();
    } catch (error) {
      var text = error.toString();
      if (text.startsWith('Exception: ')) {
        text = text.substring(11);
      }
      initialError = text;
    }

    if (!mounted) {
      return;
    }

    final inputController = TextEditingController();
    final aiScrollController = ScrollController();

    var isLoading = false;
    String? errorText = initialError;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            void scrollToBottom() {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!aiScrollController.hasClients) {
                  return;
                }

                aiScrollController.animateTo(
                  aiScrollController.position.maxScrollExtent,
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                );
              });
            }

            Future<void> sendQuestion() async {
              final question = inputController.text.trim();

              if (question.isEmpty || isLoading) {
                return;
              }

              inputController.clear();

              setSheetState(() {
                messages.add({'role': 'user', 'text': question});
                isLoading = true;
                errorText = null;
              });

              scrollToBottom();

              try {
                final answer = await _requestFenyvoAi(question);

                if (!sheetContext.mounted) {
                  return;
                }

                setSheetState(() {
                  messages.add({'role': 'assistant', 'text': answer});
                  isLoading = false;
                });

                scrollToBottom();
              } catch (error) {
                if (!sheetContext.mounted) {
                  return;
                }

                var text = error.toString();
                if (text.startsWith('Exception: ')) {
                  text = text.substring(11);
                }

                setSheetState(() {
                  isLoading = false;
                  errorText = text;
                });
              }
            }

            Future<void> clearHistory() async {
              if (isLoading) {
                return;
              }

              setSheetState(() {
                isLoading = true;
                errorText = null;
              });

              try {
                await _clearFenyvoAi();

                if (!sheetContext.mounted) {
                  return;
                }

                setSheetState(() {
                  messages.clear();
                  isLoading = false;
                });
              } catch (error) {
                if (!sheetContext.mounted) {
                  return;
                }

                var text = error.toString();
                if (text.startsWith('Exception: ')) {
                  text = text.substring(11);
                }

                setSheetState(() {
                  isLoading = false;
                  errorText = text;
                });
              }
            }

            Widget aiMessageBubble(Map<String, String> item) {
              final isUser = item['role'] == 'user';
              final text = item['text'] ?? '';

              return Align(
                alignment: isUser
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: GestureDetector(
                  onLongPress: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                  },
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 520),
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    decoration: BoxDecoration(
                      color: isUser
                          ? FenyvoPalette.blue.withValues(alpha: 0.20)
                          : FenyvoPalette.surface,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: isUser
                            ? _gold.withValues(alpha: 0.70)
                            : FenyvoPalette.line,
                      ),
                    ),
                    child: SelectableText(
                      text,
                      style: const TextStyle(
                        color: FenyvoPalette.ink,
                        fontSize: 15,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 10,
                  right: 10,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 8,
                ),
                child: FractionallySizedBox(
                  heightFactor: 0.94,
                  child: Container(
                    decoration: BoxDecoration(
                      color: FenyvoPalette.surface,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(color: _gold.withValues(alpha: 0.45)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 28,
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 42,
                          height: 4,
                          margin: const EdgeInsets.only(top: 10),
                          decoration: BoxDecoration(
                            color: FenyvoPalette.line,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 10, 10),
                          child: Row(
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: FenyvoPalette.blue.withValues(
                                    alpha: 0.15,
                                  ),
                                  border: Border.all(color: _gold),
                                ),
                                child: const Icon(
                                  Icons.auto_awesome_rounded,
                                  color: _gold,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'FENYVO AI',
                                      style: TextStyle(
                                        color: FenyvoPalette.ink,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _chatText('aiAssistantSubtitle'),
                                      style: const TextStyle(
                                        color: FenyvoPalette.secondary,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: _chatText('clearHistory'),
                                onPressed: isLoading
                                    ? null
                                    : () {
                                        unawaited(clearHistory());
                                      },
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: FenyvoPalette.secondary,
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  Navigator.of(sheetContext).pop();
                                },
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: FenyvoPalette.secondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(height: 1, color: FenyvoPalette.line),
                        Expanded(
                          child: messages.isEmpty
                              ? Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(28),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.auto_awesome_rounded,
                                          color: _gold,
                                          size: 42,
                                        ),
                                        const SizedBox(height: 14),
                                        Text(
                                          _chatText('askAiAnything'),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: FenyvoPalette.ink,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          _chatText('aiEmptyDescription'),
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(
                                            color: FenyvoPalette.secondary,
                                            fontSize: 13,
                                            height: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              : ListView.builder(
                                  controller: aiScrollController,
                                  padding: const EdgeInsets.fromLTRB(
                                    14,
                                    14,
                                    14,
                                    18,
                                  ),
                                  itemCount:
                                      messages.length + (isLoading ? 1 : 0),
                                  itemBuilder: (context, index) {
                                    if (index >= messages.length) {
                                      return const Align(
                                        alignment: Alignment.centerLeft,
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 10,
                                            horizontal: 8,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              SizedBox(
                                                width: 18,
                                                height: 18,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: _gold,
                                                    ),
                                              ),
                                              SizedBox(width: 10),
                                              Text(
                                                'FENYVO AI...',
                                                style: TextStyle(
                                                  color:
                                                      FenyvoPalette.secondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                    }

                                    return aiMessageBubble(messages[index]);
                                  },
                                ),
                        ),
                        if (errorText != null && errorText!.isNotEmpty)
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.redAccent.withValues(alpha: 0.45),
                              ),
                            ),
                            child: Text(
                              errorText!,
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: inputController,
                                  enabled: !isLoading,
                                  minLines: 1,
                                  maxLines: 5,
                                  textInputAction: TextInputAction.newline,
                                  style: const TextStyle(
                                    color: FenyvoPalette.ink,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: _chatText('askQuestionHint'),
                                    hintStyle: const TextStyle(
                                      color: FenyvoPalette.muted,
                                    ),
                                    filled: true,
                                    fillColor: FenyvoPalette.surface,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 12,
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      borderSide: BorderSide.none,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      borderSide: BorderSide(
                                        color: _gold.withValues(alpha: 0.25),
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(20),
                                      borderSide: const BorderSide(
                                        color: _gold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 46,
                                height: 46,
                                child: FilledButton(
                                  onPressed: isLoading
                                      ? null
                                      : () {
                                          unawaited(sendQuestion());
                                        },
                                  style: FilledButton.styleFrom(
                                    backgroundColor: FenyvoPalette.blue,
                                    foregroundColor: FenyvoPalette.ink,
                                    padding: EdgeInsets.zero,
                                    shape: const CircleBorder(),
                                  ),
                                  child: const Icon(Icons.arrow_upward_rounded),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            _chatText('aiDisclaimer'),
                            style: const TextStyle(
                              color: FenyvoPalette.muted,
                              fontSize: 10,
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
        );
      },
    );

    inputController.dispose();
    aiScrollController.dispose();
  }

  Future<String> _requestChatGpt({
    required String action,
    required String text,
  }) async {
    final cleanText = text.trim();

    if (cleanText.isEmpty) {
      throw Exception(
        '\u041F\u0443\u0441\u0442\u043E\u0435 \u0441\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u0435',
      );
    }

    if (!SocketService.instance.isConnected) {
      throw Exception(
        '\u041D\u0435\u0442 \u043F\u043E\u0434\u043A\u043B\u044E\u0447\u0435\u043D\u0438\u044F \u043A \u0441\u0435\u0440\u0432\u0435\u0440\u0443',
      );
    }

    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}_${action.hashCode.abs()}';

    final completer = Completer<String>();

    _chatGptCompleters[requestId] = completer;

    SocketService.instance.sendChatGptRequest(
      requestId: requestId,
      action: action,
      text: cleanText,
    );

    try {
      return await completer.future.timeout(
        const Duration(seconds: 50),
        onTimeout: () {
          throw TimeoutException(
            'ChatGPT \u043D\u0435 \u043E\u0442\u0432\u0435\u0442\u0438\u043B \u0432\u043E\u0432\u0440\u0435\u043C\u044F',
          );
        },
      );
    } finally {
      _chatGptCompleters.remove(requestId);
    }
  }

  Future<void> _showChatGptSheet(Map<String, dynamic> message) async {
    final originalText = message['text']?.toString().trim() ?? '';

    if (originalText.isEmpty || !mounted) {
      return;
    }

    var selectedAction = 'reply';
    var resultText = '';
    var isLoading = false;
    String? errorText;

    const actionLabels = <String, String>{
      'reply': '\u041F\u0440\u0435\u0434\u043B\u043E\u0436\u0438\u0442\u044C \u043E\u0442\u0432\u0435\u0442',
      'explain': '\u041E\u0431\u044A\u044F\u0441\u043D\u0438\u0442\u044C',
      'rewrite': '\u041F\u0435\u0440\u0435\u0444\u043E\u0440\u043C\u0443\u043B\u0438\u0440\u043E\u0432\u0430\u0442\u044C',
      'shorter': '\u0421\u0434\u0435\u043B\u0430\u0442\u044C \u043A\u043E\u0440\u043E\u0447\u0435',
    };

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> performAction() async {
              if (isLoading) {
                return;
              }

              setSheetState(() {
                isLoading = true;
                errorText = null;
                resultText = '';
              });

              try {
                final result = await _requestChatGpt(
                  action: selectedAction,
                  text: originalText,
                );

                if (!sheetContext.mounted) {
                  return;
                }

                setSheetState(() {
                  resultText = result;
                  isLoading = false;
                });
              } catch (error) {
                if (!sheetContext.mounted) {
                  return;
                }

                var message = error.toString();

                if (message.startsWith('Exception: ')) {
                  message = message.substring(11);
                }

                setSheetState(() {
                  isLoading = false;
                  errorText = message;
                });
              }
            }

            Widget actionButton({
              required String action,
              required IconData icon,
            }) {
              final selected = selectedAction == action;

              return OutlinedButton.icon(
                onPressed: isLoading
                    ? null
                    : () {
                        setSheetState(() {
                          selectedAction = action;
                          resultText = '';
                          errorText = null;
                        });
                      },
                style: OutlinedButton.styleFrom(
                  foregroundColor: selected
                      ? FenyvoPalette.ink
                      : FenyvoPalette.ink,
                  backgroundColor: selected
                      ? FenyvoPalette.blue
                      : FenyvoPalette.surface,
                  side: BorderSide(
                    color: selected ? _gold : _gold.withValues(alpha: 0.45),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                icon: Icon(icon, size: 17),
                label: Text(
                  actionLabels[action] ?? action,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }

            return SafeArea(
              top: false,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.90,
                ),
                decoration: const BoxDecoration(
                  color: FenyvoPalette.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(top: BorderSide(color: _gold, width: 1.2)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: FenyvoPalette.line,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Row(
                        children: [
                          Icon(Icons.auto_awesome_rounded, color: _gold),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'ChatGPT \u0434\u043B\u044F \u0441\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u044F',
                              style: TextStyle(
                                color: FenyvoPalette.ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        '\u0421\u041E\u041E\u0411\u0429\u0415\u041D\u0418\u0415',
                        style: TextStyle(
                          color: _gold,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: FenyvoPalette.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _gold.withValues(alpha: 0.30),
                          ),
                        ),
                        child: SelectableText(
                          originalText,
                          style: const TextStyle(
                            color: FenyvoPalette.ink,
                            fontSize: 15,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        '\u0427\u0422\u041E \u0421\u0414\u0415\u041B\u0410\u0422\u042C',
                        style: TextStyle(
                          color: _gold,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          actionButton(
                            action: 'reply',
                            icon: Icons.reply_rounded,
                          ),
                          actionButton(
                            action: 'explain',
                            icon: Icons.lightbulb_outline_rounded,
                          ),
                          actionButton(
                            action: 'rewrite',
                            icon: Icons.edit_note_rounded,
                          ),
                          actionButton(
                            action: 'shorter',
                            icon: Icons.compress_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: isLoading ? null : performAction,
                          style: FilledButton.styleFrom(
                            backgroundColor: FenyvoPalette.blue,
                            foregroundColor: FenyvoPalette.ink,
                            disabledBackgroundColor: _gold.withValues(
                              alpha: 0.35,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          icon: isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: FenyvoPalette.ink,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome_rounded),
                          label: Text(
                            isLoading
                                ? 'ChatGPT \u0434\u0443\u043C\u0430\u0435\u0442...'
                                : actionLabels[selectedAction] ?? '\u0412\u044B\u043F\u043E\u043B\u043D\u0438\u0442\u044C',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.redAccent.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Text(
                            errorText!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                      if (resultText.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        const Text(
                          '\u0420\u0415\u0417\u0423\u041B\u042C\u0422\u0410\u0422',
                          style: TextStyle(
                            color: _gold,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: FenyvoPalette.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _gold.withValues(alpha: 0.55),
                            ),
                          ),
                          child: SelectableText(
                            resultText,
                            style: const TextStyle(
                              color: FenyvoPalette.ink,
                              fontSize: 16,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: resultText),
                                  );

                                  if (!sheetContext.mounted) {
                                    return;
                                  }

                                  ScaffoldMessenger.of(
                                    sheetContext,
                                  ).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        '\u041E\u0442\u0432\u0435\u0442 ChatGPT \u0441\u043A\u043E\u043F\u0438\u0440\u043E\u0432\u0430\u043D',
                                      ),
                                      backgroundColor: FenyvoPalette.surface,
                                      duration: Duration(milliseconds: 1000),
                                    ),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _gold,
                                  side: BorderSide(
                                    color: _gold.withValues(alpha: 0.65),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                                icon: const Icon(Icons.copy_rounded),
                                label: const Text(
                                  '\u041A\u043E\u043F\u0438\u0440\u043E\u0432\u0430\u0442\u044C',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () {
                                  final value = resultText.trim();

                                  if (value.isEmpty) {
                                    return;
                                  }

                                  Navigator.of(sheetContext).pop();

                                  _messageController.text = value;
                                  _messageController.selection =
                                      TextSelection.collapsed(
                                        offset: value.length,
                                      );
                                  _messageFocusNode.requestFocus();
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: FenyvoPalette.blue,
                                  foregroundColor: FenyvoPalette.ink,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                                icon: const Icon(Icons.input_rounded),
                                label: const Text(
                                  '\u0412\u0441\u0442\u0430\u0432\u0438\u0442\u044C',
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        '\u0422\u0435\u043A\u0441\u0442 \u043E\u0442\u043F\u0440\u0430\u0432\u043B\u044F\u0435\u0442\u0441\u044F \u0432 ChatGPT \u0442\u043E\u043B\u044C\u043A\u043E \u043F\u043E\u0441\u043B\u0435 \u0432\u044B\u0431\u043E\u0440\u0430 \u0434\u0435\u0439\u0441\u0442\u0432\u0438\u044F.',
                        style: TextStyle(
                          color: FenyvoPalette.ink.withValues(alpha: 0.45),
                          fontSize: 11,
                          height: 1.3,
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
  }

  Future<void> _showAutoReplySettings() async {
    if (!SocketService.instance.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_chatText('aiInternetRequired')),
            backgroundColor: Colors.red,
          ),
        );
      }

      return;
    }

    const legacyGoal =
        '\u041F\u043E\u0434\u0434\u0435\u0440\u0436\u0438\u0432\u0430\u0442\u044C \u043F\u043E\u043B\u0435\u0437\u043D\u044B\u0439, \u0443\u0432\u0430\u0436\u0438\u0442\u0435\u043B\u044C\u043D\u044B\u0439 \u0434\u0438\u0430\u043B\u043E\u0433 \u0438 \u043F\u043E\u043C\u043E\u0433\u0430\u0442\u044C \u043F\u0440\u0438\u0439\u0442\u0438 \u043A \u043D\u0443\u0436\u043D\u043E\u043C\u0443 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u0443.';
    const legacyPrompt =
        '\u041E\u0442\u0432\u0435\u0447\u0430\u0439 \u043A\u043E\u0440\u043E\u0442\u043A\u043E, \u0435\u0441\u0442\u0435\u0441\u0442\u0432\u0435\u043D\u043D\u043E \u0438 \u0434\u0440\u0443\u0436\u0435\u043B\u044E\u0431\u043D\u043E. \u041E\u0442\u0432\u0435\u0447\u0430\u0439 \u043D\u0430 \u044F\u0437\u044B\u043A\u0435 \u0441\u043E\u0431\u0435\u0441\u0435\u0434\u043D\u0438\u043A\u0430. \u041D\u0435 \u0434\u043E\u0431\u0430\u0432\u043B\u044F\u0439 \u043F\u043E\u044F\u0441\u043D\u0435\u043D\u0438\u0439 \u043E\u0442 \u0441\u0435\u0431\u044F.';
    const legacyPromptWithEverything =
        '\u041E\u0442\u0432\u0435\u0447\u0430\u0439 \u043A\u043E\u0440\u043E\u0442\u043A\u043E, \u0435\u0441\u0442\u0435\u0441\u0442\u0432\u0435\u043D\u043D\u043E \u0438 \u0434\u0440\u0443\u0436\u0435\u043B\u044E\u0431\u043D\u043E. \u041E\u0442\u0432\u0435\u0447\u0430\u0439 \u043D\u0430 \u044F\u0437\u044B\u043A\u0435 \u0441\u043E\u0431\u0435\u0441\u0435\u0434\u043D\u0438\u043A\u0430. \u041D\u0435 \u0434\u043E\u0431\u0430\u0432\u043B\u044F\u0439 \u043F\u043E\u044F\u0441\u043D\u0435\u043D\u0438\u0439 \u043E\u0442 \u0441\u0435\u0431\u044F. \u0413\u043E\u0432\u043E\u0440\u0438 \u043E\u0431\u043E \u0432\u0441\u0451\u043C.';
    const legacyBoundaries =
        '\u041D\u0435 \u0434\u0430\u0432\u0438, \u043D\u0435 \u0443\u0433\u0440\u043E\u0436\u0430\u0439, \u043D\u0435 \u043E\u0431\u043C\u0430\u043D\u044B\u0432\u0430\u0439 \u0438 \u043D\u0435 \u043C\u0430\u043D\u0438\u043F\u0443\u043B\u0438\u0440\u0443\u0439. \u0423\u0432\u0430\u0436\u0430\u0439 \u043E\u0442\u043A\u0430\u0437 \u0438 \u043F\u0440\u043E\u0441\u044C\u0431\u0443 \u043F\u0440\u0435\u043A\u0440\u0430\u0442\u0438\u0442\u044C \u043E\u0431\u0449\u0435\u043D\u0438\u0435.';
    final goalController = TextEditingController(
      text:
          (_autoReplyGoal == legacyGoal ||
              (_autoReplyGoal.startsWith(
                    '\u041F\u043E\u0434\u0434\u0435\u0440\u0436\u0438\u0432\u0430\u0442\u044C \u043F\u043E\u043B\u0435\u0437\u043D\u044B\u0439',
                  ) &&
                  _autoReplyGoal.length < 220))
          ? _chatText('autoGoalDefault')
          : _autoReplyGoal,
    );
    final promptController = TextEditingController(
      text:
          (_autoReplyPrompt == legacyPrompt ||
              _autoReplyPrompt == legacyPromptWithEverything ||
              (_autoReplyPrompt.startsWith(
                    '\u041E\u0442\u0432\u0435\u0447\u0430\u0439 \u043A\u043E\u0440\u043E\u0442\u043A\u043E',
                  ) &&
                  _autoReplyPrompt.contains(
                    '\u044F\u0437\u044B\u043A\u0435 \u0441\u043E\u0431\u0435\u0441\u0435\u0434\u043D\u0438\u043A\u0430',
                  )))
          ? _chatText('autoPromptDefault')
          : _autoReplyPrompt,
    );
    final contextController = TextEditingController(text: _autoReplyContext);
    final boundariesController = TextEditingController(
      text: _autoReplyBoundaries == legacyBoundaries
          ? _chatText('autoBoundariesDefault')
          : _autoReplyBoundaries,
    );

    var enabled = _autoReplyEnabled;
    var mode = _autoReplyMode;
    var idleSeconds = _autoReplyIdleSeconds;
    var delaySeconds = _autoReplyDelaySeconds;

    Widget buildLabel(String text) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            color: FenyvoPalette.ink,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    InputDecoration inputDecoration(String hint) {
      return InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: FenyvoPalette.muted),
        filled: true,
        fillColor: FenyvoPalette.surface,
        counterStyle: const TextStyle(color: FenyvoPalette.muted),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: FenyvoPalette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _gold),
        ),
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;

            return AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 620),
                decoration: const BoxDecoration(
                  color: FenyvoPalette.canvas,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: FenyvoPalette.line,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: FenyvoPalette.blue.withValues(
                                alpha: 0.12,
                              ),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _gold.withValues(alpha: 0.55),
                              ),
                            ),
                            child: const Icon(
                              Icons.smart_toy_rounded,
                              color: _gold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _chatText('aiAutoTitle'),
                                  style: const TextStyle(
                                    color: FenyvoPalette.ink,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _chatText('aiSeparateSession', {
                                    'user': widget.targetUser,
                                  }),
                                  style: const TextStyle(
                                    color: FenyvoPalette.secondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        decoration: BoxDecoration(
                          color: FenyvoPalette.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: enabled
                                ? _gold.withValues(alpha: 0.55)
                                : FenyvoPalette.line,
                          ),
                        ),
                        child: SwitchListTile.adaptive(
                          value: enabled,
                          onChanged: (value) {
                            setSheetState(() {
                              enabled = value;
                            });

                            // V616: switching OFF is an emergency stop and is
                            // applied to the server immediately. Switching ON
                            // still waits for the Save button so the user can
                            // finish goal/style/context settings first.
                            if (!value) {
                              SocketService.instance.setAutoReplySettings(
                                peer: widget.targetUser,
                                enabled: false,
                                mode: mode,
                                idleSeconds: idleSeconds,
                                goal: goalController.text.trim(),
                                prompt: promptController.text.trim(),
                                context: contextController.text.trim(),
                                boundaries: boundariesController.text.trim(),
                                delaySeconds: delaySeconds,
                              );

                              if (mounted) {
                                setState(() {
                                  _autoReplyEnabled = false;
                                });
                              }
                            }
                          },
                          title: Text(
                            enabled
                                ? _chatText('autoReplyEnabled')
                                : _chatText('autoReplyDisabled'),
                            style: const TextStyle(
                              color: FenyvoPalette.ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            _chatText('autoReplyDescription'),
                            style: const TextStyle(
                              color: FenyvoPalette.secondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      buildLabel(_chatText('aiParticipationMode')),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            <Map<String, String>>[
                              {
                                'id': 'auto',
                                'label': '\u26A1 ${_chatText('modeAuto')}',
                              },
                              {
                                'id': 'suggest',
                                'label':
                                    '\u{1F4A1} ${_chatText('modeSuggest')}',
                              },
                              {
                                'id': 'idle',
                                'label': '\u23F3 ${_chatText('modeIdle')}',
                              },
                              {
                                'id': 'until_goal',
                                'label':
                                    '\u{1F3AF} ${_chatText('modeUntilGoal')}',
                              },
                            ].map((item) {
                              final id = item['id']!;
                              final selected = mode == id;

                              return ChoiceChip(
                                label: Text(item['label']!),
                                selected: selected,
                                onSelected: (_) {
                                  setSheetState(() {
                                    mode = id;
                                  });
                                },
                                selectedColor: _gold,
                                backgroundColor: FenyvoPalette.surface,
                                side: BorderSide(
                                  color: selected ? _gold : FenyvoPalette.line,
                                ),
                                labelStyle: TextStyle(
                                  color: selected
                                      ? FenyvoPalette.ink
                                      : FenyvoPalette.secondary,
                                  fontWeight: FontWeight.w700,
                                ),
                                showCheckmark: false,
                              );
                            }).toList(),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        mode == 'suggest'
                            ? '\u{1F4A1} ${_chatText('modeSuggestDescription')}'
                            : mode == 'idle'
                            ? '\u23F3 ${_chatText('modeIdleDescription')}'
                            : mode == 'until_goal'
                            ? '\u{1F3AF} ${_chatText('modeUntilGoalDescription')}'
                            : '\u26A1 ${_chatText('modeAutoDescription')}',
                        style: const TextStyle(
                          color: FenyvoPalette.secondary,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      if (mode == 'idle') ...[
                        const SizedBox(height: 14),
                        buildLabel(_chatText('idleDelayLabel')),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <int>[30, 60, 120, 300].map((seconds) {
                            final selected = idleSeconds == seconds;
                            final label = seconds < 60
                                ? _chatText('secondsShort', {'count': seconds})
                                : _chatText('minutesShort', {
                                    'count': seconds ~/ 60,
                                  });

                            return ChoiceChip(
                              label: Text(label),
                              selected: selected,
                              onSelected: (_) {
                                setSheetState(() {
                                  idleSeconds = seconds;
                                });
                              },
                              selectedColor: _gold,
                              backgroundColor: FenyvoPalette.surface,
                              side: BorderSide(
                                color: selected ? _gold : FenyvoPalette.line,
                              ),
                              labelStyle: TextStyle(
                                color: selected
                                    ? FenyvoPalette.ink
                                    : FenyvoPalette.secondary,
                                fontWeight: FontWeight.w700,
                              ),
                              showCheckmark: false,
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 18),
                      buildLabel(_chatText('conversationGoal')),
                      TextField(
                        controller: goalController,
                        maxLength: 500,
                        minLines: 2,
                        maxLines: 5,
                        style: const TextStyle(color: FenyvoPalette.ink),
                        decoration: inputDecoration(
                          _chatText('conversationGoalHint'),
                        ),
                      ),
                      const SizedBox(height: 6),
                      buildLabel(_chatText('conversationStyle')),
                      TextField(
                        controller: promptController,
                        maxLength: 600,
                        minLines: 2,
                        maxLines: 5,
                        style: const TextStyle(color: FenyvoPalette.ink),
                        decoration: inputDecoration(
                          _chatText('conversationStyleHint'),
                        ),
                      ),
                      const SizedBox(height: 6),
                      buildLabel(_chatText('aiContext')),
                      TextField(
                        controller: contextController,
                        maxLength: 800,
                        minLines: 2,
                        maxLines: 6,
                        style: const TextStyle(color: FenyvoPalette.ink),
                        decoration: inputDecoration(_chatText('aiContextHint')),
                      ),
                      const SizedBox(height: 6),
                      buildLabel(_chatText('aiBoundaries')),
                      TextField(
                        controller: boundariesController,
                        maxLength: 500,
                        minLines: 2,
                        maxLines: 5,
                        style: const TextStyle(color: FenyvoPalette.ink),
                        decoration: inputDecoration(
                          _chatText('aiBoundariesHint'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      buildLabel(_chatText('replyDelay')),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <int>[3, 5, 10].map((seconds) {
                          final selected = delaySeconds == seconds;

                          return ChoiceChip(
                            label: Text(
                              _chatText('secondsShort', {'count': seconds}),
                            ),
                            selected: selected,
                            onSelected: (_) {
                              setSheetState(() {
                                delaySeconds = seconds;
                              });
                            },
                            selectedColor: _gold,
                            backgroundColor: FenyvoPalette.surface,
                            side: BorderSide(
                              color: selected ? _gold : FenyvoPalette.line,
                            ),
                            labelStyle: TextStyle(
                              color: selected
                                  ? FenyvoPalette.ink
                                  : FenyvoPalette.secondary,
                              fontWeight: FontWeight.w700,
                            ),
                            showCheckmark: false,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: FenyvoPalette.blue.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: _gold.withValues(alpha: 0.20),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              color: _gold,
                              size: 18,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                _chatText('autoReplyMemoryInfo'),
                                style: const TextStyle(
                                  color: FenyvoPalette.secondary,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            SocketService.instance.clearAutoReplyHistory(
                              widget.targetUser,
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: FenyvoPalette.secondary,
                            side: const BorderSide(color: FenyvoPalette.line),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: Text(_chatText('restartAiDialog')),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            var goal = goalController.text.trim();
                            var prompt = promptController.text.trim();
                            final aiContext = contextController.text.trim();
                            var boundaries = boundariesController.text.trim();

                            if (goal.isEmpty) {
                              goal = _chatText('autoGoalDefault');
                            }

                            if (prompt.isEmpty) {
                              prompt = _chatText('autoPromptDefault');
                            }

                            if (boundaries.isEmpty) {
                              boundaries = _chatText('autoBoundariesDefault');
                            }

                            SocketService.instance.setAutoReplySettings(
                              peer: widget.targetUser,
                              enabled: enabled,
                              mode: mode,
                              idleSeconds: idleSeconds,
                              goal: goal,
                              prompt: prompt,
                              context: aiContext,
                              boundaries: boundaries,
                              delaySeconds: delaySeconds,
                            );

                            if (mounted) {
                              setState(() {
                                _autoReplyEnabled = enabled;
                                _autoReplyMode = mode;
                                _autoReplyIdleSeconds = idleSeconds;
                                _autoReplyGoal = goal;
                                _autoReplyPrompt = prompt;
                                _autoReplyContext = aiContext;
                                _autoReplyBoundaries = boundaries;
                                _autoReplyDelaySeconds = delaySeconds;
                                _autoReplyLoading = false;
                              });
                            }

                            Navigator.of(sheetContext).pop();
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: FenyvoPalette.blue,
                            foregroundColor: FenyvoPalette.ink,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          icon: const Icon(Icons.save_rounded),
                          label: Text(
                            _chatText('saveGoalAndStart'),
                            style: const TextStyle(fontWeight: FontWeight.w900),
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

    goalController.dispose();
    promptController.dispose();
    contextController.dispose();
    boundariesController.dispose();
  }

  Future<void> _editMessage(Map<String, dynamic> message) async {
    if (_isVoiceMessage(message)) {
      return;
    }

    final currentUser = SocketService.instance.currentUser ?? '';
    final messageFrom = message['from']?.toString().trim() ?? '';
    final messageId = _getMessageId(message);
    final oldText = message['text']?.toString().trim() ?? '';
    final forwardedFrom = message['forwardedFrom']?.toString().trim() ?? '';

    if (currentUser.isEmpty ||
        messageFrom != currentUser ||
        messageId.isEmpty ||
        oldText.isEmpty ||
        forwardedFrom.isNotEmpty) {
      return;
    }

    if (!SocketService.instance.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '\u0414\u043B\u044F \u0440\u0435\u0434\u0430\u043A\u0442\u0438\u0440\u043E\u0432\u0430\u043D\u0438\u044F \u043D\u0443\u0436\u0435\u043D \u0438\u043D\u0442\u0435\u0440\u043D\u0435\u0442',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final controller = TextEditingController(text: oldText);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );

    if (!mounted) {
      controller.dispose();
      return;
    }

    final newText = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        var canSave = false;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final keyboardHeight = MediaQuery.viewInsetsOf(sheetContext).bottom;

            return AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: keyboardHeight),
              child: SafeArea(
                top: false,
                child: Container(
                  decoration: const BoxDecoration(
                    color: FenyvoPalette.surface,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: FenyvoPalette.line,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Row(
                        children: [
                          Icon(Icons.edit_rounded, color: _gold),
                          SizedBox(width: 10),
                          Text(
                            '\u0418\u0437\u043C\u0435\u043D\u0438\u0442\u044C \u0441\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u0435',
                            style: TextStyle(
                              color: FenyvoPalette.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
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
                        textCapitalization: TextCapitalization.sentences,
                        style: const TextStyle(
                          color: FenyvoPalette.ink,
                          fontSize: 16,
                        ),
                        cursorColor: _gold,
                        onChanged: (value) {
                          final next = value.trim();
                          final enabled = next.isNotEmpty && next != oldText;

                          if (enabled != canSave) {
                            setSheetState(() {
                              canSave = enabled;
                            });
                          }
                        },
                        decoration: InputDecoration(
                          hintText: '\u0422\u0435\u043A\u0441\u0442 \u0441\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u044F',
                          hintStyle: const TextStyle(
                            color: FenyvoPalette.muted,
                          ),
                          counterStyle: const TextStyle(
                            color: FenyvoPalette.muted,
                          ),
                          filled: true,
                          fillColor: FenyvoPalette.surface,
                          prefixIcon: const Icon(
                            Icons.chat_bubble_outline_rounded,
                            color: _gold,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: _gold.withValues(alpha: 0.45),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
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
                                  Navigator.of(sheetContext)
                                      .pop(controller.text.trim());
                                }
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: FenyvoPalette.blue,
                            foregroundColor: FenyvoPalette.ink,
                            disabledBackgroundColor: FenyvoPalette.surface,
                            disabledForegroundColor: FenyvoPalette.muted,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text(
                            '\u0421\u043E\u0445\u0440\u0430\u043D\u0438\u0442\u044C',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
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

    if (editedText.isEmpty || editedText == oldText) {
      return;
    }

    SocketService.instance.editMessage(
      messageId: messageId,
      to: widget.targetUser,
      newText: editedText,
    );
  }

  Future<void> _deleteMessageForMe(Map<String, dynamic> message) async {
    final messageId = _getMessageId(message);

    if (messageId.isEmpty || !mounted) {
      return;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: FenyvoPalette.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: FenyvoPalette.line,
                    borderRadius: BorderRadius.circular(3),
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
                        '\u0423\u0434\u0430\u043B\u0438\u0442\u044C \u0441\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u0435?',
                        style: TextStyle(
                          color: FenyvoPalette.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '\u041E\u043D\u043E \u0438\u0441\u0447\u0435\u0437\u043D\u0435\u0442 \u0442\u043E\u043B\u044C\u043A\u043E \u0443 \u0432\u0430\u0441. \u0423 \u0441\u043E\u0431\u0435\u0441\u0435\u0434\u043D\u0438\u043A\u0430 \u0441\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u0435 \u043E\u0441\u0442\u0430\u043D\u0435\u0442\u0441\u044F.',
                    style: TextStyle(
                      color: FenyvoPalette.secondary,
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
                          Navigator.of(sheetContext).pop(false);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: FenyvoPalette.ink,
                          side: BorderSide(
                            color: _gold.withValues(alpha: 0.55),
                          ),
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          '\u041E\u0442\u043C\u0435\u043D\u0430',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop(true);
                        },
                        icon: const Icon(Icons.delete_rounded),
                        label: const Text(
                          '\u0423\u0434\u0430\u043B\u0438\u0442\u044C \u0443 \u0441\u0435\u0431\u044F',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF4D4D),
                          foregroundColor: FenyvoPalette.ink,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
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

      _messages.removeWhere((item) => _getMessageId(item) == messageId);

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

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          '\u0421\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u0435 \u0443\u0434\u0430\u043B\u0435\u043D\u043E \u0443 \u0432\u0430\u0441',
        ),
        backgroundColor: FenyvoPalette.surface,
        duration: Duration(milliseconds: 1100),
      ),
    );
  }

  Future<void> _deleteMessageForEveryone(Map<String, dynamic> message) async {
    final currentUser = SocketService.instance.currentUser ?? '';

    final messageId = _getMessageId(message);

    final from = message['from']?.toString().trim() ?? '';

    if (currentUser.isEmpty ||
        messageId.isEmpty ||
        from != currentUser ||
        !mounted) {
      return;
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            decoration: BoxDecoration(
              color: FenyvoPalette.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border.all(
                color: _gold.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: FenyvoPalette.line,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  children: [
                    Icon(
                      Icons.delete_sweep_rounded,
                      color: Color(0xFFFF5C5C),
                      size: 26,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '\u0423\u0434\u0430\u043B\u0438\u0442\u044C \u0431\u0435\u0437 \u0441\u043B\u0435\u0434\u043E\u0432?',
                        style: TextStyle(
                          color: FenyvoPalette.ink,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '\u0421\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u0435 \u0438\u0441\u0447\u0435\u0437\u043D\u0435\u0442 \u0443 \u0432\u0430\u0441 \u0438 \u0443 ${widget.targetUser}. \u0412\u043E\u0441\u0441\u0442\u0430\u043D\u043E\u0432\u0438\u0442\u044C \u0435\u0433\u043E \u0431\u0443\u0434\u0435\u0442 \u043D\u0435\u043B\u044C\u0437\u044F.',
                    style: const TextStyle(
                      color: FenyvoPalette.secondary,
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
                          Navigator.of(sheetContext).pop(false);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: FenyvoPalette.ink,
                          side: BorderSide(
                            color: _gold.withValues(alpha: 0.55),
                          ),
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          '\u041E\u0442\u043C\u0435\u043D\u0430',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(sheetContext).pop(true);
                        },
                        icon: const Icon(Icons.delete_forever_rounded),
                        label: const Text(
                          '\u0423\u0434\u0430\u043B\u0438\u0442\u044C \u0434\u043B\u044F \u0432\u0441\u0435\u0445',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF4D4D),
                          foregroundColor: FenyvoPalette.ink,
                          minimumSize: const Size(0, 48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
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

    SocketService.instance.deleteMessageForEveryone(
      messageId: messageId,
      to: widget.targetUser,
    );

    _focusMessageComposer();
  }

  Future<void> _sendForwardedMessage({
    required Map<String, dynamic> message,
    required List<String> recipients,
    required String forwardedFrom,
    required String comment,
  }) async {
    final type = _privateMessageType(message);
    final text = message['text']?.toString().trim() ?? '';

    if (type == 'text') {
      for (final user in recipients) {
        SocketService.instance.sendMessage(
          user,
          text,
          forwardedFrom: forwardedFrom,
          forwardComment: comment,
        );
      }
    } else {
      if (!MediaTransferService.isReady) {
        _privateMediaSnack('Медиа-сервер не готов. Перезайдите в аккаунт.');
        return;
      }

      if (mounted) {
        setState(() => _sendingPrivateMedia = true);
      }

      try {
        var prepared = Map<String, dynamic>.from(message);
        var path = MediaCacheService.existingLocalPath(prepared);
        if (path == null) {
          prepared = MediaCacheService.hasRemoteMedia(prepared)
              ? await MediaCacheService.cacheRemoteMedia(prepared)
              : await MediaCacheService.cacheEmbeddedMedia(prepared);
          path = MediaCacheService.existingLocalPath(prepared);
        }
        if (path == null) {
          throw StateError('Вложение недоступно');
        }

        final fileName = _privateSafeFileName(_privateAttachmentName(prepared));
        final fallbackMime = type == 'image'
            ? 'image/jpeg'
            : type == 'video'
            ? 'video/mp4'
            : type == 'voice'
            ? 'audio/mp4'
            : 'application/octet-stream';
        final mimeType =
            prepared['mimeType']?.toString().trim().isNotEmpty == true
            ? prepared['mimeType'].toString().trim()
            : (prepared['voiceMimeType']?.toString().trim().isNotEmpty == true
                  ? prepared['voiceMimeType'].toString().trim()
                  : _privateMimeFromName(fileName, fallbackMime));
        final maxBytes = type == 'video'
            ? 1024 * 1024 * 1024
            : type == 'file'
            ? 512 * 1024 * 1024
            : 20 * 1024 * 1024;
        for (final user in recipients) {
          final upload = await MediaTransferService.uploadFile(
            path: path,
            fileName: fileName,
            mimeType: mimeType,
            messageType: type,
            maxBytes: maxBytes,
            encryptForE2ee: SocketService.instance.isE2eeActiveWith(user),
          );
          if (type == 'voice') {
            final rawDuration =
                int.tryParse(prepared['voiceDurationMs']?.toString() ?? '') ??
                0;
            SocketService.instance.sendVoiceMessage(
              user,
              mediaId: upload.mediaId,
              fileName: upload.fileName,
              fileSize: upload.fileSize,
              mimeType: upload.mimeType,
              durationMs: rawDuration > 0 ? rawDuration : 1000,
              forwardedFrom: forwardedFrom,
              forwardComment: comment,
              e2eeMedia: upload.e2eeMedia,
            );
          } else {
            SocketService.instance.sendMediaMessage(
              user,
              messageType: type,
              mediaId: upload.mediaId,
              fileName: upload.fileName,
              fileSize: upload.fileSize,
              mimeType: upload.mimeType,
              text: text,
              forwardedFrom: forwardedFrom,
              forwardComment: comment,
              e2eeMedia: upload.e2eeMedia,
            );
          }
        }
      } catch (error) {
        _privateMediaSnack('Не удалось переслать: $error');
        return;
      } finally {
        if (mounted) {
          setState(() => _sendingPrivateMedia = false);
        }
      }
    }

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          recipients.length == 1
              ? 'Сообщение переслано'
              : 'Отправлено получателям: ${recipients.length}',
        ),
        backgroundColor: FenyvoPalette.surface,
      ),
    );
  }

  Future<void> _forwardMessage(Map<String, dynamic> message) async {
    final currentUser = SocketService.instance.currentUser ?? '';

    final messageType = _privateMessageType(message);
    final rawText = message['text']?.toString().trim() ?? '';
    final text = rawText.isNotEmpty
        ? rawText
        : messageType == 'voice'
        ? '🎤 Голосовое сообщение'
        : messageType == 'image'
        ? '📷 Фото'
        : messageType == 'video'
        ? '🎥 Видео'
        : messageType == 'file'
        ? '📎 ${_privateAttachmentName(message)}'
        : '';

    if (currentUser.isEmpty || (messageType == 'text' && text.isEmpty)) {
      return;
    }

    final users = StorageService.getChatUsers(currentUser)
      ..removeWhere((user) => user.trim().isEmpty || user == currentUser)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (users.isEmpty) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '\u041D\u0435\u0442 \u0434\u0440\u0443\u0433\u0438\u0445 \u0447\u0430\u0442\u043E\u0432 \u0434\u043B\u044F \u043F\u0435\u0440\u0435\u0441\u044B\u043B\u043A\u0438',
          ),
          backgroundColor: FenyvoPalette.surface,
        ),
      );

      return;
    }

    final forwardedFrom =
        message['forwardedFrom']?.toString().trim().isNotEmpty == true
        ? message['forwardedFrom'].toString().trim()
        : message['from']?.toString().trim() ?? currentUser;

    final commentController = TextEditingController();

    final searchController = TextEditingController();

    final selectedUsers = <String>{};
    var searchQuery = '';

    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filteredUsers = users
                .where((user) => user.toLowerCase().contains(searchQuery))
                .toList();

            final keyboardHeight = MediaQuery.viewInsetsOf(sheetContext).bottom;

            final screenHeight = MediaQuery.sizeOf(sheetContext).height;

            return AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: keyboardHeight),
              child: SafeArea(
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: (screenHeight - keyboardHeight) * 0.92,
                  ),
                  decoration: const BoxDecoration(
                    color: FenyvoPalette.surface,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: FenyvoPalette.line,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.fromLTRB(18, 16, 18, 12),
                        child: Row(
                          children: [
                            Icon(Icons.forward_rounded, color: _gold),
                            SizedBox(width: 10),
                            Text(
                              '\u041F\u0435\u0440\u0435\u0441\u043B\u0430\u0442\u044C \u0441\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u0435',
                              style: TextStyle(
                                color: FenyvoPalette.ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0x33171B20)),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: TextField(
                          controller: searchController,
                          onChanged: (value) {
                            setSheetState(() {
                              searchQuery = value.trim().toLowerCase();
                            });
                          },
                          style: const TextStyle(color: FenyvoPalette.ink),
                          decoration: InputDecoration(
                            hintText: '\u041F\u043E\u0438\u0441\u043A \u043A\u043E\u043D\u0442\u0430\u043A\u0442\u0430',
                            hintStyle: const TextStyle(
                              color: FenyvoPalette.muted,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: _gold,
                            ),
                            suffixIcon: searchQuery.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      searchController.clear();
                                      setSheetState(() {
                                        searchQuery = '';
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.close,
                                      color: FenyvoPalette.secondary,
                                    ),
                                  ),
                            filled: true,
                            fillColor: FenyvoPalette.surface,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
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
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            children: selectedUsers
                                .map(
                                  (user) => Padding(
                                    padding: const EdgeInsets.only(right: 7),
                                    child: InputChip(
                                      label: Text(user),
                                      labelStyle: const TextStyle(
                                        color: FenyvoPalette.ink,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      backgroundColor: FenyvoPalette.blue,
                                      deleteIconColor: Colors.black,
                                      side: BorderSide.none,
                                      onDeleted: () {
                                        setSheetState(() {
                                          selectedUsers.remove(user);
                                        });
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
                          itemCount: filteredUsers.length,
                          itemBuilder: (context, index) {
                            final user = filteredUsers[index];
                            final avatar = StorageService.getAvatar(user);
                            ImageProvider? imageProvider;

                            if (avatar != null && avatar.isNotEmpty) {
                              try {
                                imageProvider = MemoryImage(
                                  base64Decode(avatar),
                                );
                              } catch (_) {
                                imageProvider = null;
                              }
                            }

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: FenyvoPalette.surface,
                                backgroundImage: imageProvider,
                                child: imageProvider == null
                                    ? Text(
                                        user.isEmpty
                                            ? '?'
                                            : user[0].toUpperCase(),
                                        style: const TextStyle(
                                          color: _gold,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : null,
                              ),
                              title: Text(
                                user,
                                style: const TextStyle(
                                  color: FenyvoPalette.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              trailing: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                width: 27,
                                height: 27,
                                decoration: BoxDecoration(
                                  color: selectedUsers.contains(user)
                                      ? FenyvoPalette.blue
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: _gold, width: 1.3),
                                ),
                                child: selectedUsers.contains(user)
                                    ? const Icon(
                                        Icons.check,
                                        color: FenyvoPalette.ink,
                                        size: 18,
                                      )
                                    : null,
                              ),
                              onTap: () {
                                setSheetState(() {
                                  if (!selectedUsers.add(user)) {
                                    selectedUsers.remove(user);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const Divider(height: 1, color: Color(0x33171B20)),
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: FenyvoPalette.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _gold.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '\u21AA \u041F\u0435\u0440\u0435\u0441\u043B\u0430\u043D\u043E \u043E\u0442 $forwardedFrom',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _gold,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: FenyvoPalette.secondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: commentController,
                          minLines: 1,
                          maxLines: 3,
                          style: const TextStyle(color: FenyvoPalette.ink),
                          decoration: InputDecoration(
                            hintText: '\u0414\u043E\u0431\u0430\u0432\u0438\u0442\u044C \u043A\u043E\u043C\u043C\u0435\u043D\u0442\u0430\u0440\u0438\u0439\u2026',
                            hintStyle: const TextStyle(
                              color: FenyvoPalette.muted,
                            ),
                            prefixIcon: const Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: _gold,
                            ),
                            filled: true,
                            fillColor: FenyvoPalette.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: _gold,
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: selectedUsers.isEmpty
                                ? null
                                : () {
                                    final comment = commentController.text
                                        .trim();
                                    final recipients = selectedUsers.toList();

                                    Navigator.of(sheetContext).pop();

                                    unawaited(
                                      _sendForwardedMessage(
                                        message: message,
                                        recipients: recipients,
                                        forwardedFrom: forwardedFrom,
                                        comment: comment,
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.send_rounded),
                            label: Text(
                              selectedUsers.isEmpty
                                  ? '\u0412\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u043F\u043E\u043B\u0443\u0447\u0430\u0442\u0435\u043B\u044F'
                                  : selectedUsers.length == 1
                                  ? '\u041E\u0442\u043F\u0440\u0430\u0432\u0438\u0442\u044C'
                                  : '\u041E\u0442\u043F\u0440\u0430\u0432\u0438\u0442\u044C (${selectedUsers.length})',
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: FenyvoPalette.blue,
                              foregroundColor: FenyvoPalette.ink,
                              disabledBackgroundColor: FenyvoPalette.surface,
                              disabledForegroundColor: FenyvoPalette.muted,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
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
  // \u041A\u041E\u041C\u041F\u0410\u041A\u0422\u041D\u0410\u042F \u041A\u041D\u041E\u041F\u041A\u0410 \u0420\u0415\u0410\u041A\u0426\u0418\u0418
  // ========================================

  Widget _buildQuickReactionButton({
    String? emoji,
    IconData? icon,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        child: icon != null
            ? Icon(icon, color: iconColor ?? FenyvoPalette.ink, size: 26)
            : Text(emoji ?? '', style: const TextStyle(fontSize: 24)),
      ),
    );
  }

  // ========================================
  // \u041F\u041E\u041B\u041D\u042B\u0419 \u0412\u042B\u0411\u041E\u0420 \u0420\u0415\u0410\u041A\u0426\u0418\u0419
  // ========================================

  Future<void> _showReactionPicker(Map<String, dynamic> message) async {
    if (!mounted) return;

    final currentUser = SocketService.instance.currentUser ?? '';
    final selectedReaction = currentUser.isEmpty
        ? ''
        : _getMessageReactions(message)[currentUser] ?? '';

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final sheetHeight = MediaQuery.sizeOf(sheetContext).height * 0.50;

        return SafeArea(
          top: false,
          child: Container(
            height: sheetHeight,
            decoration: const BoxDecoration(
              color: FenyvoPalette.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: _gold, width: 1.2)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: FenyvoPalette.line,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 14),
                const Row(
                  children: [
                    Icon(Icons.emoji_emotions_outlined, color: _gold),
                    SizedBox(width: 10),
                    Text(
                      '\u0412\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u0440\u0435\u0430\u043A\u0446\u0438\u044E',
                      style: TextStyle(
                        color: FenyvoPalette.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: GridView.builder(
                    itemCount: _supportedReactions.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                    itemBuilder: (context, index) {
                      final reaction = _supportedReactions[index];
                      final selected = reaction == selectedReaction;
                      return InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          Future<void>.delayed(
                            const Duration(milliseconds: 60),
                            () {
                              if (!mounted) return;
                              _sendReaction(message, reaction);
                            },
                          );
                        },
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? FenyvoPalette.blue.withValues(alpha: 0.20)
                                : FenyvoPalette.surface.withValues(
                                    alpha: 0.42,
                                  ),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _gold.withValues(
                                alpha: selected ? 1.0 : 0.45,
                              ),
                            ),
                          ),
                          child: Text(
                            reaction,
                            style: const TextStyle(fontSize: 28),
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
    );
  }
  // ========================================
  // \u041A\u041E\u041C\u041F\u0410\u041A\u0422\u041D\u0410\u042F \u0421\u0422\u0420\u041E\u041A\u0410 \u041C\u0415\u041D\u042E
  // ========================================

  Widget _buildMessageMenuItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final color = danger ? const Color(0xFFFF4D4D) : FenyvoPalette.ink;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 37,
              child: Icon(
                icon,
                color: danger ? const Color(0xFFFF4D4D) : _gold,
                size: 22,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: danger
                            ? const Color(0xFFFF6A6A)
                            : _gold.withValues(alpha: 0.78),
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

  PopupMenuItem<String> _buildDesktopMessageContextItem({
    required String value,
    required IconData icon,
    required String label,
    bool danger = false,
  }) {
    final itemColor = danger ? const Color(0xFFFF6262) : FenyvoPalette.ink;

    return PopupMenuItem<String>(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(icon, size: 18, color: danger ? const Color(0xFFFF6262) : _gold),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: itemColor,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDesktopMessageContextMenu(
    Map<String, dynamic> message,
    Offset globalPosition,
  ) async {
    if (!mounted || !Platform.isWindows) {
      return;
    }

    final overlayState = Overlay.of(context);

    final overlayObject = overlayState.context.findRenderObject();

    if (overlayObject is! RenderBox) {
      return;
    }

    final localPosition = overlayObject.globalToLocal(globalPosition);

    final isMe = message['isMe'] == true;

    final isE2ee = message['e2ee'] == true;

    final forwardedFrom = message['forwardedFrom']?.toString().trim() ?? '';

    final isPinned = _isMessagePinned(message);

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        localPosition.dx,
        localPosition.dy,
        overlayObject.size.width - localPosition.dx,
        overlayObject.size.height - localPosition.dy,
      ),
      color: FenyvoPalette.surface,
      elevation: 14,
      shadowColor: Colors.black.withValues(alpha: 0.72),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: _gold.withValues(alpha: 0.34), width: 0.8),
      ),
      items: [
        _buildDesktopMessageContextItem(
          value: 'save',
          icon: Icons.bookmark_add_outlined,
          label: _chatText('save'),
        ),
        _buildDesktopMessageContextItem(
          value: 'reply',
          icon: Icons.reply_rounded,
          label: _chatText('reply'),
        ),
        _buildDesktopMessageContextItem(
          value: 'copy',
          icon: Icons.copy_rounded,
          label: _chatText('copy'),
        ),
        _buildDesktopMessageContextItem(
          value: 'forward',
          icon: Icons.forward_rounded,
          label: _chatText('forward'),
        ),
        if (isMe && forwardedFrom.isEmpty && !isE2ee)
          _buildDesktopMessageContextItem(
            value: 'edit',
            icon: Icons.edit_rounded,
            label: _chatText('edit'),
          ),
        const PopupMenuDivider(height: 8),
        _buildDesktopMessageContextItem(
          value: 'heart',
          icon: Icons.favorite_rounded,
          label: '${_chatText('reaction')} ❤️',
        ),
        if (!isE2ee)
          _buildDesktopMessageContextItem(
            value: 'translate',
            icon: Icons.translate_rounded,
            label: _chatText('translate'),
          ),
        if (!isE2ee)
          _buildDesktopMessageContextItem(
            value: 'chatgpt',
            icon: Icons.auto_awesome_rounded,
            label: 'ChatGPT',
          ),
        _buildDesktopMessageContextItem(
          value: 'pin',
          icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
          label: isPinned ? _chatText('unpin') : _chatText('pin'),
        ),
        const PopupMenuDivider(height: 8),
        if (isMe)
          _buildDesktopMessageContextItem(
            value: 'delete_everyone',
            icon: Icons.delete_sweep_rounded,
            label: _chatText('deleteForEveryone'),
            danger: true,
          ),
        _buildDesktopMessageContextItem(
          value: 'delete_me',
          icon: Icons.delete_rounded,
          label: _chatText('delete'),
          danger: true,
        ),
      ],
    );

    if (!mounted || result == null) {
      return;
    }

    switch (result) {
      case 'save':
        unawaited(_saveToSaved(message));
        break;
      case 'reply':
        _startReply(message);
        break;

      case 'copy':
        unawaited(_copyMessageText(message));
        break;

      case 'forward':
        unawaited(_forwardMessage(message));
        break;

      case 'edit':
        unawaited(_editMessage(message));
        break;

      case 'heart':
        _sendReaction(message, '\u2764\uFE0F');
        break;

      case 'translate':
        unawaited(_translateMessage(message));
        break;

      case 'chatgpt':
        unawaited(_showChatGptSheet(message));
        break;

      case 'pin':
        _togglePinnedMessage(message);
        break;

      case 'delete_everyone':
        unawaited(_deleteMessageForEveryone(message));
        break;

      case 'delete_me':
        unawaited(_deleteMessageForMe(message));
        break;
    }
  }

  Future<void> _saveToSaved(Map<String, dynamic> message) async {
    try {
      await SavedMessagesService.save(
        SocketService.instance.currentUser ?? '',
        {
          ...message,
          'messageType': _isVoiceMessage(message)
              ? 'voice'
              : _privateMessageType(message),
        },
        origin: widget.targetUser,
      );
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_chatText('addedToSaved'))));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_chatText('saveMessageError'))));
    }
  }

  Future<void> _showMessageActionMenu(Map<String, dynamic> message) async {
    final isMe = message['isMe'] == true;

    final isE2ee = message['e2ee'] == true;

    final isPinned = _isMessagePinned(message);

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: '\u0417\u0430\u043A\u0440\u044B\u0442\u044C \u043C\u0435\u043D\u044E \u0441\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u044F',
      barrierColor: Colors.black.withValues(alpha: 0.70),
      transitionDuration: const Duration(milliseconds: 170),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final screenWidth = MediaQuery.of(dialogContext).size.width;

        final screenHeight = MediaQuery.of(dialogContext).size.height;

        final menuWidth = screenWidth > 440 ? 360.0 : screenWidth - 46;

        void closeAndRun(VoidCallback action) {
          Navigator.of(dialogContext).pop();

          Future<void>.delayed(const Duration(milliseconds: 80), action);
        }

        return SafeArea(
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: menuWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // =================================
                    // \u041A\u041E\u041C\u041F\u0410\u041A\u0422\u041D\u0410\u042F \u041F\u0410\u041D\u0415\u041B\u042C \u0420\u0415\u0410\u041A\u0426\u0418\u0419
                    // =================================
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: FenyvoPalette.surface,
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(
                          color: _gold.withValues(alpha: 0.95),
                          width: 1.1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _gold.withValues(alpha: 0.06),
                            blurRadius: 13,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildQuickReactionButton(
                            icon: Icons.favorite,
                            iconColor: _gold,
                            onTap: () {
                              closeAndRun(() {
                                _sendReaction(message, '\u2764\uFE0F');
                              });
                            },
                          ),
                          _buildQuickReactionButton(
                            emoji: '\u{1F602}',
                            onTap: () {
                              closeAndRun(() {
                                _sendReaction(message, '\u{1F602}');
                              });
                            },
                          ),
                          _buildQuickReactionButton(
                            emoji: '\u{1F62E}',
                            onTap: () {
                              closeAndRun(() {
                                _sendReaction(message, '\u{1F62E}');
                              });
                            },
                          ),
                          _buildQuickReactionButton(
                            emoji: '\u{1F622}',
                            onTap: () {
                              closeAndRun(() {
                                _sendReaction(message, '\u{1F622}');
                              });
                            },
                          ),
                          _buildQuickReactionButton(
                            emoji: '\u{1F621}',
                            onTap: () {
                              closeAndRun(() {
                                _sendReaction(message, '\u{1F621}');
                              });
                            },
                          ),
                          _buildQuickReactionButton(
                            emoji: '\u{1F44D}',
                            onTap: () {
                              closeAndRun(() {
                                _sendReaction(message, '\u{1F44D}');
                              });
                            },
                          ),
                          _buildQuickReactionButton(
                            icon: Icons.add_circle_outline,
                            iconColor: _gold,
                            onTap: () {
                              closeAndRun(() {
                                _showReactionPicker(message);
                              });
                            },
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 8),

                    // =================================
                    // \u041A\u041E\u041C\u041F\u0410\u041A\u0422\u041D\u041E\u0415 \u041E\u0421\u041D\u041E\u0412\u041D\u041E\u0415 \u041C\u0415\u041D\u042E
                    // =================================
                    Container(
                      constraints: BoxConstraints(
                        maxHeight: screenHeight * 0.60,
                      ),
                      decoration: BoxDecoration(
                        color: FenyvoPalette.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: _gold.withValues(alpha: 0.95),
                          width: 1.1,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 18,
                            spreadRadius: 1,
                          ),
                          BoxShadow(
                            color: _gold.withValues(alpha: 0.06),
                            blurRadius: 12,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildMessageMenuItem(
                              icon: Icons.bookmark_add_outlined,
                              title: _chatText('save'),
                              subtitle: _chatText('localCopy'),
                              onTap: () {
                                closeAndRun(
                                  () => unawaited(_saveToSaved(message)),
                                );
                              },
                            ),
                            _buildMessageMenuItem(
                              icon: Icons.reply_rounded,
                              title: _chatText('reply'),
                              subtitle: _chatText('replySubtitle'),
                              onTap: () {
                                closeAndRun(() {
                                  _startReply(message);
                                });
                              },
                            ),

                            Divider(
                              height: 1,
                              thickness: 0.6,
                              color: _gold.withValues(alpha: 0.15),
                            ),

                            _buildMessageMenuItem(
                              icon: Icons.copy_rounded,
                              title: _chatText('copy'),
                              subtitle: _chatText('copySubtitle'),
                              onTap: () {
                                Navigator.of(dialogContext).pop();

                                unawaited(_copyMessageText(message));
                              },
                            ),

                            Divider(
                              height: 1,
                              thickness: 0.6,
                              color: _gold.withValues(alpha: 0.15),
                            ),

                            _buildMessageMenuItem(
                              icon: Icons.forward_rounded,
                              title: _chatText('forward'),
                              subtitle: _chatText('forwardSubtitle'),
                              onTap: () {
                                closeAndRun(() {
                                  unawaited(_forwardMessage(message));
                                });
                              },
                            ),

                            if (isMe &&
                                !isE2ee &&
                                (message['forwardedFrom']
                                        ?.toString()
                                        .trim()
                                        .isEmpty ??
                                    true)) ...[
                              Divider(
                                height: 1,
                                thickness: 0.6,
                                color: _gold.withValues(alpha: 0.15),
                              ),
                              _buildMessageMenuItem(
                                icon: Icons.edit_rounded,
                                title: _chatText('edit'),
                                subtitle: _chatText('editSubtitle'),
                                onTap: () {
                                  closeAndRun(() {
                                    unawaited(_editMessage(message));
                                  });
                                },
                              ),
                            ],

                            if (!isE2ee) ...[
                              Divider(
                                height: 1,
                                thickness: 0.6,
                                color: _gold.withValues(alpha: 0.15),
                              ),

                              _buildMessageMenuItem(
                                icon: Icons.translate_rounded,
                                title: _chatText('translate'),
                                subtitle: _chatText('translateSubtitle'),
                                onTap: () {
                                  Navigator.of(dialogContext).pop();

                                  Future<void>.delayed(
                                    const Duration(milliseconds: 320),
                                    () {
                                      if (!mounted) {
                                        return;
                                      }

                                      unawaited(_translateMessage(message));
                                    },
                                  );
                                },
                              ),

                              Divider(
                                height: 1,
                                thickness: 0.6,
                                color: _gold.withValues(alpha: 0.15),
                              ),

                              _buildMessageMenuItem(
                                icon: Icons.auto_awesome_rounded,
                                title: 'ChatGPT',
                                subtitle: _chatText('chatGptSubtitle'),
                                onTap: () {
                                  Navigator.of(dialogContext).pop();

                                  Future<void>.delayed(
                                    const Duration(milliseconds: 320),
                                    () {
                                      if (!mounted) {
                                        return;
                                      }

                                      unawaited(_showChatGptSheet(message));
                                    },
                                  );
                                },
                              ),
                            ],

                            Divider(
                              height: 1,
                              thickness: 0.6,
                              color: _gold.withValues(alpha: 0.15),
                            ),

                            _buildMessageMenuItem(
                              icon: isPinned
                                  ? Icons.push_pin_outlined
                                  : Icons.push_pin_rounded,
                              title: isPinned
                                  ? _chatText('unpin')
                                  : _chatText('pin'),
                              subtitle: isPinned
                                  ? _chatText('unpinSubtitle')
                                  : _chatText('pinSubtitle'),
                              onTap: () {
                                closeAndRun(() {
                                  _togglePinnedMessage(message);
                                });
                              },
                            ),

                            if (isMe) ...[
                              Divider(
                                height: 1,
                                thickness: 0.6,
                                color: _gold.withValues(alpha: 0.15),
                              ),
                              _buildMessageMenuItem(
                                icon: Icons.delete_sweep_rounded,
                                title: _chatText('deleteForEveryone'),
                                subtitle: _chatText(
                                  'deleteForEveryoneSubtitle',
                                ),
                                danger: true,
                                onTap: () {
                                  closeAndRun(() {
                                    unawaited(
                                      _deleteMessageForEveryone(message),
                                    );
                                  });
                                },
                              ),
                            ],

                            Divider(
                              height: 1,
                              thickness: 0.6,
                              color: const Color(0xFFFF4D4D)
                                  .withValues(alpha: 0.16),
                            ),

                            _buildMessageMenuItem(
                              icon: Icons.delete_rounded,
                              title: _chatText('delete'),
                              subtitle: _chatText('deleteMessageSubtitle'),
                              danger: true,
                              onTap: () {
                                closeAndRun(() {
                                  unawaited(_deleteMessageForMe(message));
                                });
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
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
        );

        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(curved),
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
    final foreground = isMe
        ? FenyvoPalette.secondary
        : _gold.withValues(alpha: 0.88);

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isMe
                  ? FenyvoPalette.surface.withValues(alpha: 0.075)
                  : FenyvoPalette.blue.withValues(alpha: 0.075),
              border: Border.all(
                color: isMe
                    ? FenyvoPalette.ink.withValues(alpha: 0.14)
                    : _gold.withValues(alpha: 0.16),
                width: 0.7,
              ),
            ),
            child: Icon(icon, size: 14, color: foreground),
          ),
        ),
      ),
    );
  }

  // ========================================
  // \u041E\u0414\u041D\u041E \u0421\u041E\u041E\u0411\u0429\u0415\u041D\u0418\u0415
  // ========================================

  Widget _buildSharedContactCard(
    Map<String, dynamic> contact, {
    required bool isMe,
  }) {
    final username = contact['username']?.toString().trim() ?? '';
    final name = contact['name']?.toString().trim() ?? '';
    final title = name.isNotEmpty ? name : username;
    final initial = title.isNotEmpty
        ? title.substring(0, 1).toUpperCase()
        : '?';

    return Container(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMe
            ? FenyvoPalette.surface.withValues(alpha: .18)
            : FenyvoPalette.blue.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMe ? FenyvoPalette.line : _gold.withValues(alpha: .42),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: FenyvoPalette.surfaceRaised,
            child: Text(
              initial,
              style: const TextStyle(
                color: _gold,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: FenyvoPalette.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (username.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '@$username',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: FenyvoPalette.secondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(Icons.person_rounded, color: _gold, size: 22),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    if (message['localCallEntry'] == true) {
      return _buildCallHistoryBubble(message);
    }
    final isMe = message['isMe'] == true;

    final isAiGenerated =
        message['aiGenerated'] == true || message['autoReply'] == true;

    final isE2ee = message['e2ee'] == true;

    final isVoiceMessage = _isVoiceMessage(message);

    final privateMessageType = _privateMessageType(message);

    final isPrivateMediaMessage =
        privateMessageType == 'image' ||
        privateMessageType == 'video' ||
        privateMessageType == 'file';

    final text = message['text']?.toString() ?? '';
    Map<String, dynamic>? sharedContact;
    final rawSharedContact = message['sharedContact'];
    if (rawSharedContact is Map) {
      final parsed = Map<String, dynamic>.from(rawSharedContact);
      if (parsed['username']?.toString().trim().isNotEmpty == true) {
        sharedContact = parsed;
      }
    }

    final from = message['from']?.toString() ?? '';

    final forwardedFrom = message['forwardedFrom']?.toString().trim() ?? '';

    final forwardComment = message['forwardComment']?.toString().trim() ?? '';

    final isWindowsDesktop = Platform.isWindows;

    final messageId = _getMessageId(message);

    final isHovered = isWindowsDesktop && _hoveredMessageId == messageId;

    final showDesktopActions = isHovered;

    final isPinnedHighlight = _highlightedMessageId == messageId;

    final bubbleMaxWidth = isWindowsDesktop
        ? forwardedFrom.isNotEmpty
              ? 520.0
              : 480.0
        : MediaQuery.of(context).size.width * 0.7;

    final timeStr = _formatTime(message['time']);

    final isEdited =
        message['isEdited'] == true ||
        (message['editedAt']?.toString().trim().isNotEmpty ?? false);

    Map<String, dynamic>? replyTo;

    final rawReplyTo = message['replyTo'];

    if (rawReplyTo is Map) {
      replyTo = Map<String, dynamic>.from(rawReplyTo);
    }

    final signalBorder = isPinnedHighlight
        ? BorderSide(color: isMe ? FenyvoPalette.ink : _gold, width: 2)
        : isHovered
        ? BorderSide(
            color: isMe
                ? FenyvoPalette.ink.withValues(alpha: .30)
                : _gold.withValues(alpha: .52),
            width: .9,
          )
        : BorderSide(
            color: isMe
                ? _gold.withValues(alpha: .38)
                : FenyvoPalette.line.withValues(alpha: .88),
            width: .75,
          );
    final signalShape = isWindowsDesktop
        ? RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(isMe ? 18 : 6),
              topRight: Radius.circular(isMe ? 6 : 18),
              bottomLeft: const Radius.circular(18),
              bottomRight: const Radius.circular(18),
            ),
            side: signalBorder,
          )
        : BeveledRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(isMe ? 13 : 5),
              topRight: Radius.circular(isMe ? 5 : 13),
              bottomRight: Radius.circular(isMe ? 13 : 5),
              bottomLeft: Radius.circular(isMe ? 5 : 13),
            ),
            side: signalBorder,
          );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: MouseRegion(
        cursor: isWindowsDesktop ? SystemMouseCursors.basic : MouseCursor.defer,
        onEnter: isWindowsDesktop
            ? (_) {
                if (_hoveredMessageId != messageId) {
                  setState(() {
                    _hoveredMessageId = messageId;
                  });
                }
              }
            : null,
        onExit: isWindowsDesktop
            ? (_) {
                if (_hoveredMessageId == messageId) {
                  setState(() {
                    _hoveredMessageId = null;
                  });
                }
              }
            : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () {
            _showMessageActionMenu(message);
          },
          onDoubleTap: isWindowsDesktop
              ? () {
                  _startReply(message);
                }
              : null,
          onSecondaryTapDown: isWindowsDesktop
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
            padding: EdgeInsets.only(
              top: isWindowsDesktop ? 2 : 4,
              bottom: isWindowsDesktop ? 8 : 18,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
                  decoration: ShapeDecoration(
                    gradient: isMe
                        ? const LinearGradient(
                            colors: [
                              FenyvoPalette.surfaceRaised,
                              FenyvoPalette.blue,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : const LinearGradient(
                            colors: [
                              FenyvoPalette.surfaceSoft,
                              FenyvoPalette.surface,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    shape: signalShape,
                    shadows: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isPinnedHighlight
                              ? 0.10
                              : isHovered
                              ? 0.07
                              : 0.03,
                        ),
                        blurRadius: isPinnedHighlight
                            ? 14
                            : isHovered
                            ? 9
                            : 4,
                        offset: const Offset(0, 2),
                      ),
                      if (isPinnedHighlight)
                        BoxShadow(
                          color: _gold.withValues(alpha: 0.06),
                          blurRadius: 24,
                          spreadRadius: 1.5,
                        )
                      else if (isHovered)
                        BoxShadow(
                          color: isMe
                              ? _gold.withValues(alpha: 0.06)
                              : _gold.withValues(alpha: 0.06),
                          blurRadius: 14,
                          spreadRadius: -2,
                        ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isMe && from.isNotEmpty && forwardedFrom.isEmpty)
                        Text(
                          from,
                          style: const TextStyle(
                            fontSize: 10,
                            color: _gold,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                      if (!isMe && from.isNotEmpty && forwardedFrom.isEmpty)
                        const SizedBox(height: 2),

                      if (replyTo != null)
                        _buildReplyPreview(replyTo, isMe: isMe),

                      if (forwardedFrom.isNotEmpty) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.forward_rounded,
                              size: 12,
                              color: isMe
                                  ? FenyvoPalette.secondary
                                  : _gold.withValues(alpha: 0.90),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                '\u041F\u0435\u0440\u0435\u0441\u043B\u0430\u043D\u043E \u043E\u0442 $forwardedFrom',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isMe
                                      ? FenyvoPalette.secondary
                                      : _gold.withValues(alpha: 0.90),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                      ],

                      if (sharedContact != null)
                        _buildSharedContactCard(sharedContact, isMe: isMe)
                      else if (isVoiceMessage)
                        _buildVoiceMessagePlayer(message, isMe: isMe)
                      else if (isPrivateMediaMessage)
                        _buildPrivateMediaBody(message, isMe: isMe)
                      else
                        Text(
                          text,
                          style: TextStyle(
                            color: isMe
                                ? FenyvoPalette.ink
                                : FenyvoPalette.ink,
                            fontSize: 16,
                          ),
                        ),

                      if (forwardComment.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Container(
                            height: 0.6,
                            color: isMe
                                ? FenyvoPalette.line
                                : FenyvoPalette.blue.withValues(alpha: 0.22),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 11,
                              color: isMe
                                  ? FenyvoPalette.secondary
                                  : _gold.withValues(alpha: 0.82),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                from.isNotEmpty ? from : 'Комментарий',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isMe
                                      ? FenyvoPalette.secondary
                                      : _gold.withValues(alpha: 0.82),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
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
                                ? FenyvoPalette.ink
                                : FenyvoPalette.ink,
                            fontSize: 14,
                            height: 1.18,
                          ),
                        ),
                      ],

                      if (isWindowsDesktop &&
                          isHovered &&
                          (isVoiceMessage || isPrivateMediaMessage))
                        Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Tooltip(
                              message: 'Переслать медиа',
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () =>
                                    unawaited(_forwardMessage(message)),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? FenyvoPalette.surface.withValues(
                                            alpha: 0.09,
                                          )
                                        : FenyvoPalette.blue.withValues(
                                            alpha: 0.10,
                                          ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isMe
                                          ? FenyvoPalette.line
                                          : _gold.withValues(alpha: 0.42),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.forward_rounded,
                                        size: 16,
                                        color: isMe
                                            ? FenyvoPalette.ink
                                            : _gold,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Переслать',
                                        style: TextStyle(
                                          color: isMe
                                              ? FenyvoPalette.ink
                                              : _gold,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 4),

                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isE2ee) ...[
                            Icon(
                              message['e2eeError'] == true
                                  ? Icons.lock_reset_rounded
                                  : Icons.lock_rounded,
                              size: 10,
                              color: message['e2eeError'] == true
                                  ? Colors.redAccent
                                  : _gold,
                            ),
                            const SizedBox(width: 3),
                          ],
                          if (isAiGenerated) ...[
                            Icon(
                              Icons.smart_toy_rounded,
                              size: 10,
                              color: isMe
                                  ? FenyvoPalette.secondary
                                  : _gold.withValues(alpha: 0.88),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'AI',
                              style: TextStyle(
                                color: isMe
                                    ? FenyvoPalette.secondary
                                    : _gold.withValues(alpha: 0.88),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 5),
                          ],
                          if (timeStr.isNotEmpty)
                            Text(
                              timeStr,
                              style: TextStyle(
                                color: isMe
                                    ? FenyvoPalette.secondary
                                    : FenyvoPalette.secondary,
                                fontSize: 10,
                              ),
                            ),

                          if (isEdited) ...[
                            const SizedBox(width: 4),
                            Text(
                              '\u0438\u0437\u043C\u0435\u043D\u0435\u043D\u043E',
                              style: TextStyle(
                                color: isMe
                                    ? FenyvoPalette.secondary
                                    : FenyvoPalette.muted,
                                fontSize: 9,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],

                          if (isMe) ...[
                            const SizedBox(width: 4),
                            _buildMessageStatus(message),
                          ],

                          if (!isWindowsDesktop &&
                              (isVoiceMessage || isPrivateMediaMessage)) ...[
                            const SizedBox(width: 5),
                            Tooltip(
                              message: 'Переслать',
                              child: InkWell(
                                borderRadius: BorderRadius.circular(15),
                                onTap: () =>
                                    unawaited(_forwardMessage(message)),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.forward_rounded,
                                    size: 17,
                                    color: isMe
                                        ? FenyvoPalette.secondary
                                        : _gold,
                                  ),
                                ),
                              ),
                            ),
                          ],

                          if (isWindowsDesktop) ...[
                            const SizedBox(width: 8),
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 120),
                              curve: Curves.easeOutCubic,
                              opacity: showDesktopActions ? 1.0 : 0.0,
                              child: AnimatedScale(
                                duration: const Duration(milliseconds: 130),
                                curve: Curves.easeOutCubic,
                                scale: showDesktopActions ? 1.0 : 0.90,
                                child: IgnorePointer(
                                  ignoring: !showDesktopActions,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildDesktopQuickMessageAction(
                                        icon: Icons.reply_rounded,
                                        tooltip: '\u041E\u0442\u0432\u0435\u0442\u0438\u0442\u044C',
                                        isMe: isMe,
                                        onTap: () {
                                          _startReply(message);
                                        },
                                      ),
                                      const SizedBox(width: 4),
                                      _buildDesktopQuickMessageAction(
                                        icon: Icons.copy_rounded,
                                        tooltip: '\u041A\u043E\u043F\u0438\u0440\u043E\u0432\u0430\u0442\u044C',
                                        isMe: isMe,
                                        onTap: () {
                                          unawaited(_copyMessageText(message));
                                        },
                                      ),
                                      const SizedBox(width: 4),
                                      _buildDesktopQuickMessageAction(
                                        icon: Icons.forward_rounded,
                                        tooltip: '\u041F\u0435\u0440\u0435\u0441\u043B\u0430\u0442\u044C',
                                        isMe: isMe,
                                        onTap: () {
                                          unawaited(_forwardMessage(message));
                                        },
                                      ),
                                      if (isMe && forwardedFrom.isEmpty) ...[
                                        const SizedBox(width: 4),
                                        _buildDesktopQuickMessageAction(
                                          icon: Icons.edit_rounded,
                                          tooltip: '\u0418\u0437\u043C\u0435\u043D\u0438\u0442\u044C',
                                          isMe: isMe,
                                          onTap: () {
                                            unawaited(_editMessage(message));
                                          },
                                        ),
                                      ],
                                      const SizedBox(width: 4),
                                      _buildDesktopQuickMessageAction(
                                        icon: Icons.favorite_outline_rounded,
                                        tooltip: '\u0420\u0435\u0430\u043A\u0446\u0438\u044F \u2764\uFE0F',
                                        isMe: isMe,
                                        onTap: () {
                                          _sendReaction(
                                            message,
                                            '\u2764\uFE0F',
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

                if (!isMe)
                  Positioned(
                    left: -8,
                    top: 22,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: _gold,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: FenyvoPalette.canvasDeep,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _gold.withValues(alpha: .30),
                            blurRadius: 7,
                          ),
                        ],
                      ),
                    ),
                  ),

                if (isMe && !isWindowsDesktop)
                  Positioned(
                    right: 2,
                    top: 12,
                    bottom: 12,
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: _gold.withValues(alpha: .82),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),

                Positioned(
                  bottom: -15,
                  left: isMe ? -15 : null,
                  right: isMe ? null : -15,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, animation) {
                      return ScaleTransition(
                        scale: CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutBack,
                        ),
                        child: child,
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey<String>(_reactionStateKey(message)),
                      child: _buildReactionRow(message),
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

  Widget _buildCallHistoryBubble(Map<String, dynamic> message) {
    final raw = message['call'];
    final call = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final missed = call['outcome'] == 'missed';
    final incoming = call['incoming'] == true;
    final video = call['video'] == true;
    final accent = missed ? Colors.redAccent : _gold;
    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 14),
        child: Material(
          color: FenyvoPalette.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => unawaited(
              CallService.instance.startCall(
                peer: widget.targetUser,
                video: video,
              ),
            ),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: Platform.isWindows ? 310 : 340,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent.withValues(alpha: 0.42)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    video ? Icons.videocam_rounded : Icons.call_rounded,
                    color: accent,
                  ),
                  const SizedBox(width: 11),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          CallHistoryService.title(call),
                          style: TextStyle(
                            color: missed
                                ? Colors.redAccent
                                : FenyvoPalette.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          CallHistoryService.status(call),
                          style: const TextStyle(
                            color: FenyvoPalette.secondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    incoming
                        ? Icons.call_received_rounded
                        : Icons.call_made_rounded,
                    color: accent,
                    size: 19,
                  ),
                ],
              ),
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

    final shouldShow = _messageScrollController.position.pixels > 180;

    final shouldResetCounter = !shouldShow && _newMessagesWhileScrolledUp > 0;

    if (shouldShow == _showScrollToLatest && !shouldResetCounter) {
      return;
    }

    setState(() {
      _showScrollToLatest = shouldShow;

      if (shouldResetCounter) {
        _newMessagesWhileScrolledUp = 0;
      }
    });
  }

  void _scrollToLatestMessage() {
    if (!_messageScrollController.hasClients) {
      return;
    }

    if (_newMessagesWhileScrolledUp > 0 && mounted) {
      setState(() {
        _newMessagesWhileScrolledUp = 0;
      });
    }

    _messageScrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildScrollToLatestButton() {
    if (!Platform.isWindows) {
      return const SizedBox.shrink();
    }

    return AnimatedSlide(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      offset: _showScrollToLatest ? Offset.zero : const Offset(0, 0.45),
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 160),
        opacity: _showScrollToLatest ? 1 : 0,
        child: IgnorePointer(
          ignoring: !_showScrollToLatest,
          child: Tooltip(
            message: _newMessagesWhileScrolledUp > 0
                ? '\u041D\u043E\u0432\u044B\u0445 \u0441\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u0439: $_newMessagesWhileScrolledUp'
                : '\u041A \u043F\u043E\u0441\u043B\u0435\u0434\u043D\u0438\u043C \u0441\u043E\u043E\u0431\u0449\u0435\u043D\u0438\u044F\u043C',
            waitDuration: const Duration(milliseconds: 350),
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) {
                if (!_scrollToLatestHovered) {
                  setState(() {
                    _scrollToLatestHovered = true;
                  });
                }
              },
              onExit: (_) {
                if (_scrollToLatestHovered) {
                  setState(() {
                    _scrollToLatestHovered = false;
                  });
                }
              },
              child: GestureDetector(
                onTap: _scrollToLatestMessage,
                child: AnimatedScale(
                  duration: const Duration(milliseconds: 130),
                  curve: Curves.easeOutCubic,
                  scale: _scrollToLatestHovered ? 1.08 : 1,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: FenyvoPalette.surface,
                      border: Border.all(
                        color: _gold.withValues(
                          alpha: _scrollToLatestHovered ? 0.72 : 0.40,
                        ),
                        width: 0.9,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                        if (_scrollToLatestHovered)
                          BoxShadow(
                            color: _gold.withValues(alpha: 0.06),
                            blurRadius: 16,
                          ),
                      ],
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      alignment: Alignment.center,
                      children: [
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: _gold,
                          size: 24,
                        ),
                        if (_newMessagesWhileScrolledUp > 0)
                          Positioned(
                            right: -7,
                            top: -7,
                            child: AnimatedScale(
                              duration: const Duration(milliseconds: 150),
                              curve: Curves.easeOutBack,
                              scale: 1,
                              child: Container(
                                constraints: const BoxConstraints(
                                  minWidth: 20,
                                  minHeight: 20,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: FenyvoPalette.blue,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.black.withValues(alpha: 0.72),
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _gold.withValues(alpha: 0.06),
                                      blurRadius: 8,
                                    ),
                                  ],
                                ),
                                child: Text(
                                  _newMessagesWhileScrolledUp > 99
                                      ? '99+'
                                      : '$_newMessagesWhileScrolledUp',
                                  style: const TextStyle(
                                    color: FenyvoPalette.ink,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
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
  // \u0421\u041F\u0418\u0421\u041E\u041A \u0421\u041E\u041E\u0411\u0429\u0415\u041D\u0418\u0419
  // ========================================

  ({ShieldAssessment assessment, String fingerprint})? _latestShieldFinding() {
    for (final message in _messages.reversed) {
      if (message['isMe'] == true) continue;
      final text = message['text']?.toString() ?? '';
      if (text.trim().isEmpty) continue;
      final assessment = FenyvoShieldService.assess(text);
      if (assessment == null) return null;
      final fingerprint = [
        message['id'],
        message['timestamp'],
        message['time'],
        text,
      ].join('|');
      return (assessment: assessment, fingerprint: fingerprint);
    }
    return null;
  }

  Future<void> _loadTrustState() async {
    final results = await Future.wait<bool>([
      FenyvoTrustService.isTrusted(widget.targetUser),
      FenyvoTrustService.isBlocked(widget.targetUser),
      FenyvoTrustService.isReported(widget.targetUser),
    ]);
    if (!mounted) return;
    setState(() {
      _contactTrusted = results[0];
      _contactBlocked = results[1];
      _contactReported = results[2];
    });
    FenyvoTrustService.requestRemote(widget.targetUser);
  }

  Future<void> _applyRemoteTrustState(Map<String, dynamic> data) async {
    final trusted = data['trusted'] == true;
    final blocked = data['blocked'] == true;
    final reported = data['reported'] == true;
    final reason = data['reportReason']?.toString() ?? '';
    final changed =
        trusted != _contactTrusted ||
        blocked != _contactBlocked ||
        reported != _contactReported;

    await FenyvoTrustService.applyRemote(
      widget.targetUser,
      trusted: trusted,
      blocked: blocked,
      reported: reported,
      reportReason: reason,
    );
    if (!mounted) return;
    setState(() {
      _contactTrusted = trusted;
      _contactBlocked = blocked;
      _contactReported = reported;
      if (blocked) {
        _messages.removeWhere((message) => message['isMe'] != true);
      }
    });
    if (blocked) _saveMessages();
    if (changed) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_chatText('trustSynced'))));
    }
  }

  Future<void> _showTrustExplanation({bool firstTime = false}) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.shield_rounded, color: FenyvoPalette.gold),
            const SizedBox(width: 10),
            Expanded(child: Text(_chatText('whatIsTrust'))),
          ],
        ),
        content: Text(_chatText('trustExplanation')),
        actions: [
          TextButton(
            onPressed: () async {
              if (firstTime) {
                await FenyvoTrustService.markExplanationSeen();
              }
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            },
            child: Text(
              firstTime ? _chatText('gotItDontShow') : _chatText('gotIt'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openTrustActions(ShieldAssessment assessment) async {
    if (await FenyvoTrustService.shouldShowExplanation()) {
      if (!mounted) return;
      await _showTrustExplanation(firstTime: true);
      if (!mounted) return;
    }
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: FenyvoPalette.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.shield_rounded, color: FenyvoPalette.gold),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'FENYVO TRUST',
                      style: TextStyle(
                        color: FenyvoPalette.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: _chatText('whatIsTrust'),
                    onPressed: () => unawaited(_showTrustExplanation()),
                    icon: const Icon(Icons.info_outline_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                widget.targetUser,
                style: const TextStyle(
                  color: FenyvoPalette.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                assessment.reason,
                style: const TextStyle(color: FenyvoPalette.secondary),
              ),
              const SizedBox(height: 14),
              ListTile(
                leading: Icon(
                  _contactTrusted
                      ? Icons.verified_rounded
                      : Icons.verified_outlined,
                  color: FenyvoPalette.gold,
                ),
                title: Text(
                  _contactTrusted
                      ? _chatText('removeTrusted')
                      : _chatText('addTrusted'),
                ),
                subtitle: Text(_chatText('trustBadgeSubtitle')),
                onTap: () => Navigator.pop(sheetContext, 'trust'),
              ),
              ListTile(
                leading: Icon(
                  _contactBlocked
                      ? Icons.lock_open_rounded
                      : Icons.block_rounded,
                  color: FenyvoPalette.gold,
                ),
                title: Text(
                  _contactBlocked
                      ? _chatText('unblockContact')
                      : _chatText('blockContact'),
                ),
                subtitle: Text(_chatText('blockSubtitle')),
                onTap: () => Navigator.pop(sheetContext, 'block'),
              ),
              ListTile(
                leading: const Icon(
                  Icons.flag_outlined,
                  color: FenyvoPalette.gold,
                ),
                title: Text(
                  _contactReported
                      ? _chatText('reportSent')
                      : _chatText('report'),
                ),
                subtitle: Text(_chatText('reportSubtitle')),
                enabled: !_contactReported,
                onTap: _contactReported
                    ? null
                    : () => Navigator.pop(sheetContext, 'report'),
              ),
            ],
          ),
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'trust') {
      final next = !_contactTrusted;
      await FenyvoTrustService.setTrusted(widget.targetUser, next);
      FenyvoTrustService.sync(widget.targetUser);
      if (mounted) setState(() => _contactTrusted = next);
    } else if (action == 'block') {
      final next = !_contactBlocked;
      await FenyvoTrustService.setBlocked(widget.targetUser, next);
      FenyvoTrustService.sync(widget.targetUser);
      if (mounted) {
        setState(() {
          _contactBlocked = next;
          if (next) {
            _messages.removeWhere((message) => message['isMe'] != true);
          }
        });
        if (next) _saveMessages();
      }
    } else if (action == 'report') {
      final reason = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_chatText('reportReason')),
          content: Text(_chatText('chooseReportReason')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, _chatText('fraud')),
              child: Text(_chatText('fraud')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, _chatText('spam')),
              child: Text(_chatText('spam')),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, _chatText('threats')),
              child: Text(_chatText('threats')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, _chatText('other')),
              child: Text(_chatText('other')),
            ),
          ],
        ),
      );
      if (reason == null) return;
      await FenyvoTrustService.report(widget.targetUser, reason: reason);
      FenyvoTrustService.sync(widget.targetUser);
      if (mounted) setState(() => _contactReported = true);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 3),
        content: Text(
          action == 'report'
              ? _chatText('reportSaved')
              : action == 'block'
              ? (_contactBlocked
                    ? _chatText('contactBlocked')
                    : _chatText('contactUnblocked'))
              : _chatText('contactSettingSaved'),
        ),
      ),
    );
  }

  Widget _buildShieldBanner() {
    final finding = _latestShieldFinding();
    if (finding == null || finding.fingerprint == _dismissedShieldFingerprint) {
      return const SizedBox.shrink();
    }
    final assessment = finding.assessment;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
        decoration: BoxDecoration(
          color: FenyvoPalette.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _gold.withValues(alpha: 0.75)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.shield_rounded, color: _gold),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _chatText('shieldCheckMessage'),
                    style: const TextStyle(
                      color: _gold,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    assessment.reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: FenyvoPalette.ink,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _chatText('analysisOnDevice'),
                    style: const TextStyle(
                      color: FenyvoPalette.secondary,
                      fontSize: 11,
                    ),
                  ),
                  TextButton(
                    onPressed: () => _openTrustActions(assessment),
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(_chatText('checkContact')),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: _chatText('hideWarning'),
              onPressed: () => setState(
                () => _dismissedShieldFingerprint = finding.fingerprint,
              ),
              icon: const Icon(Icons.close_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockedBanner() {
    if (!_contactBlocked) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: FenyvoPalette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: FenyvoPalette.secondary.withValues(alpha: .4),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.block_rounded, color: FenyvoPalette.secondary),
            const SizedBox(width: 10),
            Expanded(child: Text(_chatText('blockedBanner'))),
            TextButton(
              onPressed: () => unawaited(
                _openTrustActions(
                  ShieldAssessment(
                    reason: _chatText('trustManageReason'),
                    level: 'info',
                  ),
                ),
              ),
              child: Text(_chatText('edit')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          _chatText('noMessages'),
          style: const TextStyle(
            color: FenyvoPalette.secondary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
            shadows: [Shadow(blurRadius: 4, color: FenyvoPalette.ink)],
          ),
        ),
      );
    }

    final isWindowsDesktop = Platform.isWindows;

    return Stack(
      children: [
        if (!isWindowsDesktop)
          Positioned(
            left: 27,
            top: 0,
            bottom: 0,
            child: Container(
              width: 1.2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    FenyvoPalette.line.withValues(alpha: .82),
                    FenyvoPalette.line.withValues(alpha: .82),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: isWindowsDesktop
              ? ScrollbarTheme(
                  data: ScrollbarThemeData(
                    thumbColor: WidgetStateProperty.resolveWith<Color?>((
                      states,
                    ) {
                      if (states.contains(WidgetState.dragged)) {
                        return _gold.withValues(alpha: 0.88);
                      }

                      if (states.contains(WidgetState.hovered)) {
                        return _gold.withValues(alpha: 0.72);
                      }

                      return _gold.withValues(alpha: 0.34);
                    }),
                    thickness: WidgetStateProperty.resolveWith<double?>((
                      states,
                    ) {
                      if (states.contains(WidgetState.dragged) ||
                          states.contains(WidgetState.hovered)) {
                        return 8;
                      }

                      return 5;
                    }),
                    radius: const Radius.circular(10),
                    trackColor: WidgetStatePropertyAll(FenyvoPalette.line),
                    trackBorderColor: WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                  ),
                  child: Scrollbar(
                    controller: _messageScrollController,
                    thumbVisibility: true,
                    trackVisibility: false,
                    interactive: true,
                    child: ListView.builder(
                      controller: _messageScrollController,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
                      itemCount: _messages.length,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemBuilder: (context, index) {
                        return _buildMessageListItem(index);
                      },
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _messageScrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  itemCount: _messages.length,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemBuilder: (context, index) {
                    return _buildMessageListItem(index);
                  },
                ),
        ),

        if (isWindowsDesktop)
          Positioned(
            right: 24,
            bottom: 18,
            child: _buildScrollToLatestButton(),
          ),
      ],
    );
  }

  // ========================================
  // \u041F\u041E\u041B\u0415 \u0412\u0412\u041E\u0414\u0410
  // ========================================

  void _openComposerEmoji() {
    final open = !_emojiVisible;
    if (open) {
      _messageFocusNode.unfocus();
      unawaited(SystemChannels.textInput.invokeMethod<void>('TextInput.hide'));
    }
    setState(() => _emojiVisible = open);
  }

  Widget _buildMessageInput() {
    if (_isRecordingVoice)
      return _withVoicePointerBridge(_buildVoiceRecordingComposer());
    return _withVoicePointerBridge(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTypingIndicator(),
          _buildComposerReplyPreview(),
          Container(
            margin: const EdgeInsets.fromLTRB(10, 5, 10, 9),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [FenyvoPalette.surfaceSoft, FenyvoPalette.rail],
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: FenyvoPalette.line),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4A000000),
                  blurRadius: 16,
                  offset: Offset(0, 7),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 1),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: Platform.isWindows ? 800 : 920,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton.outlined(
                        tooltip: _chatText('attachment'),
                        onPressed: _sendingPrivateMedia
                            ? null
                            : () => unawaited(_showPrivateAttachmentMenu()),
                        icon: _sendingPrivateMedia
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.add_circle_outline_rounded,
                                color: FenyvoPalette.gold,
                              ),
                        style: IconButton.styleFrom(
                          side: BorderSide(
                            color: FenyvoPalette.gold.withValues(alpha: .58),
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: CallbackShortcuts(
                          bindings: Platform.isWindows
                              ? <ShortcutActivator, VoidCallback>{
                                  const SingleActivator(
                                    LogicalKeyboardKey.enter,
                                  ): _sendMessage,
                                  const SingleActivator(
                                    LogicalKeyboardKey.escape,
                                  ): _cancelReply,
                                }
                              : const <ShortcutActivator, VoidCallback>{},
                          child: TextField(
                            key: const ValueKey('private-composer'),
                            controller: _messageController,
                            focusNode: _messageFocusNode,
                            onTap: () {
                              if (_emojiVisible)
                                setState(() => _emojiVisible = false);
                            },
                            autofocus: false,
                            style: const TextStyle(
                              color: FenyvoPalette.ink,
                              fontSize: 16,
                            ),
                            keyboardType: TextInputType.multiline,
                            minLines: 1,
                            maxLines: 6,
                            textInputAction: TextInputAction.newline,
                            onChanged: _handleTextChanged,
                            decoration: InputDecoration(
                              hintText: _chatText('messageHint'),
                              fillColor: FenyvoPalette.canvasDeep.withValues(
                                alpha: .72,
                              ),
                              filled: true,
                              suffixIcon: IconButton(
                                tooltip: _chatText('emoji'),
                                onPressed: _openComposerEmoji,
                                icon: const Icon(
                                  Icons.emoji_emotions_outlined,
                                  color: FenyvoPalette.ink,
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(26),
                                borderSide: const BorderSide(
                                  color: FenyvoPalette.line,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(26),
                                borderSide: const BorderSide(
                                  color: FenyvoPalette.line,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(26),
                                borderSide: BorderSide(
                                  color: FenyvoPalette.gold.withValues(
                                    alpha: .72,
                                  ),
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_messageController.text.trim().isEmpty)
                        _buildVoiceRecordButton()
                      else
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: IconButton.filled(
                            tooltip: Platform.isWindows
                                ? _chatText('sendEnter')
                                : _chatText('send'),
                            onPressed: _sendMessage,
                            style: IconButton.styleFrom(
                              backgroundColor: FenyvoPalette.gold,
                              foregroundColor: FenyvoPalette.onGold,
                            ),
                            icon: const Icon(Icons.send_rounded),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ========================================
  // \u042D\u041A\u0420\u0410\u041D
  // ========================================

  Future<void> _showPulseSheet() async {
    final service = PulseService.instance;
    var video = false;
    var windowMinutes = 60;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: FenyvoPalette.surface,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return AnimatedBuilder(
              animation: service,
              builder: (context, _) {
                final active = service.activeFor(widget.targetUser);
                final incoming =
                    active != null &&
                    service.phase == FenyvoPulsePhase.incoming;
                final matched =
                    active != null &&
                    service.phase == FenyvoPulsePhase.matched;
                final width = MediaQuery.sizeOf(context).width;

                Widget modeButton({
                  required bool selected,
                  required IconData icon,
                  required String label,
                  required VoidCallback onPressed,
                }) {
                  return Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: onPressed,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? FenyvoPalette.blue
                              : FenyvoPalette.canvas,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected
                                ? FenyvoPalette.gold
                                : FenyvoPalette.line,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              icon,
                              color: selected
                                  ? FenyvoPalette.gold
                                  : FenyvoPalette.secondary,
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                label,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: selected
                                      ? FenyvoPalette.ink
                                      : FenyvoPalette.secondary,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return SafeArea(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: width > 620 ? 560 : width,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 4, 22, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 52,
                                height: 52,
                                decoration: BoxDecoration(
                                  color: FenyvoPalette.blue,
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: FenyvoPalette.gold,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: FenyvoPalette.gold.withValues(
                                        alpha: .18,
                                      ),
                                      blurRadius: 18,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.bolt_rounded,
                                  color: FenyvoPalette.gold,
                                  size: 30,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'FENYVO PULSE',
                                      style: TextStyle(
                                        color: FenyvoPalette.gold,
                                        fontSize: 19,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                    Text(
                                      _chatText('pulseTagline'),
                                      style: const TextStyle(
                                        color: FenyvoPalette.secondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 22),
                          if (active != null) ...[
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: FenyvoPalette.canvas,
                                borderRadius: BorderRadius.circular(22),
                                border: Border.all(
                                  color: matched
                                      ? FenyvoPalette.gold
                                      : FenyvoPalette.line,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    matched
                                        ? Icons.graphic_eq_rounded
                                        : incoming
                                        ? Icons.notifications_active_rounded
                                        : Icons.schedule_rounded,
                                    size: 38,
                                    color: FenyvoPalette.gold,
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    matched
                                        ? _chatText('bothReadyCountdown', {
                                            'seconds': service.countdownSeconds,
                                          })
                                        : incoming
                                        ? _chatText('awaitsDecision', {
                                            'user': widget.targetUser,
                                          })
                                        : _chatText('waitingForReady', {
                                            'user': widget.targetUser,
                                          }),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: FenyvoPalette.ink,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    active.video
                                        ? _chatText('videoCall')
                                        : _chatText('audioCall'),
                                    style: const TextStyle(
                                      color: FenyvoPalette.secondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (incoming)
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton(
                                      onPressed: () {
                                        service.decline();
                                        Navigator.of(sheetContext).pop();
                                      },
                                      child: Text(_chatText('notNow')),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: FilledButton.icon(
                                      onPressed: () {
                                        service.accept();
                                        Navigator.of(sheetContext).pop();
                                      },
                                      icon: const Icon(Icons.check_rounded),
                                      label: Text(_chatText('imReady')),
                                    ),
                                  ),
                                ],
                              )
                            else
                              OutlinedButton.icon(
                                onPressed: () {
                                  service.cancel();
                                  Navigator.of(sheetContext).pop();
                                },
                                icon: const Icon(Icons.close_rounded),
                                label: Text(_chatText('cancelPulse')),
                              ),
                          ] else ...[
                            Text(
                              _chatText('pulseInviteExplanation', {
                                'user': widget.targetUser,
                              }),
                              style: const TextStyle(
                                color: FenyvoPalette.secondary,
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Row(
                              children: [
                                modeButton(
                                  selected: !video,
                                  icon: Icons.call_rounded,
                                  label: _chatText('audio'),
                                  onPressed: () =>
                                      setSheetState(() => video = false),
                                ),
                                const SizedBox(width: 10),
                                modeButton(
                                  selected: video,
                                  icon: Icons.videocam_rounded,
                                  label: _chatText('video'),
                                  onPressed: () =>
                                      setSheetState(() => video = true),
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            Text(
                              _chatText('freeFor'),
                              style: const TextStyle(
                                color: FenyvoPalette.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final option in {
                                  15: _chatText('minutes15'),
                                  60: _chatText('hour1'),
                                  240: _chatText('hours4'),
                                }.entries)
                                  ChoiceChip(
                                    label: Text(option.value),
                                    selected: windowMinutes == option.key,
                                    selectedColor: FenyvoPalette.blue,
                                    backgroundColor: FenyvoPalette.canvas,
                                    side: BorderSide(
                                      color: windowMinutes == option.key
                                          ? FenyvoPalette.gold
                                          : FenyvoPalette.line,
                                    ),
                                    labelStyle: TextStyle(
                                      color: windowMinutes == option.key
                                          ? FenyvoPalette.ink
                                          : FenyvoPalette.secondary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    onSelected: (_) => setSheetState(
                                      () => windowMinutes = option.key,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 22),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(52),
                              ),
                              onPressed: () {
                                service.request(
                                  peer: widget.targetUser,
                                  video: video,
                                  windowMinutes: windowMinutes,
                                );
                                Navigator.of(sheetContext).pop();
                              },
                              icon: const Icon(Icons.bolt_rounded),
                              label: Text(_chatText('inviteWhenFree')),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              _chatText('pulsePrivacy'),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: FenyvoPalette.muted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  void _startPrivateCall({required bool video}) {
    if (!SocketService.instance.isConnected) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_chatText('noServerConnection'))));
      return;
    }

    if (CallService.instance.hasCall) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_chatText('anotherCallActive'))));
      return;
    }

    unawaited(
      CallService.instance.startCall(peer: widget.targetUser, video: video),
    );
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;

    return PopScope(
      canPop: !_emojiVisible && !_searchMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_emojiVisible) {
          setState(() => _emojiVisible = false);
        } else if (_searchMode) {
          _closeMessageSearch();
        }
      },
      child: Scaffold(
        backgroundColor: FenyvoPalette.canvas,
        resizeToAvoidBottomInset: false,
        appBar: AppBar(
          automaticallyImplyLeading: Navigator.canPop(context),
          toolbarHeight: Platform.isWindows ? 70 : 64,
          titleSpacing: Platform.isWindows ? 22 : 0,
          title: Row(
            children: [
              _buildContactAvatar(),

              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.targetUser,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: FenyvoPalette.ink,
                        fontSize: Platform.isWindows ? 18 : 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),

                    const SizedBox(height: 2),

                    Platform.isWindows
                        ? AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.18),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: Row(
                              key: ValueKey(
                                _contactIsTyping
                                    ? 'typing'
                                    : _contactOnline
                                    ? 'online'
                                    : _formatContactStatus(),
                              ),
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 220),
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _contactIsTyping
                                        ? FenyvoPalette.blue
                                        : _contactOnline
                                        ? Colors.greenAccent
                                        : FenyvoPalette.muted,
                                    boxShadow:
                                        (_contactIsTyping || _contactOnline)
                                        ? [
                                            BoxShadow(
                                              color:
                                                  (_contactIsTyping
                                                          ? _gold
                                                          : Colors.greenAccent)
                                                      .withValues(alpha: 0.06),
                                              blurRadius: 8,
                                            ),
                                          ]
                                        : const [],
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    _contactIsTyping
                                        ? _chatText('typing')
                                        : _formatContactStatus(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: _contactIsTyping
                                          ? _gold
                                          : _contactOnline
                                          ? Colors.greenAccent
                                          : FenyvoPalette.secondary,
                                      fontSize: 12,
                                      fontWeight: _contactIsTyping
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          )
                        : Text(
                            _formatContactStatus(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _contactOnline
                                  ? Colors.greenAccent
                                  : FenyvoPalette.secondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                  ],
                ),
              ),
              if (_contactTrusted)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.verified_rounded, color: _gold, size: 19),
                ),
            ],
          ),
          actions: [
            AnimatedBuilder(
              animation: PulseService.instance,
              builder: (context, _) {
                final active =
                    PulseService.instance.activeFor(widget.targetUser) != null;
                return Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: active ? FenyvoPalette.blue : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: active
                        ? Border.all(color: FenyvoPalette.gold)
                        : null,
                  ),
                  child: IconButton(
                    tooltip: _chatText('pulseTooltip'),
                    onPressed: () => unawaited(_showPulseSheet()),
                    icon: Icon(
                      Icons.bolt_rounded,
                      color: active
                          ? FenyvoPalette.gold
                          : FenyvoPalette.secondary,
                    ),
                  ),
                );
              },
            ),
            IconButton(
              tooltip: _chatText('audioCall'),
              onPressed: () {
                _startPrivateCall(video: false);
              },
              icon: const Icon(Icons.call_rounded, color: _gold),
            ),
            IconButton(
              tooltip: _chatText('videoCall'),
              onPressed: () {
                _startPrivateCall(video: true);
              },
              icon: const Icon(Icons.videocam_rounded, color: _gold),
            ),
            PopupMenuButton<String>(
              tooltip: _chatText('more'),
              icon: const Icon(Icons.more_vert_rounded),
              onSelected: (value) {
                if (value == 'search') _openMessageSearch();
                if (value == 'ai') unawaited(_showFenyvoAiSheet());
                if (value == 'auto') unawaited(_showAutoReplySettings());
                if (value == 'screen_security' &&
                    (Platform.isAndroid || Platform.isWindows)) {
                  unawaited(_toggleScreenSecurity());
                }
                if (value == 'e2ee') unawaited(_toggleChatE2ee());
                if (value == 'e2ee_verify') {
                  unawaited(_showE2eeSafetyNumber());
                }
                if (value == 'trust') {
                  unawaited(
                    _openTrustActions(
                      ShieldAssessment(
                        reason: _chatText('trustManageReason'),
                        level: 'info',
                      ),
                    ),
                  );
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'search',
                  child: Row(
                    children: [
                      const Icon(Icons.search_rounded),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_chatText('searchMessages'))),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'e2ee',
                  enabled: !_changingE2ee,
                  child: Row(
                    children: [
                      Icon(
                        _e2eeActive
                            ? Icons.lock_rounded
                            : Icons.lock_open_rounded,
                        color: _e2eeActive ? _gold : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _e2eeActive
                              ? _chatText('e2eeChatOn')
                              : _chatText('e2eeChatInvite'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_e2eeActive)
                  PopupMenuItem(
                    value: 'e2ee_verify',
                    child: Row(
                      children: [
                        Icon(
                          _e2eeVerified
                              ? Icons.verified_user_rounded
                              : _e2eeKeyChanged
                              ? Icons.warning_amber_rounded
                              : Icons.qr_code_2_rounded,
                          color: _e2eeVerified
                              ? Colors.green
                              : _e2eeKeyChanged
                              ? Colors.orange
                              : _gold,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _e2eeVerified
                                ? _chatText('e2eeVerified')
                                : _e2eeKeyChanged
                                ? _chatText('e2eeKeyChangedTitle')
                                : _chatText('e2eeVerifyTitle'),
                          ),
                        ),
                      ],
                    ),
                  ),
                PopupMenuItem(
                  value: 'trust',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_chatText('trustContact')),
                      Text(
                        _chatText('trustSubtitle'),
                        style: const TextStyle(fontSize: 11),
                      ),
                    ],
                  ),
                ),
                if (Platform.isAndroid || Platform.isWindows)
                  PopupMenuItem<String>(
                    value: 'screen_security',
                    child: Row(
                      children: [
                        const Icon(Icons.security_rounded),
                        const SizedBox(width: 12),
                        const Expanded(child: Text('Защита экрана')),
                        Text(
                          _screenSecurityEnabled ? 'Вкл.' : 'Выкл.',
                          style: TextStyle(
                            color: _screenSecurityEnabled
                                ? Colors.greenAccent
                                : FenyvoPalette.secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                const PopupMenuItem(value: 'ai', child: Text('FENYVO AI')),
                PopupMenuItem(
                  value: 'auto',
                  enabled: !_autoReplyLoading,
                  child: Text(
                    _autoReplyEnabled
                        ? _chatText('autoRepliesOn')
                        : _chatText('configureAutoReplies'),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 4),
          ],
          backgroundColor: FenyvoPalette.canvasDeep,
          foregroundColor: FenyvoPalette.ink,
          elevation: 0,
          shadowColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          shape: Border(
            bottom: BorderSide(
              color: _gold.withValues(
                alpha: _contactIsTyping
                    ? .46
                    : _contactOnline
                    ? .32
                    : .22,
              ),
              width: _contactIsTyping ? 1.1 : .8,
            ),
          ),
        ),
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildBackground(),

            AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                bottom: _emojiVisible ? 0 : keyboardHeight,
              ),
              child: Column(
                children: [
                  if (_searchMode) _buildMessageSearchBar(),
                  _buildBlockedBanner(),
                  _buildShieldBanner(),
                  _buildPinnedMessageBanner(),
                  Expanded(child: _buildMessages()),
                  _buildMessageInput(),
                  if (_emojiVisible && !_isRecordingVoice)
                    SafeArea(
                      top: false,
                      child: ComposerEmojiPanel(
                        controller: _messageController,
                        height: (MediaQuery.sizeOf(context).height * .30).clamp(
                          120.0,
                          280.0,
                        ),
                        onChanged: () =>
                            _handleTextChanged(_messageController.text),
                        onClose: () => setState(() => _emojiVisible = false),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
