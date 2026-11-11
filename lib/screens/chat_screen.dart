import '../services/app_visibility.dart';
import 'package:fenyvo/services/crypto/private_e2ee_edit_protocol.dart';
import '../features/messages/domain/private_external_text_policy.dart';
import '../features/messages/data/private_voice_temp_cleanup_policy.dart';
import '../features/messages/data/private_voice_temp_path_tracker.dart';
import '../features/messages/data/private_voice_failed_start_cleanup.dart';
import '../features/messages/domain/private_voice_recording_operations.dart';
import '../features/messages/domain/private_voice_recording_ticker.dart';
import '../features/messages/domain/private_voice_recording_state.dart';
import '../features/messages/data/private_voice_recorder_shutdown.dart';
import '../widgets/private_voice_pointer_bridge.dart';
import '../features/messages/domain/private_voice_recording_gesture_policy.dart';
import '../features/messages/data/private_voice_recording_files.dart';
import '../features/messages/domain/private_voice_recording_policy.dart';
import '../widgets/private_composer_reply_preview.dart';
import '../widgets/private_voice_record_button.dart';
import '../widgets/fenyvo_hex_video_camera.dart';
import '../widgets/fenyvo_hex_audio_border.dart';
import '../features/messages/data/hex_video_audio_levels.dart';
import '../widgets/private_voice_recording_composer.dart';
import '../widgets/private_voice_message_player.dart';
import '../features/messages/domain/voice_playback_policy.dart';
import '../features/messages/domain/voice_duration_formatter.dart';
import '../features/messages/domain/private_attachment_size_formatter.dart';
import '../features/messages/domain/private_attachment_helpers.dart';
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

import '../features/messages/data/private_video_note_speed_settings.dart';

import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';

import '../features/messages/data/private_video_note_capture.dart';
import '../features/messages/data/private_voice_recorder_device.dart';

import 'package:qr_flutter/qr_flutter.dart';

import '../services/legacy_media_regrant_visibility.dart';
import '../services/legacy_media_regrant_result.dart';
import '../services/legacy_media_regrant_client.dart';
import '../widgets/legacy_media_regrant_dialog.dart';
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
import '../services/presence_tracker.dart';
import '../services/e2ee_settings_service.dart';
import '../services/crypto/signal_e2ee_service.dart';
part '../widgets/private_forward_message_sheet.dart';
part '../widgets/private_auto_reply_settings.dart';
part '../widgets/private_share_contact_picker.dart';
part '../widgets/private_chatgpt_sheet.dart';
part '../widgets/private_translation_sheet.dart';
part '../widgets/private_video_widgets.dart';
part '../widgets/private_message_search.dart';
part '../widgets/private_pinned_messages.dart';
part '../widgets/private_reaction_widgets.dart';
part '../widgets/private_message_menu_widgets.dart';
part '../widgets/private_message_display_widgets.dart';
part '../widgets/private_message_bubble.dart';
part '../widgets/private_message_list.dart';
part '../widgets/private_message_composer.dart';
part '../widgets/private_desktop_message_context_menu.dart';

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

  // Cache the decoded avatar across frequent chat rebuilds.
  String? _contactAvatarCachedSource;
  MemoryImage? _contactAvatarCachedImage;
  late final PresenceTracker _presence;
  bool get _contactOnline => _presence.isOnline(widget.targetUser);
  DateTime? _contactLastSeen;
  bool _contactIsTyping = false;
  String? _contactRecordingKind;
  Timer? _contactRecordingTimeoutTimer;
  Timer? _localVoiceActivityTimer;
  bool _typingSent = false;

  final ImagePicker _privateImagePicker = ImagePicker();
  bool _sendingPrivateMedia = false;
  bool _videoNoteMode = false;
  bool? _voiceHoldPendingFinish;

  OverlayEntry? _hexCameraOverlay;
  FenyvoHexCameraControl? _hexCameraControl;
  bool _hexVideoPressHeld = false;
  bool _hexVideoCancelled = false;
  bool _hexVideoLocked = false;
  bool _localHexRecordingActivityActive = false;
  Timer? _localHexRecordingActivityTimer;

  void _setLocalHexRecordingActivity(bool active) {
    _localHexRecordingActivityTimer?.cancel();
    _localHexRecordingActivityTimer = null;

    if (active && !mounted) return;
    if (!active && !_localHexRecordingActivityActive) return;

    _localHexRecordingActivityActive = active;

    SocketService.instance.sendRecordingActivity(
      widget.targetUser,
      kind: 'video',
      active: active,
    );

    if (!active) return;

    _localHexRecordingActivityTimer = Timer.periodic(
      const Duration(seconds: 5),
      (timer) {
        if (!mounted || !_localHexRecordingActivityActive) {
          timer.cancel();
          _localHexRecordingActivityTimer = null;
          return;
        }

        SocketService.instance.sendRecordingActivity(
          widget.targetUser,
          kind: 'video',
          active: true,
        );
      },
    );
  }

  void _closeHexCameraOverlay() {
    _setLocalHexRecordingActivity(false);
    final entry = _hexCameraOverlay;
    _hexCameraOverlay = null;

    final control = _hexCameraControl;
    _hexCameraControl = null;

    entry?.remove();
    entry?.dispose();
    control?.dispose();
  }

  void _showHexCameraPreview() {
    if (!mounted ||
        !_videoNoteMode ||
        _hexCameraOverlay != null ||
        _sendingPrivateMedia ||
        (!Platform.isAndroid && !Platform.isIOS && !Platform.isWindows)) {
      return;
    }
    final control = FenyvoHexCameraControl();
    _hexCameraControl = control;

    final entry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        left: 0,
        right: 0,
        bottom: 106,
        child: Center(
          child: FenyvoHexVideoCamera(
            control: control,
            onRecordingChanged: _setLocalHexRecordingActivity,
            languageCode: AppLanguageService.instance.code.value,
            onCancel: () {
              _hexVideoPressHeld = false;
              _closeHexCameraOverlay();
            },
            onCaptured: (path) async {
              _hexVideoPressHeld = false;
              final overlayForThisVideo = _hexCameraOverlay;
              if (!mounted) return;

              // Recording has stopped. Close the camera
              // immediately; sending continues independently.
              if (identical(_hexCameraOverlay, overlayForThisVideo)) {
                _closeHexCameraOverlay();
              }

              final extension = path.toLowerCase().endsWith('.mov')
                  ? 'mov'
                  : 'mp4';

              await _sendPrivateMediaFile(
                messageType: 'video',
                path: path,
                fileName:
                    'fenyvo_hex_note_${DateTime.now().millisecondsSinceEpoch}.$extension',
                mimeType: extension == 'mov' ? 'video/quicktime' : 'video/mp4',
                text: _videoNoteText(
                  'Видеосообщение',
                  'Відеоповідомлення',
                  'Video message',
                ),
                maxBytes: PrivateVideoNoteCapture.maximumBytes,
              );
            },
          ),
        ),
      ),
    );

    _hexCameraOverlay = entry;
    Overlay.of(context).insert(entry);
  }

  void _beginHexVideoHold(LongPressStartDetails details) {
    if (!mounted ||
        !_videoNoteMode ||
        _sendingPrivateMedia ||
        _isRecordingVoice ||
        _hexVideoPressHeld) {
      return;
    }

    _hexVideoPressHeld = true;
    _hexVideoCancelled = false;
    _hexVideoLocked = false;

    // Reuse the already initialized preview when possible.
    if (_hexCameraControl == null) {
      _showHexCameraPreview();
    }

    // Camera initialization may still be asynchronous.
    _hexCameraControl?.startRecording();
  }

  void _moveHexVideoHold(LongPressMoveUpdateDetails details) {
    if (!_hexVideoPressHeld || _hexVideoCancelled || _hexVideoLocked) {
      return;
    }

    // Cancel takes priority if both gesture thresholds are met.
    if (details.offsetFromOrigin.dx <= -70) {
      _hexVideoCancelled = true;
      _hexVideoPressHeld = false;
      _hexCameraControl?.cancelRecording();
      return;
    }

    if (details.offsetFromOrigin.dy <= -80) {
      _hexVideoLocked = true;
      _hexVideoPressHeld = false;
      _hexCameraControl?.lockRecording();
    }
  }

  void _endHexVideoHold() {
    if (!_hexVideoPressHeld || _hexVideoCancelled || _hexVideoLocked) return;
    _hexVideoPressHeld = false;
    _hexCameraControl?.sendRecording();
  }

  void _togglePrivateVideoNoteMode() {
    if (!mounted ||
        _sendingPrivateMedia ||
        _isRecordingVoice ||
        _hexVideoPressHeld) {
      return;
    }
    if (!Platform.isAndroid && !Platform.isIOS && !Platform.isWindows) return;

    final enableVideo = !_videoNoteMode;
    setState(() => _videoNoteMode = enableVideo);

    if (enableVideo) {
      // Preview is shown immediately, without recording anything.
      _showHexCameraPreview();
    } else {
      _hexVideoCancelled = true;
      _hexVideoPressHeld = false;
      _closeHexCameraOverlay();
    }
  }

  List<String> _registeredUsers = const [];
  Completer<List<String>>? _registeredUsersCompleter;

  final PrivateVoiceRecorderDevice _voiceRecorder =
      PrivateVoiceRecorderDevice();
  final PrivateVoiceRecorderShutdown _voiceShutdown =
      PrivateVoiceRecorderShutdown();
  final PrivateVoiceRecordingOperations _voiceOperations =
      PrivateVoiceRecordingOperations();

  Future<void>? get _voiceStartFuture => _voiceOperations.pendingStart;
  Future<void>? get _voiceFinishFuture => _voiceOperations.pendingFinish;
  final PrivateVoiceTempPathTracker _voiceTempPaths =
      PrivateVoiceTempPathTracker();
  bool _voiceStopFailed = false;
  final AudioPlayer _voicePlayer = AudioPlayer();

  final PrivateVoiceRecordingTicker _voiceTicker =
      PrivateVoiceRecordingTicker();
  StreamSubscription<Duration>? _voicePositionSubscription;
  StreamSubscription<Duration>? _voiceDurationSubscription;
  StreamSubscription<PlayerState>? _voiceStateSubscription;
  StreamSubscription<void>? _voiceCompleteSubscription;

  final PrivateVoiceRecordingState _voiceState = PrivateVoiceRecordingState();
  bool get _voicePressActive => _voiceState.pressActive;
  set _voicePressActive(bool value) => _voiceState.pressActive = value;
  bool get _voiceStarting => _voiceState.starting;
  set _voiceStarting(bool value) => _voiceState.starting = value;
  bool get _isRecordingVoice => _voiceState.isRecording;
  set _isRecordingVoice(bool value) => _voiceState.isRecording = value;
  bool get _voiceRecordingLocked => _voiceState.locked;
  set _voiceRecordingLocked(bool value) => _voiceState.locked = value;
  Duration get _voiceRecordDuration => _voiceState.duration;
  set _voiceRecordDuration(Duration value) => _voiceState.duration = value;
  Offset? _voiceDragStart;
  String? get _voiceRecordingPath => _voiceState.recordingPath;
  set _voiceRecordingPath(String? value) => _voiceState.recordingPath = value;

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
  bool _e2eeDecryptWarningShown = false;
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
    _presence = PresenceTracker()..addListener(_handlePresenceChanged);
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

      if (position.inMilliseconds % 1000 < 220) {
        debugPrint(
          'FENYVO_VOICE_TIMING event=position '
          'position_ms=${position.inMilliseconds} '
          'duration_ms=${_voicePlaybackDuration.inMilliseconds}',
        );
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

      debugPrint(
        'FENYVO_VOICE_TIMING event=duration '
        'duration_ms=${duration.inMilliseconds}',
      );
      setState(() {
        _voicePlaybackDuration = duration;
      });
    });

    _voiceStateSubscription = _voicePlayer.onPlayerStateChanged.listen((state) {
      debugPrint('FENYVO_VOICE_TRACE event=state value=${state.name}');
      if (!mounted) {
        return;
      }

      setState(() {
        _voiceIsPlaying = state == PlayerState.playing;
      });
    });

    _voiceCompleteSubscription = _voicePlayer.onPlayerComplete.listen((_) {
      unawaited(HexInlineVoiceCoordinator.setVoiceActive(false));
      // FENYVO_VOICE_COMPLETION_TRACE_983
      // Only timing metadata; no paths, IDs, message text or encryption data.
      debugPrint(
        'FENYVO_VOICE_TIMING event=complete '
        'position_ms=${_voicePlaybackPosition.inMilliseconds} '
        'duration_ms=${_voicePlaybackDuration.inMilliseconds} '
        'active=${_playingVoiceMessageId != null}',
      );
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
    _closeHexCameraOverlay();
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
    _contactRecordingTimeoutTimer?.cancel();
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
    _presence
      ..removeListener(_handlePresenceChanged)
      ..dispose();

    _messageScrollController.removeListener(_handleMessageScroll);
    _messageScrollController.dispose();

    _messageFocusNode.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _drafts[_draftKey] = _messageController.text;
    _messageController.dispose();

    _setLocalVoiceRecordingActivity(false);
    _voiceTicker.stop();
    _voicePositionSubscription?.cancel();
    _voiceDurationSubscription?.cancel();
    _voiceStateSubscription?.cancel();
    _voiceCompleteSubscription?.cancel();
    _voicePressActive = false;

    String? shutdownStoppedPath;
    bool shutdownStopSucceeded = false;

    unawaited(
      _voiceShutdown
          .close(
            pendingStart: _voiceStartFuture,
            pendingFinish: _voiceFinishFuture,
            stop: () async {
              try {
                shutdownStoppedPath = await _voiceRecorder.stop();
                shutdownStopSucceeded = true;
              } catch (_) {
                // The recorder may already be stopped.
              }
            },
            cleanup: () async {
              final paths = PrivateVoiceTempCleanupPolicy.pathsForShutdown(
                stopSucceeded: shutdownStopSucceeded,
                trackedPaths: _voiceTempPaths.paths,
                recordingPath: _voiceRecordingPath,
                stoppedPath: shutdownStoppedPath,
              );

              if (!shutdownStopSucceeded) {
                debugPrint(
                  'Voice shutdown: recorder stop failed; '
                  'temporary file deletion skipped',
                );
                return;
              }

              for (final path in paths) {
                await _deleteVoiceTemporaryFile(path);
              }

              _voiceTempPaths.clear();
              _voiceRecordingPath = null;
            },
            dispose: () => _voiceRecorder.dispose(),
          )
          .catchError((Object error, StackTrace stack) {
            debugPrint('Voice recorder shutdown failed: $error');
          }),
    );
    unawaited(
      HexInlineVoiceCoordinator.setVoiceRecordingActive(false),
    );
    unawaited(_voicePlayer.dispose());

    super.dispose();
  }

  void _refreshLanguage() {
    if (mounted) setState(() {});
  }

  void _handlePresenceChanged() {
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

    // A new MemoryImage on every setState can cause repeated decoding
    // and visible flicker during typing and voice playback.
    if (_contactAvatarCachedSource != avatar) {
      _contactAvatarCachedSource = avatar;
      _contactAvatarCachedImage = null;

      if (avatar != null && avatar.isNotEmpty) {
        try {
          _contactAvatarCachedImage = MemoryImage(base64Decode(avatar));
        } catch (_) {
          _contactAvatarCachedImage = null;
        }
      }
    }

    final ImageProvider? imageProvider = _contactAvatarCachedImage;

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
                  border: Border.all(color: FenyvoPalette.canvasDeep, width: 2),
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

  void _setContactRecordingActivity(String kind, bool active) {
    if (!mounted || (kind != 'voice' && kind != 'video')) return;

    if (!active) {
      if (_contactRecordingKind != kind) return;
      _contactRecordingTimeoutTimer?.cancel();
      _contactRecordingTimeoutTimer = null;
      setState(() => _contactRecordingKind = null);
      return;
    }

    _contactRecordingTimeoutTimer?.cancel();
    _remoteTypingTimeoutTimer?.cancel();

    // Recording takes priority over a delayed typing event.
    if (_contactRecordingKind != kind || _contactIsTyping) {
      setState(() {
        _contactRecordingKind = kind;
        _contactIsTyping = false;
      });
    }

    // A missing stop packet must not leave an endless status.
    _contactRecordingTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (!mounted) return;
      setState(() => _contactRecordingKind = null);
      _contactRecordingTimeoutTimer = null;
    });
  }

  void _setContactTyping(bool isTyping) {
    // A late typing event must not override an active recording.
    if (isTyping && _contactRecordingKind != null) return;

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
      child: !_contactIsTyping && _contactRecordingKind == null
          ? const SizedBox.shrink()
          : Container(
              key: const ValueKey('typing_indicator'),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 7, 18, 5),
              color: FenyvoPalette.surface,
              child: Row(
                children: [
                  if (_contactRecordingKind == null)
                    const Icon(Icons.edit_outlined, size: 14, color: _gold)
                  else
                    AnimatedBuilder(
                      animation: _typingAnimationController,
                      builder: (context, child) {
                        final phase = _typingAnimationController.value;
                        final pulse = phase < 0.5
                            ? phase * 2.0
                            : (1.0 - phase) * 2.0;

                        return Opacity(
                          opacity: 0.35 + 0.65 * pulse,
                          child: child,
                        );
                      },
                      child: Icon(
                        _contactRecordingKind == 'voice'
                            ? Icons.mic_rounded
                            : Icons.videocam_rounded,
                        size: 14,
                        color: _contactRecordingKind == 'voice'
                            ? Colors.redAccent
                            : _gold,
                      ),
                    ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      '${widget.targetUser} ${_contactRecordingKind == 'voice'
                          ? _videoNoteText('записывает голосовое…', 'записує голосове…', 'is recording a voice message…')
                          : _contactRecordingKind == 'video'
                          ? _videoNoteText('записывает видео…', 'записує відео…', 'is recording a video message…')
                          : _videoNoteText('печатает…', 'друкує…', 'is typing…')}',
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
                  if (_contactRecordingKind == null) _buildTypingDots(),
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

    final savedMessages = StorageService.getMessagesVisibleForOwner(
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
    final owner = SocketService.instance.currentUser?.trim() ?? '';
    final peer = widget.targetUser;
    if (owner.isEmpty || peer.isEmpty) return;

    unawaited(
      StorageService.mutateMessagesDurably(owner, peer, (current) {
        for (final message in current) {
          if (message['id']?.toString().trim() != id ||
              message['from']?.toString().trim() != owner ||
              message['to']?.toString().trim() != peer) {
            continue;
          }
          final confirmed = parsedTime.toUtc().toIso8601String();
          if (message['time']?.toString() == confirmed) return null;
          message['time'] = confirmed;
          return current;
        }
        return null;
      }).then((_) {}).catchError((Object error, StackTrace stack) {
        debugPrint('Durable message time update failed: $error');
      }),
    );
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

    final owner = SocketService.instance.currentUser?.trim() ?? '';
    final peer = widget.targetUser;
    if (owner.isEmpty || peer.isEmpty) return;

    unawaited(
      StorageService.mutateMessagesDurably(owner, peer, (current) {
        for (final message in current) {
          if (message['id']?.toString().trim() != id ||
              message['from']?.toString().trim() != owner ||
              message['to']?.toString().trim() != peer) {
            continue;
          }
          final storedStatus = message['status']?.toString() ?? '';
          if (_messageStatusRank(newStatus) <=
              _messageStatusRank(storedStatus)) {
            return null;
          }
          message['status'] = newStatus;
          return current;
        }
        return null;
      }).then((_) {}).catchError((Object error, StackTrace stack) {
        debugPrint('Durable message status update failed: $error');
      }),
    );
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
    final newlyReadIds = <String>{};

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
      newlyReadIds.add(messageId);

      changed = true;
    }

    if (changed) {
      final owner = currentUser.trim();
      final peer = widget.targetUser.trim();
      final idsToMark = Set<String>.from(newlyReadIds);

      if (owner.isNotEmpty && peer.isNotEmpty && idsToMark.isNotEmpty) {
        unawaited(
          StorageService.mutateMessagesDurably(owner, peer, (current) {
            var modified = false;

            for (final stored in current) {
              final id = stored['id']?.toString().trim() ?? '';
              if (!idsToMark.contains(id)) continue;

              final sender = stored['from']?.toString().trim() ?? '';
              final recipient = stored['to']?.toString().trim() ?? '';
              if (sender != peer || recipient != owner) continue;

              if (stored['readByMe'] != true) {
                stored['readByMe'] = true;
                modified = true;
              }
            }

            return modified ? current : null;
          }).then((_) {}).catchError((Object error, StackTrace stack) {
            debugPrint('Durable incoming read update failed: $error');
          }),
        );
      }
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

  Future<void> _showIncomingE2eeInvite(String from) async {
    if (_changingE2ee) return;
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

  Future<void> _showE2eeDecryptWarning() async {
    if (!mounted || !SocketService.instance.isAuthenticated) return;
    final verifyNow = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: Colors.orange),
        title: Text(_videoNoteText(
          'Ошибка защищённого сообщения',
          'Помилка захищеного повідомлення',
          'Encrypted message error',
        )),
        content: Text(_videoNoteText(
          'Сообщение не удалось расшифровать. Причиной может быть смена ключа '
          'или несовместимая Signal-сессия. Проверьте новый номер безопасности '
          'с собеседником по независимому каналу. Не подтверждайте несовпадающий номер.',
          'Не вдалося розшифрувати повідомлення. Причиною може бути зміна ключа '
          'або несумісна Signal-сесія. Перевірте новий номер безпеки '
          'із співрозмовником через незалежний канал. Не підтверджуйте різні номери.',
          'The message could not be decrypted. The key may have changed or '
          'the Signal session may be incompatible. Verify the new safety number '
          'with your contact over an independent channel. Do not approve a mismatch.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(_chatText('close')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.verified_user_outlined),
            label: Text(_videoNoteText(
              'Проверить новый ключ',
              'Перевірити новий ключ',
              'Verify new key',
            )),
          ),
        ],
      ),
    );
    if (verifyNow == true && mounted) {
      await _showVerifiedE2eeRecovery();
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
      await _showVerifiedE2eeRecovery();
    }
  }

  Future<void> _showVerifiedE2eeRecovery() async {
    if (!mounted || !SocketService.instance.isAuthenticated) return;
    final owner = SocketService.instance.currentUser?.trim() ?? '';
    final peer = widget.targetUser.trim();
    if (owner.isEmpty || peer.isEmpty || owner == peer) return;
    try {
      final bundle = await SocketService.instance.previewE2eeCandidate(peer);
      if (!mounted || SocketService.instance.currentUser?.trim() != owner) {
        return;
      }
      final candidate = await SignalE2eeService.instance.candidateSafetyNumber(
        peer,
        bundle['identityKey']?.toString() ?? '',
      );
      if (!mounted || SocketService.instance.currentUser?.trim() != owner) {
        return;
      }
      var compared = false;
      final approved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, updateDialog) => AlertDialog(
            title: Text(_videoNoteText(
              'Проверка нового ключа', 'Перевірка нового ключа',
              'Verify new key',
            )),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_videoNoteText(
                    'Сравните этот номер с номером контакта по независимому каналу. '
                    'Если номера не совпадают, отмените восстановление.',
                    'Порівняйте цей номер із номером контакту через незалежний канал. '
                    'Якщо номери не збігаються, скасуйте відновлення.',
                    'Compare this number with your contact using an independent channel. '
                    'Cancel if the numbers do not match.',
                  )),
                  const SizedBox(height: 12),
                  QrImageView(
                    data: candidate.scannable,
                    version: QrVersions.auto,
                    size: 160,
                    backgroundColor: Colors.white,
                  ),
                  const SizedBox(height: 12),
                  SelectableText(candidate.display, textAlign: TextAlign.center),
                  CheckboxListTile(
                    value: compared,
                    onChanged: (value) => updateDialog(() => compared = value == true),
                    title: Text(_videoNoteText(
                      'Я лично проверил совпадение номеров',
                      'Я особисто перевірив збіг номерів',
                      'I independently verified the numbers match',
                    )),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(_chatText('close')),
              ),
              FilledButton(
                onPressed: compared
                    ? () => Navigator.pop(dialogContext, true)
                    : null,
                child: Text(_videoNoteText(
                  'Подтвердить ключ', 'Підтвердити ключ', 'Confirm key',
                )),
              ),
            ],
          ),
        ),
      );
      if (approved != true || !mounted ||
          SocketService.instance.currentUser?.trim() != owner ||
          !SocketService.instance.isAuthenticated) return;

      await SignalE2eeService.instance.acceptVerifiedRemoteBundle(
        peer, bundle, candidate.display,
      );
      await E2eeSettingsService.instance.setFingerprintVerified(
        owner, peer, candidate.display,
      );
      if (!mounted || SocketService.instance.currentUser?.trim() != owner) {
        return;
      }
      setState(() {
        _e2eeVerified = true;
        _e2eeKeyChanged = false;
      });
      _showE2eeNotice(_videoNoteText(
        'Новая защищённая сессия создана',
        'Нову захищену сесію створено',
        'New encrypted session established',
      ));
    } catch (_) {
      if (mounted) {
        _showE2eeNotice(_videoNoteText(
          'Восстановление E2EE не удалось. Ключи не подтверждены.',
          'Не вдалося відновити E2EE. Ключі не підтверджено.',
          'E2EE recovery failed. Keys were not verified.',
        ));
      }
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
              onPressed: () {
                Navigator.pop(context, false);
                unawaited(_showVerifiedE2eeRecovery());
              },
              child: Text(_videoNoteText(
                'Новый ключ', 'Новий ключ', 'New key',
              )),
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
      _presence.clearImmediately();
      if (mounted) {
        setState(() {
          _contactLastSeen = null;
        });
      }
      return;
    }

    // Re-query the peer status after successful authentication.
    if (type == 'login_success') {
      _presence.clearImmediately();
      if (mounted) {
        setState(() {
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

    // Local-only Signal decrypt failure. Never change trust based on this event.
    if (type == 'e2ee_local_decrypt_failure' &&
        data['peer']?.toString().trim() == widget.targetUser &&
        !_e2eeDecryptWarningShown && mounted) {
      _e2eeDecryptWarningShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_showE2eeDecryptWarning());
      });
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

      if (username.toLowerCase() != widget.targetUser.trim().toLowerCase()) {
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

      _presence.updateUser(widget.targetUser, online: online);
      setState(() => _contactLastSeen = lastSeen);

      return;
    }

    if (type == 'chat_recording_activity') {
      final from = data['from']?.toString().trim() ?? '';
      final to = data['to']?.toString().trim() ?? '';
      final kind = data['kind']?.toString().trim() ?? '';
      final active = data['active'];

      if (from == widget.targetUser &&
          to == currentUser &&
          (kind == 'voice' || kind == 'video') &&
          active is bool) {
        _setContactRecordingActivity(kind, active);
      }
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
        final owner = SocketService.instance.currentUser?.trim() ?? '';
        final contact = widget.targetUser.trim();
        if (owner.isNotEmpty && contact.isNotEmpty) {
          unawaited(
            StorageService.mutateMessagesDurably(owner, contact, (current) {
              for (final stored in current) {
                if (stored['id']?.toString().trim() != messageId) {
                  continue;
                }
                final from = stored['from']?.toString().trim() ?? '';
                final to = stored['to']?.toString().trim() ?? '';
                final validParticipants =
                    (from == owner && to == contact) ||
                    (from == contact && to == owner);
                if (!validParticipants) return null;
                if ((stored['isPinned'] == true) == pinned) {
                  return null;
                }
                stored['isPinned'] = pinned;
                return current;
              }
              return null;
            }).then((_) {}).catchError((Object error, StackTrace stack) {
              debugPrint('Durable remote pin update failed: $error');
            }),
          );
        }
      }
      return;
    }

    if (type == 'private_e2ee_edit_sent') {
      // This is an internal ACK emitted only by SocketService after
      // matching the server response to the local encrypted edit outbox.
      final operationValue = data['operation'];
      if (operationValue is! Map) return;

      final operation = Map<String, dynamic>.from(operationValue);
      final owner = SocketService.instance.currentUser?.trim() ?? '';
      final peer = widget.targetUser.trim();
      final eventId = operation['id']?.toString().trim() ?? '';
      final targetId = operation['targetMessageId']?.toString().trim() ?? '';

      if (!mounted ||
          owner.isEmpty ||
          peer.isEmpty ||
          owner == peer ||
          eventId.isEmpty ||
          targetId.isEmpty ||
          data['id']?.toString().trim() != eventId ||
          data['to']?.toString().trim() != peer ||
          operation['from']?.toString().trim() != owner ||
          operation['to']?.toString().trim() != peer) {
        return;
      }

      unawaited(() async {
        try {
          final saved = await StorageService.mutateMessagesDurably(
            owner,
            peer,
            (current) {
              Map<String, dynamic>? originalMessage;

              for (final item in current) {
                if (item['id']?.toString().trim() == targetId &&
                    item['from']?.toString().trim() == owner &&
                    item['to']?.toString().trim() == peer) {
                  originalMessage = Map<String, dynamic>.from(item);
                  break;
                }
              }

              if (originalMessage == null ||
                  !PrivateE2eeEditProtocol.canApply(
                    payload: operation,
                    original: originalMessage,
                    authenticatedFrom: owner,
                    localUser: owner,
                    peer: peer,
                  )) {
                return null;
              }

              for (final item in current) {
                if (item['id']?.toString().trim() == targetId &&
                    item['from']?.toString().trim() == owner &&
                    item['to']?.toString().trim() == peer) {
                  item['text'] = operation['newText'];
                  item['isEdited'] = true;
                  item['editedAt'] = operation['editedAt'];
                  item['lastEditEventId'] = eventId;
                }

                final reply = item['replyTo'];
                if (reply is Map &&
                    reply['id']?.toString().trim() == targetId) {
                  item['replyTo'] = {
                    ...Map<String, dynamic>.from(reply),
                    'text': operation['newText'],
                  };
                }
              }

              return current;
            },
          );

          if (!saved ||
              !mounted ||
              SocketService.instance.currentUser?.trim() != owner ||
              widget.targetUser.trim() != peer) {
            if (!saved &&
                mounted &&
                SocketService.instance.currentUser?.trim() == owner &&
                widget.targetUser.trim() == peer) {
              final confirmed = StorageService.getMessagesVisibleForOwner(
                owner,
                peer,
              ).any(
                (item) =>
                    item['id']?.toString().trim() == targetId &&
                    item['from']?.toString().trim() == owner &&
                    item['to']?.toString().trim() == peer &&
                    item['lastEditEventId']?.toString().trim() == eventId,
              );

              if (confirmed) {
                _loadMessages();
              }
            }
            return;
          }

          setState(() {
            for (final item in _messages) {
              if (item['id']?.toString().trim() == targetId &&
                  item['from']?.toString().trim() == owner &&
                  item['to']?.toString().trim() == peer) {
                item['text'] = operation['newText'];
                item['isEdited'] = true;
                item['editedAt'] = operation['editedAt'];
                item['lastEditEventId'] = eventId;
              }

              final reply = item['replyTo'];
              if (reply is Map &&
                  reply['id']?.toString().trim() == targetId) {
                item['replyTo'] = {
                  ...Map<String, dynamic>.from(reply),
                  'text': operation['newText'],
                };
              }
            }
          });
        } catch (error) {
          debugPrint('Private E2EE edit ACK persistence failed: $error');
        }
      }());

      return;
    }
    if (type == 'private_e2ee_edit') {
      // Only process Signal-decrypted private edits. The transport layer
      // must establish authenticatedFrom from its verified envelope.
      final owner = currentUser.trim();
      final peer = widget.targetUser.trim();
      final from = data['from']?.toString().trim() ?? '';
      final to = data['to']?.toString().trim() ?? '';
      final targetId = data['targetMessageId']?.toString().trim() ?? '';
      final authenticatedFrom =
          data['authenticatedFrom']?.toString().trim() ?? '';

      if (!mounted ||
          owner.isEmpty ||
          peer.isEmpty ||
          targetId.isEmpty ||
          authenticatedFrom.isEmpty ||
          from != authenticatedFrom ||
          !((from == peer && to == owner) ||
              (from == owner && to == peer))) {
        return;
      }

      // A server event is not sufficient proof of authorship. This route
      // depends on Signal verification in SocketService before dispatch.
      unawaited(() async {
        try {
          final saved = await StorageService.mutateMessagesDurably(
            owner,
            peer,
            (current) {
              Map<String, dynamic>? original;

              for (final item in current) {
                if (item['id']?.toString().trim() == targetId &&
                    item['from']?.toString().trim() == from &&
                    item['to']?.toString().trim() == to) {
                  original = Map<String, dynamic>.from(item);
                  break;
                }
              }

              if (original == null ||
                  !PrivateE2eeEditProtocol.canApply(
                    payload: data,
                    original: original,
                    authenticatedFrom: authenticatedFrom,
                    localUser: owner,
                    peer: peer,
                  )) {
                return null;
              }

              for (final item in current) {
                if (item['id']?.toString().trim() == targetId &&
                    item['from']?.toString().trim() == from &&
                    item['to']?.toString().trim() == to) {
                  item['text'] = data['newText'];
                  item['isEdited'] = true;
                  item['editedAt'] = data['editedAt'];
                  item['lastEditEventId'] = data['id'];
                }

                final reply = item['replyTo'];
                if (reply is Map &&
                    reply['id']?.toString().trim() == targetId) {
                  item['replyTo'] = {
                    ...Map<String, dynamic>.from(reply),
                    'text': data['newText'],
                  };
                }
              }

              return current;
            },
          );

          if (!saved || !mounted ||
              SocketService.instance.currentUser?.trim() != owner ||
              widget.targetUser.trim() != peer) {
            // SocketService may already have applied the Signal edit.
            // Refresh from persisted history instead of creating a bubble.
            if (!saved &&
                mounted &&
                SocketService.instance.currentUser?.trim() == owner &&
                widget.targetUser.trim() == peer) {
              final confirmed = StorageService.getMessagesVisibleForOwner(
                owner,
                peer,
              ).any(
                (item) =>
                    item['id']?.toString().trim() == targetId &&
                    item['from']?.toString().trim() == from &&
                    item['to']?.toString().trim() == to &&
                    item['lastEditEventId']?.toString().trim() ==
                        data['id']?.toString().trim(),
              );
              if (confirmed) {
                _loadMessages();
              }
            }
            return;
          }

          setState(() {
            for (final item in _messages) {
              if (item['id']?.toString().trim() == targetId &&
                  item['from']?.toString().trim() == from &&
                  item['to']?.toString().trim() == to) {
                item['text'] = data['newText'];
                item['isEdited'] = true;
                item['editedAt'] = data['editedAt'];
                item['lastEditEventId'] = data['id'];
              }

              final reply = item['replyTo'];
              if (reply is Map &&
                  reply['id']?.toString().trim() == targetId) {
                item['replyTo'] = {
                  ...Map<String, dynamic>.from(reply),
                  'text': data['newText'],
                };
              }
            }
          });
        } catch (error) {
          debugPrint('Protected private edit persistence failed: $error');
        }
      }());

      return;
    }
    if (type == 'message_edited') {
      // Fail closed: legacy private edits carry plaintext.
      // Accept edits only through a future verified E2EE protocol.
      return;
    }

    if (type == 'message_deleted') {
      final currentUser = SocketService.instance.currentUser?.trim() ?? '';
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

      // Save the deletion marker and update Hive through the shared
      // per-chat queue before changing the visible message list.
      unawaited(
        StorageService.deleteForEveryoneDurably(
              currentUser: currentUser,
              peer: widget.targetUser,
              messageId: messageId,
              from: from,
              to: to,
            )
            .then((_) {
              if (!mounted) {
                return;
              }

              setState(() {
                _messages.removeWhere(
                  (message) => _getMessageId(message) == messageId,
                );

                for (final message in _messages) {
                  final rawReply = message['replyTo'];
                  if (rawReply is Map &&
                      rawReply['id']?.toString().trim() == messageId) {
                    message.remove('replyTo');
                  }
                }

                final selectedReplyId = _replyToMessage == null
                    ? ''
                    : _getMessageId(_replyToMessage!);

                if (selectedReplyId == messageId) {
                  _replyToMessage = null;
                }
              });

              if (from == currentUser) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Сообщение удалено без следов'),
                    backgroundColor: FenyvoPalette.surface,
                    duration: Duration(milliseconds: 1100),
                  ),
                );
              }
            })
            .catchError((Object error, StackTrace stack) {
              debugPrint('Guarded chat delete persistence failed: $error');
            }),
      );

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
                  AppLanguageService.instance.text('chatSecureSendFailed'),
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

      final owner = SocketService.instance.currentUser?.trim() ?? '';
      final contact = widget.targetUser.trim();
      if (owner.isNotEmpty && contact.isNotEmpty) {
        final persistedReactions = Map<String, String>.from(reactions);
        unawaited(
          StorageService.mutateMessagesDurably(owner, contact, (current) {
            for (final stored in current) {
              if (stored['id']?.toString().trim() != messageId) {
                continue;
              }
              final sender = stored['from']?.toString().trim() ?? '';
              final recipient = stored['to']?.toString().trim() ?? '';
              final validParticipants =
                  (sender == owner && recipient == contact) ||
                  (sender == contact && recipient == owner);
              if (!validParticipants) return null;
              stored['reactions'] = persistedReactions;
              stored.remove('reactionUsers');
              stored.remove('reaction');
              return current;
            }
            return null;
          }).then((_) {}).catchError((Object error, StackTrace stack) {
            debugPrint('Durable reaction update failed: $error');
          }),
        );
      }

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

    if (!mounted) return;

    final owner = SocketService.instance.currentUser?.trim() ?? '';
    final peer = widget.targetUser.trim();
    final sender = newMessage['from']?.toString().trim() ?? '';
    final recipient = newMessage['to']?.toString().trim() ?? '';

    final validParticipants =
        (sender == owner && recipient == peer) ||
        (sender == peer && recipient == owner);

    if (owner.isEmpty || peer.isEmpty || owner == peer || !validParticipants) {
      return;
    }

    final incomingRealId = newMessage['id']?.toString().trim() ?? '';
    if (incomingRealId.isNotEmpty &&
        StorageService.isMessageHiddenForMe(
          currentUser: owner,
          peer: peer,
          messageId: incomingRealId,
        )) {
      return;
    }
    if (_messages.any((message) => isSameStoredMessage(message, newMessage))) {
      return;
    }

    // Preserve all fields, including E2EE and media metadata.
    final pendingMessage = Map<String, dynamic>.from(newMessage);

    // Always derive the direction from verified chat participants.
    // Do not trust stale isMe metadata from a queued message.
    pendingMessage['isMe'] = sender == owner;

    // Persist first. A deleted or duplicate message must not be
    // inserted into the visible history by this handler.
    unawaited(
      StorageService.appendMessageDurably(
            owner,
            peer,
            pendingMessage,
            allowAppend: () async {
              // Only the incoming direction is filtered by a block.
              // Outgoing messages retain their existing write behavior.
              if (sender == owner) {
                return SocketService.instance.currentUser?.trim() == owner;
              }

              if (SocketService.instance.currentUser?.trim() != owner) {
                return false;
              }

              final blockedAtWrite = await FenyvoTrustService.isBlocked(
                peer,
                owner: owner,
              );

              return !blockedAtWrite &&
                  SocketService.instance.currentUser?.trim() == owner;
            },
          )
          .then((_) {
            if (!mounted) return;

            // The message may have been saved by the chat list first.
            // Never display an absent or deleted record.
            Map<String, dynamic>? visibleMessage;
            final persisted = StorageService.getMessages(owner, peer);

            for (final stored in persisted) {
              if (isSameStoredMessage(stored, pendingMessage)) {
                visibleMessage = Map<String, dynamic>.from(stored);
                break;
              }
            }

            final persistedMessage = visibleMessage;
            if (persistedMessage == null) return;
            _normalizeReactionUsers(persistedMessage);

            // The durable storage path may return metadata saved earlier.
            // Repair the visible direction before the first render.
            persistedMessage['isMe'] = sender == owner;

            if (SocketService.instance.currentUser?.trim() != owner) {
              return;
            }

            // A marker may have been committed while append was pending.
            if (incomingRealId.isNotEmpty &&
                StorageService.isMessageHiddenForMe(
                  currentUser: owner,
                  peer: peer,
                  messageId: incomingRealId,
                )) {
              return;
            }
            if (_contactBlocked && sender == peer) {
              return;
            }

            if (_messages.any(
              (message) => isSameStoredMessage(message, persistedMessage),
            )) {
              return;
            }

            final isIncomingMessage = persistedMessage['isMe'] != true;
            final shouldCountAsNew =
                Platform.isWindows && isIncomingMessage && _showScrollToLatest;

            setState(() {
              _messages.add(persistedMessage);
              _sortMessagesChronologically();

              if (shouldCountAsNew) {
                _newMessagesWhileScrolledUp++;
              }
            });

            _clearUnread();
          })
          .catchError((Object error, StackTrace stack) {
            debugPrint('Guarded open chat append failed: $error');
          }),
    );
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

  Uint8List? _privateMediaBytes(Map<String, dynamic> message) {
    return MediaCacheService.readBytesSync(message);
  }

  String? _privateMediaPath(Map<String, dynamic> message) {
    return MediaCacheService.existingLocalPath(message);
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
                AppLanguageService.instance.text('chatContact'),
                _showShareContactPicker,
              ),
            ],
          ),
        );
      },
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
          mimeType: PrivateAttachmentHelpers.mimeFromName(
            picked.name,
            'image/jpeg',
          ),
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
        fileName: PrivateAttachmentHelpers.basename(picked.path),
        mimeType: PrivateAttachmentHelpers.mimeFromName(
          picked.path,
          'image/jpeg',
        ),
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
          mimeType: PrivateAttachmentHelpers.mimeFromName(
            picked.name,
            'video/mp4',
          ),
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
        fileName: PrivateAttachmentHelpers.basename(picked.path),
        mimeType: PrivateAttachmentHelpers.mimeFromName(
          picked.path,
          'video/mp4',
        ),
        text: '🎥 ${_chatText('video')}',
        maxBytes: 1024 * 1024 * 1024,
      );
    } catch (error) {
      _privateMediaSnack(_chatText('videoPickError', {'error': error}));
    }
  }

  String _videoNoteText(String ru, String uk, String en) {
    final code = AppLanguageService.instance.code.value;
    if (code.startsWith('uk')) return uk;
    if (code.startsWith('en')) return en;
    return ru;
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
      final mime = PrivateAttachmentHelpers.mimeFromName(
        name,
        'application/octet-stream',
      );
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
      final upload = await MediaTransferService.uploadFile(
        path: path,
        fileName: PrivateAttachmentHelpers.safeFileName(fileName),
        mimeType: mimeType,
        messageType: messageType,
        maxBytes: maxBytes,
        encryptForE2ee: true,
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
    switch (PrivateAttachmentHelpers.messageType(message)) {
      case 'image':
        return 'photo.jpg';
      case 'video':
        return 'video.mp4';
      default:
        return 'file.bin';
    }
  }

  // FENYVO_MEDIA_DOWNLOAD_MENU_974
  // Saving media is explicit user action, separate from Save to FENYVO.
  Future<void> _downloadPrivateMessageMedia(
    Map<String, dynamic> message,
  ) async {
    if (message['messageType']?.toString().trim() != 'voice') {
      await _savePrivateAttachment(message);
      return;
    }

    try {
      final path = await _voiceCachePath(message);
      final file = File(path);

      if (!await file.exists() || await file.length() <= 0) {
        throw StateError('voice_file_unavailable');
      }

      final originalName = _privateAttachmentName(message);
      final lowerName = originalName.toLowerCase();

      final hasAudioExtension =
          lowerName.endsWith('.m4a') ||
          lowerName.endsWith('.mp3') ||
          lowerName.endsWith('.ogg') ||
          lowerName.endsWith('.wav') ||
          lowerName.endsWith('.aac');

      final fileName = PrivateAttachmentHelpers.safeFileName(
        hasAudioExtension
            ? originalName
            : 'voice_message_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );

      final lowerFileName = fileName.toLowerCase();
      final mime = lowerFileName.endsWith('.mp3')
          ? 'audio/mpeg'
          : lowerFileName.endsWith('.ogg')
          ? 'audio/ogg'
          : lowerFileName.endsWith('.wav')
          ? 'audio/wav'
          : lowerFileName.endsWith('.aac')
          ? 'audio/aac'
          : 'audio/mp4';

      final savedPath = await FenyvoDownloadService.saveBytes(
        bytes: await file.readAsBytes(),
        fileName: fileName,
        mimeType: mime,
      );

      if (!mounted) return;
      _privateMediaSnack(_chatText('savedToFenyvo', {'path': savedPath}));
    } catch (error) {
      if (!mounted) return;
      _privateMediaSnack(_chatText('fileSaveError', {'error': error}));
    }
  }

  Future<void> _savePrivateAttachment(Map<String, dynamic> message) async {
    final bytes = await MediaCacheService.readBytes(message);
    if (bytes == null || bytes.isEmpty) {
      _privateMediaSnack(_chatText('attachmentDamaged'));
      return;
    }

    final original = PrivateAttachmentHelpers.safeFileName(
      _privateAttachmentName(message),
    );
    final mime =
        message['mimeType']?.toString().trim() ??
        message['voiceMimeType']?.toString().trim() ??
        PrivateAttachmentHelpers.mimeFromName(
          original,
          'application/octet-stream',
        );

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
    final type = PrivateAttachmentHelpers.messageType(message);
    final path = _privateMediaPath(message);
    final bytes = path == null ? _privateMediaBytes(message) : null;
    final networkUrl = MediaCacheService.remoteUrl(message);

    if (type == 'image') {
      if (path == null &&
          (bytes == null || bytes.isEmpty) &&
          networkUrl == null) {
        return Text(
          '📷 ${_chatText('photoUnavailable')}',
          style: TextStyle(color: isMe ? FenyvoPalette.ink : FenyvoPalette.ink),
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
          style: TextStyle(color: isMe ? FenyvoPalette.ink : FenyvoPalette.ink),
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
    final size = PrivateAttachmentSizeFormatter.format(
      message['fileSize'],
      (key) => AppLanguageService.instance.text(key),
    );
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

  Future<void> _deleteVoiceTemporaryFile(String path) async {
    await PrivateVoiceRecordingFiles.deleteIfExists(path);
    _voiceTempPaths.release(path);
  }

  Future<void> _deleteVoiceTemporaryFiles(Iterable<String> paths) async {
    for (final path in paths) {
      await _deleteVoiceTemporaryFile(path);
    }
  }

  // Publish only recording state, never audio content.
  // A refresh keeps the remote indicator alive while recording.
  void _setLocalVoiceRecordingActivity(bool active) {
    _localVoiceActivityTimer?.cancel();
    _localVoiceActivityTimer = null;

    if (active && (!mounted || !_isRecordingVoice)) return;

    SocketService.instance.sendRecordingActivity(
      widget.targetUser,
      kind: 'voice',
      active: active,
    );

    if (!active) return;

    _localVoiceActivityTimer = Timer.periodic(const Duration(seconds: 5), (
      timer,
    ) {
      if (!mounted || !_isRecordingVoice) {
        timer.cancel();
        _localVoiceActivityTimer = null;
        return;
      }
      SocketService.instance.sendRecordingActivity(
        widget.targetUser,
        kind: 'voice',
        active: true,
      );
    });
  }

  Future<void> _startVoiceRecording() {
    return _voiceOperations.start(
      isClosing: _voiceShutdown.isClosing,
      action: _runStartVoiceRecording,
    );
  }

  Future<void> _runStartVoiceRecording() async {
    if (_voiceStopFailed || _voiceStarting || _isRecordingVoice) {
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

      final path = await PrivateVoiceRecordingFiles.createPath();
      _voiceTempPaths.track(path);

      try {
        // FENYVO_VOICE_RECORD_HEX_999
        // Release inline video decoders before acquiring microphone.
        await HexInlineVoiceCoordinator.setVoiceRecordingActive(true);
        await _voiceRecorder.start(path: path);
      } catch (_) {
        try {
          final cleaned = await PrivateVoiceFailedStartCleanup.run(
            path: path,
            stop: _voiceRecorder.stop,
            delete: PrivateVoiceRecordingFiles.deleteIfExists,
          );

          if (cleaned) {
            _voiceTempPaths.release(path);
          }
        } catch (cleanupError) {
          debugPrint('Voice startup cleanup failed: $cleanupError');
        }

        rethrow;
      }

      if (!mounted || !_voicePressActive) {
        final stoppedPath = await _voiceRecorder.stop();
        await HexInlineVoiceCoordinator.setVoiceRecordingActive(false);

        final abandonedPaths = PrivateVoiceTempCleanupPolicy.pathsAfterStop(
          stopSucceeded: true,
          originalPath: path,
          stoppedPath: stoppedPath,
        );

        await _deleteVoiceTemporaryFiles(abandonedPaths);

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

      _voiceTicker.stop();

      _setLocalVoiceRecordingActivity(true);
      _voiceTicker.start(
        onTick: (delta) {
          if (!mounted || !_isRecordingVoice) {
            return;
          }

          final next = _voiceRecordDuration + delta;

          setState(() {
            _voiceRecordDuration = next;
          });

          if (PrivateVoiceRecordingPolicy.shouldAutoFinish(next)) {
            unawaited(_finishVoiceRecording(send: true));
          }
        },
      );
    } catch (error) {
      await HexInlineVoiceCoordinator.setVoiceRecordingActive(false);
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

  Future<void> _finishVoiceRecording({required bool send}) {
    return _voiceOperations.finish(
      isClosing: _voiceShutdown.isClosing,
      action: () => _runFinishVoiceRecording(send: send),
    );
  }

  Future<void> _runFinishVoiceRecording({required bool send}) async {
    if (!_isRecordingVoice) {
      return;
    }

    _voiceTicker.stop();
    _setLocalVoiceRecordingActivity(false);

    final duration = _voiceRecordDuration;

    final fallbackPath = _voiceRecordingPath;

    // IMPORTANT: release the recording UI immediately. Previously the
    // long-press widget could disappear while the pointer was still down,
    // leaving the recorder active with no usable controls.
    _voicePressActive = false;

    if (mounted) {
      setState(() {
        _voiceState.resetAfterFinish();
        _voiceDragStart = null;
      });
    } else {
      _voiceState.resetAfterFinish();
      _voiceDragStart = null;
    }

    String? stoppedPath;

    try {
      stoppedPath = await _voiceRecorder.stop();
    } catch (error) {
      // A failed native stop does not prove the microphone was released.
      // Keep the tracked path for the shutdown coordinator.
      _voiceStopFailed = true;
      debugPrint('Voice recorder stop failed: $error');
      return;
    } finally {
      await HexInlineVoiceCoordinator.setVoiceRecordingActive(false);
    }

    final path = stoppedPath ?? fallbackPath;
    final cleanupPaths = PrivateVoiceTempCleanupPolicy.pathsAfterStop(
      stopSucceeded: true,
      originalPath: fallbackPath,
      stoppedPath: stoppedPath,
    );

    if (path == null || path.isEmpty) {
      return;
    }

    final file = File(path);

    if (PrivateVoiceRecordingPolicy.shouldDiscard(
      send: send,
      duration: duration,
    )) {
      await _deleteVoiceTemporaryFiles(cleanupPaths);

      return;
    }

    if (!SocketService.instance.isConnected) {
      await _deleteVoiceTemporaryFiles(cleanupPaths);

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
      if (PrivateVoiceRecordingPolicy.isTooLarge(fileSize)) {
        _privateMediaSnack(
          AppLanguageService.instance.text('chatVoiceTooLarge'),
        );
        return;
      }

      final upload = await MediaTransferService.uploadFile(
        path: file.path,
        fileName: PrivateAttachmentHelpers.basename(file.path),
        mimeType: 'audio/mp4',
        messageType: 'voice',
        maxBytes: PrivateVoiceRecordingPolicy.maximumFileBytes,
        encryptForE2ee: true,
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
      await _deleteVoiceTemporaryFiles(cleanupPaths);
    }
  }

  void _handleVoiceLongPressStart(LongPressStartDetails details) {
    if (_voiceStarting || _isRecordingVoice || _sendingPrivateMedia) {
      return;
    }

    _voiceDragStart = details.globalPosition;
    _voicePressActive = true;
    _voiceRecordingLocked = false;
    _voiceHoldPendingFinish = null;

    unawaited(_startLockedVoiceRecording());
  }

  void _handleVoiceDragPosition(Offset globalPosition) {
    final start = _voiceDragStart;

    if (!_voicePressActive || start == null || _voiceRecordingLocked) {
      return;
    }

    final delta = globalPosition - start;

    if (PrivateVoiceRecordingGesturePolicy.shouldCancel(delta.dx)) {
      _finishVoicePointerGesture(send: false);
    }
  }

  void _handleVoiceLongPressMove(LongPressMoveUpdateDetails details) {
    _handleVoiceDragPosition(details.globalPosition);
  }

  void _finishVoicePointerGesture({required bool send}) {
    if (!_voicePressActive) return;

    _voicePressActive = false;
    _voiceDragStart = null;

    if (_isRecordingVoice) {
      unawaited(_finishVoiceRecording(send: send));
      return;
    }

    if (_voiceStarting) {
      _voiceHoldPendingFinish = send;
    }
  }

  void _handleVoiceLongPressEnd(LongPressEndDetails details) {
    _finishVoicePointerGesture(send: true);
  }

  Widget _withVoicePointerBridge(Widget child) {
    return PrivateVoicePointerBridge(
      enabled: !Platform.isWindows,
      onMove: _handleVoiceDragPosition,
      onPointerUp: () => _finishVoicePointerGesture(send: true),
      onPointerCancel: () => _finishVoicePointerGesture(send: false),
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
      throw StateError(
        AppLanguageService.instance.text('chatVoiceUnavailable'),
      );
    }
    return path;
  }

  Future<void> _toggleVoicePlayback(Map<String, dynamic> message) async {
    final id = _getMessageId(message);

    // Logs contain only fixed event names, never message identifiers.
    debugPrint('FENYVO_VOICE_TRACE event=play_tapped');

    if (id.isEmpty || !_isVoiceMessage(message)) {
      debugPrint('FENYVO_VOICE_TRACE event=play_rejected');
      return;
    }

    if (_playingVoiceMessageId == id) {
      debugPrint('FENYVO_VOICE_TRACE event=existing_player');
      if (_voiceIsPlaying) {
        await _voicePlayer.pause();
      } else {
        await _voicePlayer.resume();
      }

      return;
    }

    var playbackStage = 'stop';
    try {
      await _voicePlayer.stop();

      playbackStage = 'cache';
      final path = await _voiceCachePath(message);
      debugPrint('FENYVO_VOICE_TRACE event=cache_ready');

      playbackStage = 'file';
      final voiceFile = File(path);
      if (!await voiceFile.exists() || await voiceFile.length() <= 0) {
        throw StateError('voice_file_unavailable');
      }
      debugPrint('FENYVO_VOICE_TRACE event=file_valid');

      if (!mounted) {
        return;
      }

      setState(() {
        _playingVoiceMessageId = id;
        _voicePlaybackPosition = Duration.zero;
        _voicePlaybackDuration = Duration(
          milliseconds: VoiceDurationFormatter.milliseconds(message),
        );
        _voiceIsPlaying = true;
      });

      playbackStage = 'play';
      debugPrint(
        'FENYVO_VOICE_TIMING event=start '
        'expected_ms=${_voicePlaybackDuration.inMilliseconds} '
        'rate=${_voicePlaybackRate.toStringAsFixed(1)}',
      );
      await HexInlineVoiceCoordinator.setVoiceActive(true);
      // FENYVO_VOICE_BYTES_SOURCE_EXPERIMENT_987
      // Android-only source comparison; no encryption or cache changes.
      final audioLength = await voiceFile.length();
      if (Platform.isAndroid && audioLength <= 20 * 1024 * 1024) {
        final lowerPath = path.toLowerCase();
        final mime = lowerPath.endsWith('.ogg')
            ? 'audio/ogg'
            : lowerPath.endsWith('.mp3')
            ? 'audio/mpeg'
            : lowerPath.endsWith('.wav')
            ? 'audio/wav'
            : lowerPath.endsWith('.aac')
            ? 'audio/aac'
            : 'audio/mp4';

        debugPrint('FENYVO_VOICE_TIMING event=bytes_source');
        await _voicePlayer.play(
          BytesSource(await voiceFile.readAsBytes(), mimeType: mime),
        );
      } else {
        debugPrint('FENYVO_VOICE_TIMING event=file_source');
        await _voicePlayer.play(DeviceFileSource(path));
      }
      debugPrint('FENYVO_VOICE_TRACE event=play_returned');

      playbackStage = 'rate';
      await _voicePlayer.setPlaybackRate(_voicePlaybackRate);
      debugPrint('FENYVO_VOICE_TRACE event=rate_applied');
    } catch (error) {
      unawaited(HexInlineVoiceCoordinator.setVoiceActive(false));
      // FENYVO_VOICE_PLAYBACK_DIAGNOSTIC_955
      // No message content, media identifiers, paths, or E2EE data.
      debugPrint(
        'FENYVO_VOICE_PLAYBACK_FAILURE '
        'stage=$playbackStage type=${error.runtimeType}',
      );

      if (mounted) {
        setState(() {
          _voiceIsPlaying = false;
          _playingVoiceMessageId = null;
          _voicePlaybackPosition = Duration.zero;
          _voicePlaybackDuration = Duration.zero;
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
        : Duration(milliseconds: VoiceDurationFormatter.milliseconds(message));

    if (duration.inMilliseconds <= 0) {
      return;
    }

    final safeFraction = VoicePlaybackPolicy.clampSeekFraction(fraction);

    await _voicePlayer.seek(
      Duration(milliseconds: (duration.inMilliseconds * safeFraction).round()),
    );
  }

  Future<void> _cycleVoicePlaybackRate(Map<String, dynamic> message) async {
    final next = VoicePlaybackPolicy.nextRate(_voicePlaybackRate);

    if (mounted) {
      setState(() {
        _voicePlaybackRate = next;
      });
    }

    if (_playingVoiceMessageId == _getMessageId(message)) {
      await _voicePlayer.setPlaybackRate(next);
    }
  }

  Future<void> _startLockedVoiceRecording() async {
    if (_voiceStarting || _isRecordingVoice) return;

    await _startVoiceRecording();

    final pending = _voiceHoldPendingFinish;
    _voiceHoldPendingFinish = null;

    if (pending != null && _isRecordingVoice) {
      await _finishVoiceRecording(send: pending);
    }
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
          color: isMe ? FenyvoPalette.secondary : _gold.withValues(alpha: 0.55),
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
      final owner = currentUser.trim();
      final peer = widget.targetUser.trim();
      final validParticipants =
          (from == owner && to == peer) || (from == peer && to == owner);

      if (owner.isNotEmpty && peer.isNotEmpty && validParticipants) {
        final selectedReaction = reactions[owner];
        unawaited(
          StorageService.mutateMessagesDurably(owner, peer, (current) {
            for (final stored in current) {
              if (stored['id']?.toString().trim() != messageId) {
                continue;
              }

              final sender = stored['from']?.toString().trim() ?? '';
              final recipient = stored['to']?.toString().trim() ?? '';
              final belongsToChat =
                  (sender == owner && recipient == peer) ||
                  (sender == peer && recipient == owner);
              if (!belongsToChat) return null;

              final latestReactions = _getMessageReactions(stored);
              final currentReaction = latestReactions[owner];

              if (currentReaction == selectedReaction) {
                return null;
              }

              if (selectedReaction == null) {
                latestReactions.remove(owner);
              } else {
                latestReactions[owner] = selectedReaction;
              }

              stored['reactions'] = latestReactions;
              stored.remove('reactionUsers');
              stored.remove('reaction');
              return current;
            }
            return null;
          }).then((_) {}).catchError((Object error, StackTrace stack) {
            debugPrint('Durable local reaction update failed: $error');
          }),
        );
      }
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

  GlobalKey _messageItemKey(String messageId) {
    return _messageItemKeys.putIfAbsent(messageId, GlobalKey.new);
  }

  void _updateMessageSearchState(VoidCallback update) {
    setState(update);
  }

  void _updatePinnedMessageState(VoidCallback update) {
    setState(update);
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
      throw Exception(_privateChatGptUiText('emptyMessage'));
    }

    if (!SocketService.instance.isConnected) {
      throw Exception(_privateChatGptUiText('notConnected'));
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
          throw TimeoutException(_privateChatGptUiText('timeout'));
        },
      );
    } finally {
      _chatGptCompleters.remove(requestId);
    }
  }

  void _autoReplyApplyState(VoidCallback update) {
    setState(update);
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
        forwardedFrom.isNotEmpty ||
        message['e2ee'] != true) {
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

    // The legacy plaintext edit API must never be used here.
    // The secure sender validates the original author, recipient,
    // encrypted status and operation before Signal encryption.
    final accepted = SocketService.instance.sendPrivateE2eeEdit(
      originalMessage: Map<String, dynamic>.from(message),
      to: widget.targetUser,
      newText: editedText,
    );

    if (!accepted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _videoNoteText(
              'Не удалось отправить защищённое редактирование',
              'Не вдалося надіслати захищене редагування',
              'Could not send encrypted edit',
            ),
          ),
        ),
      );
    }
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

    final owner = SocketService.instance.currentUser?.trim() ?? '';
    final peer = widget.targetUser.trim();
    final sender = message['from']?.toString().trim() ?? '';
    final recipient = message['to']?.toString().trim() ?? '';
    final realId = message['id']?.toString().trim() ?? '';

    final validParticipants =
        (sender == owner && recipient == peer) ||
        (sender == peer && recipient == owner);
    if (owner.isEmpty || peer.isEmpty || owner == peer || !validParticipants)
      return;

    bool removedDurably;
    try {
      if (realId.isNotEmpty) {
        // Owner-only durable marker. Shared history is preserved.
        removedDurably = await StorageService.hideMessageForMeDurably(
          currentUser: owner,
          peer: peer,
          messageId: realId,
        );
      } else {
        // Compatibility path for legacy records without a real ID.
        removedDurably = await StorageService.mutateMessagesDurably(
          owner,
          peer,
          (current) {
            final index = current.indexWhere((stored) {
              if (stored['from']?.toString().trim() != sender ||
                  stored['to']?.toString().trim() != recipient) {
                return false;
              }
              return (stored['id']?.toString().trim() ?? '').isEmpty &&
                  isSameStoredMessage(stored, message);
            });
            if (index < 0) return null;
            current.removeAt(index);
            return current;
          },
        );
      }
    } catch (error) {
      debugPrint('Delete for me persistence failed: $error');
      return;
    }

    if (!removedDurably ||
        !mounted ||
        SocketService.instance.currentUser?.trim() != owner) {
      return;
    }

    final replyId = _replyToMessage == null
        ? ''
        : _getMessageId(_replyToMessage!);

    setState(() {
      _messages.removeWhere((item) => _getMessageId(item) == messageId);
      if (replyId == messageId) {
        _replyToMessage = null;
      }
    });

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
    final type = PrivateAttachmentHelpers.messageType(message);
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
        _privateMediaSnack(
          AppLanguageService.instance.text('chatMediaServerNotReady'),
        );
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
          throw StateError(
            AppLanguageService.instance.text('chatAttachmentUnavailable'),
          );
        }

        final fileName = PrivateAttachmentHelpers.safeFileName(
          _privateAttachmentName(prepared),
        );
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
                  : PrivateAttachmentHelpers.mimeFromName(
                      fileName,
                      fallbackMime,
                    ));
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
            encryptForE2ee: true,
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
        _privateMediaSnack(
          AppLanguageService.instance.text('chatForwardFailurePrefix') +
              error.toString(),
        );
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
              ? AppLanguageService.instance.text('chatMessageForwarded')
              : AppLanguageService.instance
                    .text('chatSentToRecipients')
                    .replaceAll('{count}', recipients.length.toString()),
        ),
        backgroundColor: FenyvoPalette.surface,
      ),
    );
  }

  // ========================================
  // \u041A\u041E\u041C\u041F\u0410\u041A\u0422\u041D\u0410\u042F \u041A\u041D\u041E\u041F\u041A\u0410 \u0420\u0415\u0410\u041A\u0426\u0418\u0418
  // ========================================

  bool _canOfferLegacyMediaAccess(Map<String, dynamic> message) {
    final socket = SocketService.instance;
    final me = socket.currentUser ?? '';
    final peer = widget.targetUser;

    return socket.isAuthenticated &&
        LegacyMediaRegrantVisibility.canOffer(
          message: message,
          currentUser: me,
          recipient: peer,
          communicationAccepted: socket.isCommunicationAccepted(peer),
        );
  }

  String _legacyMediaAccessText(String ru, String uk, String en) {
    final language = AppLanguageService.instance.code.value
        .toLowerCase()
        .split('-')
        .first;

    if (language == 'uk') return uk;
    if (language == 'en') return en;
    return ru;
  }

  Future<void> _showLegacyMediaAccess(Map<String, dynamic> message) async {
    // Revalidate after the message menu has closed.
    if (!mounted || !_canOfferLegacyMediaAccess(message)) return;

    final mediaId = message['mediaId']?.toString().trim() ?? '';
    final recipient = widget.targetUser;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => LegacyMediaRegrantDialog(
        recipient: recipient,
        languageCode: AppLanguageService.instance.code.value,
        onConfirm: () async {
          // Revalidate the authenticated account and recipient.
          if (!_canOfferLegacyMediaAccess(message)) {
            return const LegacyMediaRegrantResult(
              approved: false,
              reason: 'RECIPIENT_NOT_ELIGIBLE',
            );
          }

          return LegacyMediaRegrantClient.instance.request(
            mediaId: mediaId,
            recipient: recipient,
            ownerConfirmed: true,
          );
        },
      ),
    );
  }

  Future<void> _saveToSaved(Map<String, dynamic> message) async {
    try {
      await SavedMessagesService.save(
        SocketService.instance.currentUser ?? '',
        {
          ...message,
          'messageType': _isVoiceMessage(message)
              ? 'voice'
              : PrivateAttachmentHelpers.messageType(message),
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
                            // FENYVO_MEDIA_DOWNLOAD_MENU_974
                            if (message['messageType']
                                        ?.toString()
                                        .trim() ==
                                    'voice' ||
                                const <String>[
                                  'image',
                                  'video',
                                  'file',
                                  'document',
                                  'audio',
                                ].contains(
                                  PrivateAttachmentHelpers.messageType(
                                    message,
                                  ),
                                )) ...[
                              Divider(
                                height: 1,
                                thickness: 0.6,
                                color: _gold.withValues(alpha: 0.15),
                              ),
                              _buildMessageMenuItem(
                                icon: Icons.download_rounded,
                                title: _legacyMediaAccessText(
                                  'Скачать на телефон',
                                  'Завантажити на телефон',
                                  'Download to device',
                                ),
                                subtitle: _legacyMediaAccessText(
                                  'Сохранить файл в память устройства',
                                  'Зберегти файл у пам’ять пристрою',
                                  'Save the file to this device',
                                ),
                                onTap: () {
                                  closeAndRun(() {
                                    unawaited(
                                      _downloadPrivateMessageMedia(message),
                                    );
                                  });
                                },
                              ),
                            ],
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

                            if (_canOfferLegacyMediaAccess(message)) ...[
                              Divider(
                                height: 1,
                                thickness: 0.6,
                                color: _gold.withValues(alpha: 0.15),
                              ),
                              _buildMessageMenuItem(
                                icon: Icons.lock_open_rounded,
                                title: _legacyMediaAccessText(
                                  'Открыть доступ',
                                  'Надати доступ',
                                  'Grant access',
                                ),
                                subtitle: _legacyMediaAccessText(
                                  'Только для подтверждённого контакта',
                                  'Лише для підтвердженого контакту',
                                  'Accepted contacts only',
                                ),
                                onTap: () {
                                  closeAndRun(() {
                                    unawaited(_showLegacyMediaAccess(message));
                                  });
                                },
                              ),
                            ],
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

  // Flutter State retains ownership of setState.
  void _updateMessageBubbleState(VoidCallback update) {
    setState(update);
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
    // Capture the owner before asynchronous preference reads.
    // Never apply a previous account's result to the current screen.
    final owner = SocketService.instance.currentUser?.trim() ?? '';
    final peer = widget.targetUser.trim();

    if (owner.isEmpty || peer.isEmpty || owner == peer) {
      return;
    }

    final results = await Future.wait<bool>([
      FenyvoTrustService.isTrusted(peer, owner: owner),
      FenyvoTrustService.isBlocked(peer, owner: owner),
      FenyvoTrustService.isReported(peer, owner: owner),
    ]);

    if (!mounted || SocketService.instance.currentUser?.trim() != owner) {
      return;
    }

    setState(() {
      _contactTrusted = results[0];
      _contactBlocked = results[1];
      _contactReported = results[2];
      if (_contactBlocked) {
        _messages.removeWhere((message) => message['isMe'] != true);
      }
    });

    // Request remote state only while the original owner is active.
    if (SocketService.instance.currentUser?.trim() == owner) {
      FenyvoTrustService.requestRemote(peer);
    }
  }

  Future<void> _removeBlockedIncomingMessagesDurably() async {
    final owner = SocketService.instance.currentUser?.trim() ?? '';
    final peer = widget.targetUser.trim();

    if (owner.isEmpty || peer.isEmpty || owner == peer) return;

    try {
      // Preserve shared history. Blocked messages are hidden only for
      // the currently authenticated owner, using durable ID markers.
      if (!await FenyvoTrustService.isBlocked(peer, owner: owner)) {
        return;
      }

      final stored = StorageService.getMessages(owner, peer);
      final incomingIds = stored
          .where((message) {
            return message['from']?.toString().trim() == peer &&
                message['to']?.toString().trim() == owner;
          })
          .map((message) => message['id']?.toString().trim() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet();

      for (final messageId in incomingIds) {
        // A queued operation must not act after account switching or
        // after the contact was unblocked.
        if (SocketService.instance.currentUser?.trim() != owner) {
          return;
        }

        if (!await FenyvoTrustService.isBlocked(peer, owner: owner)) {
          return;
        }

        await StorageService.hideMessageForMeDurably(
          currentUser: owner,
          peer: peer,
          messageId: messageId,
        );
      }

      // Legacy messages without IDs are deliberately left untouched.
      // They need a separate account-safe visibility strategy.
    } catch (error) {
      debugPrint('Blocked incoming owner-only hide failed: $error');
    }
  }

  Future<void> _applyRemoteTrustState(Map<String, dynamic> data) async {
    // Capture the authenticated owner before any asynchronous work.
    final socket = SocketService.instance;
    final owner = socket.currentUser?.trim() ?? '';
    final peer = widget.targetUser.trim();

    if (!mounted ||
        !socket.isAuthenticated ||
        owner.isEmpty ||
        peer.isEmpty ||
        owner == peer) {
      return;
    }

    final trusted = data['trusted'] == true;
    final blocked = data['blocked'] == true;
    final reported = data['reported'] == true;
    final reason = data['reportReason']?.toString() ?? '';
    final changed =
        trusted != _contactTrusted ||
        blocked != _contactBlocked ||
        reported != _contactReported;

    // A socket or account transition can occur during preference writes.
    // Never use an implicit, potentially different account for the keys.
    if (!socket.isAuthenticated || socket.currentUser?.trim() != owner) {
      return;
    }

    await FenyvoTrustService.applyRemote(
      peer,
      trusted: trusted,
      blocked: blocked,
      reported: reported,
      reportReason: reason,
      owner: owner,
    );

    // Never update the UI or start follow-up cleanup for another owner.
    if (!mounted ||
        !socket.isAuthenticated ||
        socket.currentUser?.trim() != owner) {
      return;
    }
    setState(() {
      _contactTrusted = trusted;
      _contactBlocked = blocked;
      _contactReported = reported;
      if (blocked) {
        _messages.removeWhere((message) => message['isMe'] != true);
      }
    });
    if (blocked) unawaited(_removeBlockedIncomingMessagesDurably());
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
        if (next) unawaited(_removeBlockedIncomingMessagesDurably());
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

  // State owns Flutter UI mutations.
  void _updateComposerState(VoidCallback update) {
    setState(update);
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
                    active != null && service.phase == FenyvoPulsePhase.matched;
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
                                  border: Border.all(color: FenyvoPalette.gold),
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
                if (value == 'e2ee_verify') {
                  unawaited(_showE2eeSafetyNumber());
                }
                if (value == 'e2ee_recovery') {
                  unawaited(_showVerifiedE2eeRecovery());
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
                if (SocketService.instance.isAuthenticated)
                  PopupMenuItem(
                    value: 'e2ee_recovery',
                    child: Row(
                      children: [
                        const Icon(Icons.security_rounded, color: Colors.orange),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(_videoNoteText(
                            'Восстановить защищённую переписку',
                            'Відновити захищене листування',
                            'Recover encrypted chat',
                          )),
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
                        Expanded(
                          child: Text(_chatText('chatScreenProtection')),
                        ),
                        Text(
                          _screenSecurityEnabled
                              ? _chatText('commonEnabledShort')
                              : _chatText('commonDisabledShort'),
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
