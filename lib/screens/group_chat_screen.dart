import '../theme/spartan_theme.dart';

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';

import '../services/socket_service.dart';
import '../services/group_call_service.dart';
import '../services/storage_service.dart';
import '../services/media_cache_service.dart';
import '../services/download_service.dart';
import '../services/saved_messages_service.dart';
import '../services/media_transfer_service.dart';
import 'group_add_members_screen.dart';

class GroupChatScreen extends StatefulWidget {
  final Map<String, dynamic> group;

  const GroupChatScreen({super.key, required this.group});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _InlineGroupVideo extends StatefulWidget {
  final Uint8List? bytes;
  final String? filePath;
  final String fileName;
  final String fileSize;
  final String? networkUrl;
  final Map<String, String> httpHeaders;
  final Map<String, dynamic>? mediaMessage;
  final bool isMe;
  final Color gold;
  final Future<void> Function() onSave;

  const _InlineGroupVideo({
    super.key,
    this.bytes,
    this.filePath,
    required this.fileName,
    required this.fileSize,
    this.networkUrl,
    this.httpHeaders = const <String, String>{},
    this.mediaMessage,
    required this.isMe,
    required this.gold,
    required this.onSave,
  });

  @override
  State<_InlineGroupVideo> createState() => _InlineGroupVideoState();
}

class _InlineGroupVideoState extends State<_InlineGroupVideo> {
  VideoPlayerController? _controller;
  File? _tempFile;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_prepare());
  }

  Future<void> _prepare() async {
    try {
      File file;
      var ownsTemp = false;
      final localPath = widget.filePath?.trim() ?? '';

      VideoPlayerController controller;
      if (localPath.isNotEmpty && File(localPath).existsSync()) {
        file = File(localPath);
        controller = VideoPlayerController.file(file);
      } else {
        final mediaMessage = widget.mediaMessage;
        if (mediaMessage != null &&
            MediaCacheService.hasRemoteMedia(mediaMessage)) {
          final cached = await MediaCacheService.cacheRemoteMedia(mediaMessage);
          final cachedPath = MediaCacheService.existingLocalPath(cached);
          if (cachedPath == null || !File(cachedPath).existsSync()) {
            throw StateError('Видео не удалось скачать в кэш');
          }
          file = File(cachedPath);
          controller = VideoPlayerController.file(file);
        } else {
          final networkUrl = widget.networkUrl?.trim() ?? '';
          if (networkUrl.isNotEmpty) {
            file = File('');
            controller = VideoPlayerController.networkUrl(
              Uri.parse(networkUrl),
              httpHeaders: widget.httpHeaders,
            );
          } else {
            final bytes = widget.bytes;
            if (bytes == null || bytes.isEmpty) {
              throw StateError('Видео недоступно');
            }
            final temp = await getTemporaryDirectory();
            final safeName = widget.fileName
                .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
                .trim();
            final extension = safeName.contains('.')
                ? '.${safeName.split('.').last.toLowerCase()}'
                : '.mp4';
            file = File(
              '${temp.path}${Platform.pathSeparator}'
              'spartan_group_video_${DateTime.now().microsecondsSinceEpoch}$extension',
            );
            await file.writeAsBytes(bytes, flush: true);
            ownsTemp = true;
            controller = VideoPlayerController.file(file);
          }
        }
      }

      await controller.initialize();
      controller.addListener(_videoChanged);

      if (!mounted) {
        await controller.dispose();
        if (ownsTemp) {
          try {
            await file.delete();
          } catch (_) {}
        }
        return;
      }

      setState(() {
        _tempFile = ownsTemp ? file : null;
        _controller = controller;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      debugPrint('🎥 Group video prepare failed: $error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _videoChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.position >= controller.value.duration &&
        controller.value.duration > Duration.zero) {
      await controller.seekTo(Duration.zero);
    }
    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }
  }

  @override
  void dispose() {
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_videoChanged);
      unawaited(controller.dispose());
    }
    final file = _tempFile;
    if (file != null) {
      unawaited(
        Future<void>(() async {
          try {
            if (await file.exists()) await file.delete();
          } catch (_) {}
        }),
      );
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const foreground = SpartanPalette.ink;
    if (_loading) {
      return SizedBox(
        width: 270,
        height: 152,
        child: Center(
          child: CircularProgressIndicator(color: SpartanPalette.ink),
        ),
      );
    }

    final controller = _controller;
    if (_error != null ||
        controller == null ||
        !controller.value.isInitialized) {
      return Container(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 330),
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            Icon(
              Icons.videocam_off_outlined,
              color: SpartanPalette.ink,
              size: 30,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Видео не удалось открыть',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Сохранить видео',
              onPressed: () => unawaited(widget.onSave()),
              icon: Icon(Icons.download_rounded, color: foreground),
            ),
          ],
        ),
      );
    }

    final aspect = controller.value.aspectRatio > 0
        ? controller.value.aspectRatio
        : 16 / 9;
    final playing = controller.value.isPlaying;

    return Container(
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 390),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: aspect,
            child: Stack(
              fit: StackFit.expand,
              children: [
                VideoPlayer(controller),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => unawaited(_togglePlayback()),
                    child: Center(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 160),
                        opacity: playing ? 0.0 : 1.0,
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.72),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: widget.gold.withValues(alpha: 0.70),
                            ),
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 38,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 6,
                  child: VideoProgressIndicator(
                    controller,
                    allowScrubbing: true,
                    colors: VideoProgressColors(
                      playedColor: widget.gold,
                      bufferedColor: Colors.white38,
                      backgroundColor: Colors.white24,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Container(
            color: Colors.black.withValues(alpha: 0.88),
            padding: const EdgeInsets.fromLTRB(10, 5, 4, 5),
            child: Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => unawaited(_togglePlayback()),
                  icon: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: widget.gold,
                  ),
                ),
                Expanded(
                  child: Text(
                    widget.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (widget.fileSize.isNotEmpty)
                  Text(
                    widget.fileSize,
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 10.5,
                    ),
                  ),
                IconButton(
                  tooltip: 'Сохранить видео',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => unawaited(widget.onSave()),
                  icon: const Icon(
                    Icons.download_rounded,
                    color: Colors.white70,
                    size: 21,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  static const Color _gold = SpartanPalette.gold;

  static const List<String> _supportedReactions = <String>[
    '❤️',
    '😂',
    '😮',
    '😢',
    '😡',
    '👍',
    '🔥',
    '🎉',
    '👏',
    '🙏',
    '💯',
    '🤣',
    '😎',
    '😍',
    '🤔',
    '😭',
    '😱',
    '🤝',
    '👀',
    '💪',
    '✅',
    '⭐',
    '💔',
  ];

  late Map<String, dynamic> _group;

  final TextEditingController _messageController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();

  final ImagePicker _imagePicker = ImagePicker();
  final AudioRecorder _audioRecorder = AudioRecorder();
  late final AudioPlayer _audioPlayer;

  StreamSubscription<void>? _audioCompleteSubscription;

  bool _recordingVoice = false;
  bool _composerHasText = false;
  DateTime? _voiceStartedAt;
  String? _playingVoiceMessageId;

  final List<Map<String, dynamic>> _messages = <Map<String, dynamic>>[];

  // STAGE 27: group pins + search + forwarding
  final Map<String, GlobalKey> _messageItemKeys = <String, GlobalKey>{};
  final Set<String> _pinnedMessageIds = <String>{};
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  Map<String, dynamic>? _replyToMessage;

  bool _loadingMessages = true;
  bool _sending = false;
  bool _loadingOlderMessages = false;
  bool _hasMoreHistory = true;
  bool _searchMode = false;

  // STAGE 30: group typing indicator
  final Set<String> _typingUsers = <String>{};
  final Map<String, Timer> _typingUserTimers = <String, Timer>{};
  Timer? _typingStopTimer;
  bool _typingSent = false;

  String _searchQuery = '';
  List<String> _searchMatchIds = <String>[];
  int _searchMatchIndex = -1;
  String? _highlightedMessageId;
  Timer? _highlightTimer;

  String get _groupId => _group['id']?.toString().trim() ?? '';

  String get _groupName {
    final name = _group['name']?.toString().trim() ?? '';
    return name.isEmpty ? 'Группа' : name;
  }

  String get _currentUser => SocketService.instance.currentUser ?? '';

  @override
  void initState() {
    super.initState();

    _group = Map<String, dynamic>.from(widget.group);
    SocketService.instance.activeGroupId = _groupId;
    GroupCallService.instance.addListener(_groupCallChanged);
    GroupCallService.instance.requestState(_groupId);

    _scrollController.addListener(_handleHistoryScroll);

    unawaited(_loadPinnedMessageIds());

    SocketService.instance.addMessageHandler(_handleMessage);

    _audioPlayer = AudioPlayer();

    _audioCompleteSubscription = _audioPlayer.onPlayerComplete.listen((_) {
      if (!mounted) return;

      setState(() {
        _playingVoiceMessageId = null;
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_groupId.isNotEmpty) {
        SocketService.instance.getGroupMessages(_groupId);
      }
    });
  }

  @override
  void dispose() {
    if (_typingSent && _groupId.isNotEmpty) {
      SocketService.instance.sendGroupTyping(_groupId, false);
    }

    if (SocketService.instance.activeGroupId == _groupId)
      SocketService.instance.activeGroupId = null;
    _typingStopTimer?.cancel();

    for (final timer in _typingUserTimers.values) {
      timer.cancel();
    }

    _typingUserTimers.clear();

    SocketService.instance.removeMessageHandler(_handleMessage);
    GroupCallService.instance.removeListener(_groupCallChanged);
    _highlightTimer?.cancel();
    unawaited(_audioCompleteSubscription?.cancel());
    _audioCompleteSubscription = null;
    unawaited(_audioPlayer.dispose());
    unawaited(_audioRecorder.dispose());
    _searchController.dispose();
    _searchFocusNode.dispose();
    _messageController.dispose();
    _messageFocusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _groupCallChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _startGroupCall() async {
    if (_recordingVoice) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала завершите запись голосового сообщения'),
        ),
      );
      return;
    }
    final service = GroupCallService.instance;
    final room = service.rooms[_groupId];
    await service.begin(_groupId, _groupName, existingCallId: room?.id);
  }

  Widget _groupCallBanner() {
    final call = GroupCallService.instance.rooms[_groupId];
    if (call == null) return const SizedBox.shrink();
    return Material(
      color: SpartanPalette.blue,
      child: InkWell(
        onTap: _startGroupCall,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              const Icon(Icons.call_rounded, color: SpartanPalette.gold),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Голосовой звонок · ${call.members.length}/4\nПрисоединиться',
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  void _handleHistoryScroll() {
    if (!_scrollController.hasClients ||
        _loadingOlderMessages ||
        !_hasMoreHistory ||
        _messages.isEmpty ||
        _loadingMessages) {
      return;
    }
    if (_scrollController.position.pixels > 180) return;

    final before = _messages.first['time']?.toString().trim() ?? '';
    if (before.isEmpty) return;

    _loadingOlderMessages = true;
    SocketService.instance.getGroupMessages(
      _groupId,
      before: before,
      limit: 60,
    );
  }

  Map<String, dynamic> _dataFromMessage(Map<String, dynamic> msg) {
    final rawData = msg['data'];
    return rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};
  }

  String _messageId(Map<String, dynamic> message) {
    return message['id']?.toString().trim() ?? '';
  }

  String get _pinsPrefsKey => 'spartan_group_pins_$_groupId';

  GlobalKey _messageItemKey(String messageId) {
    return _messageItemKeys.putIfAbsent(messageId, GlobalKey.new);
  }

  Future<void> _loadPinnedMessageIds() async {
    if (_groupId.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_pinsPrefsKey) ?? const <String>[];

    if (!mounted) {
      return;
    }

    setState(() {
      _pinnedMessageIds
        ..clear()
        ..addAll(
          saved
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .take(10),
        );
    });
  }

  Future<void> _savePinnedMessageIds() async {
    if (_groupId.isEmpty) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _pinsPrefsKey,
      _pinnedMessageIds.take(10).toList(),
    );
  }

  Future<void> _prunePinnedMessages() async {
    if (_pinnedMessageIds.isEmpty) {
      return;
    }

    final existingIds = _messages
        .map(_messageId)
        .where((id) => id.isNotEmpty)
        .toSet();

    final before = _pinnedMessageIds.length;

    if (!mounted) {
      return;
    }

    setState(() {
      _pinnedMessageIds.removeWhere((id) => !existingIds.contains(id));
    });

    if (_pinnedMessageIds.length != before) {
      await _savePinnedMessageIds();
    }
  }

  List<Map<String, dynamic>> _pinnedMessages() {
    if (_pinnedMessageIds.isEmpty) {
      return <Map<String, dynamic>>[];
    }

    final result = _messages
        .where((message) => _pinnedMessageIds.contains(_messageId(message)))
        .toList();

    result.sort((a, b) => _messageDateTime(a).compareTo(_messageDateTime(b)));

    return result;
  }

  Future<void> _togglePinnedMessage(Map<String, dynamic> message) async {
    final id = _messageId(message);

    if (id.isEmpty) {
      return;
    }

    final alreadyPinned = _pinnedMessageIds.contains(id);

    if (!alreadyPinned && _pinnedMessageIds.length >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('В группе можно закрепить до 10 сообщений'),
          backgroundColor: SpartanPalette.surface,
        ),
      );
      return;
    }

    setState(() {
      if (alreadyPinned) {
        _pinnedMessageIds.remove(id);
      } else {
        _pinnedMessageIds.add(id);
      }
    });

    await _savePinnedMessageIds();

    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1100),
        backgroundColor: SpartanPalette.surface,
        content: Text(
          alreadyPinned ? 'Сообщение откреплено' : 'Сообщение закреплено',
        ),
      ),
    );
  }

  void _recalculateSearchMatches() {
    final query = _searchQuery.trim().toLowerCase();

    if (query.isEmpty) {
      _searchMatchIds = <String>[];
      _searchMatchIndex = -1;
      return;
    }

    final previousId =
        _searchMatchIndex >= 0 && _searchMatchIndex < _searchMatchIds.length
        ? _searchMatchIds[_searchMatchIndex]
        : '';

    _searchMatchIds = _messages
        .where((message) {
          final text = message['text']?.toString().toLowerCase() ?? '';
          final from = message['from']?.toString().toLowerCase() ?? '';
          return text.contains(query) || from.contains(query);
        })
        .map(_messageId)
        .where((id) => id.isNotEmpty)
        .toList();

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

  void _openSearch() {
    setState(() {
      _searchMode = true;
      _searchQuery = _searchController.text.trim().toLowerCase();
      _recalculateSearchMatches();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _searchFocusNode.requestFocus();
      }
    });
  }

  void _closeSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();

    setState(() {
      _searchMode = false;
      _searchQuery = '';
      _searchMatchIds = <String>[];
      _searchMatchIndex = -1;
    });
  }

  void _onSearchChanged(String value) {
    setState(() {
      _searchQuery = value.trim().toLowerCase();
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
    final index = _messages.indexWhere((message) => _messageId(message) == id);

    if (index < 0) {
      return;
    }

    await _jumpToMessage(_messages[index]);
  }

  Future<void> _nextSearchMatch({required bool newer}) async {
    if (_searchMatchIds.isEmpty) {
      return;
    }

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

  Future<void> _jumpToMessage(Map<String, dynamic> message) async {
    final id = _messageId(message);

    if (id.isEmpty || !_scrollController.hasClients) {
      return;
    }

    _highlightTimer?.cancel();

    setState(() {
      _highlightedMessageId = id;
    });

    final directContext = _messageItemKeys[id]?.currentContext;

    if (directContext != null) {
      await Scrollable.ensureVisible(
        directContext,
        alignment: 0.45,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    } else {
      final index = _messages.indexWhere((item) => _messageId(item) == id);

      if (index >= 0 && _messages.isNotEmpty) {
        final position = _scrollController.position;
        final fraction = _messages.length <= 1
            ? 0.0
            : index / (_messages.length - 1);
        final target = position.maxScrollExtent * fraction;

        await _scrollController.animateTo(
          target.clamp(position.minScrollExtent, position.maxScrollExtent),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );

        await Future<void>.delayed(const Duration(milliseconds: 80));

        final contextAfterScroll = _messageItemKeys[id]?.currentContext;

        if (contextAfterScroll != null) {
          await Scrollable.ensureVisible(
            contextAfterScroll,
            alignment: 0.45,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          );
        }
      }
    }

    _highlightTimer = Timer(const Duration(milliseconds: 2200), () {
      if (!mounted || _highlightedMessageId != id) {
        return;
      }

      setState(() {
        _highlightedMessageId = null;
      });
    });
  }

  Future<void> _sendForwardedGroupMessage({
    required Map<String, dynamic> message,
    required List<String> recipients,
    required String forwardedFrom,
  }) async {
    final type = _messageType(message);
    final text = message['text']?.toString().trim() ?? '';

    if (type == 'text') {
      for (final user in recipients) {
        SocketService.instance.sendMessage(
          user,
          text,
          forwardedFrom: forwardedFrom,
        );
      }
    } else {
      if (!MediaTransferService.isReady) {
        _mediaSnack('Медиа-сервер не готов. Перезайдите в аккаунт.');
        return;
      }

      if (mounted) {
        setState(() => _sending = true);
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

        final fileName = _safeFileName(_attachmentName(prepared));
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
                  : _mimeFromName(fileName, fallbackMime));
        final maxBytes = type == 'video'
            ? 1024 * 1024 * 1024
            : type == 'file'
            ? 512 * 1024 * 1024
            : 20 * 1024 * 1024;
        final upload = await MediaTransferService.uploadFile(
          path: path,
          fileName: fileName,
          mimeType: mimeType,
          messageType: type,
          maxBytes: maxBytes,
        );

        for (final user in recipients) {
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
            );
          }
        }
      } catch (error) {
        _mediaSnack('Не удалось переслать: $error');
        return;
      } finally {
        if (mounted) {
          setState(() => _sending = false);
        }
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          recipients.length == 1
              ? 'Сообщение переслано'
              : 'Отправлено получателям: ${recipients.length}',
        ),
        backgroundColor: SpartanPalette.surface,
      ),
    );
  }

  Future<void> _forwardMessage(Map<String, dynamic> message) async {
    final currentUser = _currentUser;
    final messageType = _messageType(message);
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
        ? '📎 ${_attachmentName(message)}'
        : '';

    if (currentUser.isEmpty || (messageType == 'text' && text.isEmpty)) {
      return;
    }

    final recipients =
        <String>{...StorageService.getChatUsers(currentUser), ..._members()}
          ..remove(currentUser)
          ..removeWhere((user) => user.trim().isEmpty);

    final users = recipients.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (users.isEmpty) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нет доступных чатов для пересылки'),
          backgroundColor: SpartanPalette.surface,
        ),
      );
      return;
    }

    final forwardedFrom =
        message['forwardedFrom']?.toString().trim().isNotEmpty == true
        ? message['forwardedFrom'].toString().trim()
        : (message['from']?.toString().trim().isNotEmpty == true
              ? message['from'].toString().trim()
              : _groupName);

    final selectedUsers = <String>{};
    var filter = '';

    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: SpartanPalette.surface,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filtered = users
                .where((user) => user.toLowerCase().contains(filter))
                .toList();

            return SafeArea(
              child: SizedBox(
                height: MediaQuery.sizeOf(sheetContext).height * 0.72,
                child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(18, 8, 18, 12),
                      child: Row(
                        children: [
                          Icon(Icons.forward_rounded, color: _gold),
                          SizedBox(width: 10),
                          Text(
                            'Переслать сообщение',
                            style: TextStyle(
                              color: SpartanPalette.ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                      child: TextField(
                        onChanged: (value) {
                          setSheetState(() {
                            filter = value.trim().toLowerCase();
                          });
                        },
                        style: const TextStyle(color: SpartanPalette.ink),
                        decoration: InputDecoration(
                          hintText: 'Поиск получателя',
                          hintStyle: const TextStyle(
                            color: SpartanPalette.muted,
                          ),
                          prefixIcon: const Icon(
                            Icons.search_rounded,
                            color: _gold,
                          ),
                          filled: true,
                          fillColor: SpartanPalette.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: SpartanPalette.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _gold.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '↪ Переслано из $_groupName • $forwardedFrom',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _gold,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: SpartanPalette.secondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final user = filtered[index];
                          final selected = selectedUsers.contains(user);

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: SpartanPalette.surface,
                              child: Text(
                                user.isEmpty ? '?' : user[0].toUpperCase(),
                                style: const TextStyle(
                                  color: _gold,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                            title: Text(
                              user,
                              style: const TextStyle(
                                color: SpartanPalette.ink,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: Icon(
                              selected
                                  ? Icons.check_circle_rounded
                                  : Icons.circle_outlined,
                              color: selected ? _gold : SpartanPalette.muted,
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
                    Padding(
                      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: selectedUsers.isEmpty
                              ? null
                              : () {
                                  final targets = selectedUsers.toList();
                                  Navigator.of(sheetContext).pop();

                                  unawaited(
                                    _sendForwardedGroupMessage(
                                      message: message,
                                      recipients: targets,
                                      forwardedFrom:
                                          '$_groupName • $forwardedFrom',
                                    ),
                                  );
                                },
                          icon: const Icon(Icons.send_rounded),
                          label: Text(
                            selectedUsers.isEmpty
                                ? 'Выберите получателя'
                                : selectedUsers.length == 1
                                ? 'Отправить'
                                : 'Отправить (${selectedUsers.length})',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: SpartanPalette.blue,
                            foregroundColor: SpartanPalette.ink,
                            disabledBackgroundColor: SpartanPalette.surface,
                            disabledForegroundColor: SpartanPalette.muted,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPinnedMessagesBanner() {
    final pinned = _pinnedMessages();

    if (pinned.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      color: SpartanPalette.surface,
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      child: Row(
        children: [
          const Icon(Icons.push_pin_rounded, color: _gold, size: 19),
          const SizedBox(width: 7),
          Text(
            '${pinned.length}',
            style: const TextStyle(color: _gold, fontWeight: FontWeight.w800),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 42,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: pinned.length,
                separatorBuilder: (_, __) => const SizedBox(width: 7),
                itemBuilder: (context, index) {
                  final message = pinned[index];
                  final from = message['from']?.toString().trim() ?? '';
                  final text = message['text']?.toString().trim() ?? '';

                  return Material(
                    color: SpartanPalette.surface,
                    borderRadius: BorderRadius.circular(12),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        unawaited(_jumpToMessage(message));
                      },
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 250),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _gold.withValues(alpha: 0.30),
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (from.isNotEmpty) ...[
                              Text(
                                from,
                                style: const TextStyle(
                                  color: _gold,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                text.isEmpty ? 'Сообщение' : text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: SpartanPalette.secondary,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            const SizedBox(width: 4),
                            SizedBox(
                              width: 28,
                              height: 28,
                              child: IconButton(
                                tooltip: 'Открепить',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () {
                                  unawaited(_togglePinnedMessage(message));
                                },
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: SpartanPalette.secondary,
                                  size: 18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    final matchCount = _searchMatchIds.length;
    final current = _searchMatchIndex >= 0 ? _searchMatchIndex + 1 : 0;

    return Container(
      color: SpartanPalette.surface,
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
              onChanged: _onSearchChanged,
              style: const TextStyle(color: SpartanPalette.ink),
              decoration: InputDecoration(
                hintText: 'Поиск по группе',
                hintStyle: const TextStyle(color: SpartanPalette.muted),
                prefixIcon: const Icon(Icons.search_rounded, color: _gold),
                suffixText: _searchQuery.isEmpty
                    ? null
                    : '$current/$matchCount',
                suffixStyle: const TextStyle(
                  color: _gold,
                  fontWeight: FontWeight.w700,
                ),
                filled: true,
                fillColor: SpartanPalette.surface,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Предыдущее',
            onPressed: matchCount == 0
                ? null
                : () {
                    unawaited(_nextSearchMatch(newer: false));
                  },
            icon: const Icon(Icons.keyboard_arrow_up_rounded, color: _gold),
          ),
          IconButton(
            tooltip: 'Следующее',
            onPressed: matchCount == 0
                ? null
                : () {
                    unawaited(_nextSearchMatch(newer: true));
                  },
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _gold),
          ),
          IconButton(
            tooltip: 'Закрыть поиск',
            onPressed: _closeSearch,
            icon: const Icon(
              Icons.close_rounded,
              color: SpartanPalette.secondary,
            ),
          ),
        ],
      ),
    );
  }

  // ========================================
  // GROUP TYPING - STAGE 30
  // ========================================

  void _handleGroupTextChanged(String value) {
    final hasText = value.trim().isNotEmpty;

    if (hasText != _composerHasText && mounted) {
      setState(() {
        _composerHasText = hasText;
      });
    }

    _typingStopTimer?.cancel();

    if (!hasText) {
      _stopGroupTyping();
      return;
    }

    if (!_typingSent) {
      _typingSent = true;

      SocketService.instance.sendGroupTyping(_groupId, true);
    }

    _typingStopTimer = Timer(
      const Duration(milliseconds: 1600),
      _stopGroupTyping,
    );
  }

  void _stopGroupTyping() {
    _typingStopTimer?.cancel();
    _typingStopTimer = null;

    if (!_typingSent) {
      return;
    }

    _typingSent = false;

    SocketService.instance.sendGroupTyping(_groupId, false);
  }

  void _setGroupUserTyping(String username, bool isTyping) {
    final user = username.trim();

    if (user.isEmpty || user == _currentUser) {
      return;
    }

    _typingUserTimers[user]?.cancel();

    if (!isTyping) {
      _typingUserTimers.remove(user);

      if (mounted && _typingUsers.contains(user)) {
        setState(() {
          _typingUsers.remove(user);
        });
      }

      return;
    }

    if (mounted && !_typingUsers.contains(user)) {
      setState(() {
        _typingUsers.add(user);
      });
    }

    _typingUserTimers[user] = Timer(const Duration(seconds: 4), () {
      _typingUserTimers.remove(user);

      if (!mounted || !_typingUsers.contains(user)) {
        return;
      }

      setState(() {
        _typingUsers.remove(user);
      });
    });
  }

  String _groupSubtitleText(int memberCount) {
    final users =
        _typingUsers
            .where((user) => user.trim().isNotEmpty && user != _currentUser)
            .toList()
          ..sort();

    if (users.isEmpty) {
      return '$memberCount участников';
    }

    if (users.length == 1) {
      return '${users.first} печатает...';
    }

    if (users.length == 2) {
      return '${users[0]} и ${users[1]} печатают...';
    }

    return '${users.length} участника печатают...';
  }

  void _handleMessage(Map<String, dynamic> msg) {
    if (!mounted) {
      return;
    }

    final type = msg['type']?.toString() ?? '';
    final data = _dataFromMessage(msg);

    if (type == 'group_updated') {
      final rawGroup = data['group'];

      if (rawGroup is! Map) {
        return;
      }

      final group = Map<String, dynamic>.from(rawGroup);
      final incomingId = group['id']?.toString().trim() ?? '';

      if (incomingId != _groupId) {
        return;
      }

      setState(() {
        _group = group;
      });
      return;
    }

    if (type == 'group_typing') {
      final incomingGroupId = data['groupId']?.toString().trim() ?? '';

      if (incomingGroupId != _groupId) {
        return;
      }

      final from = data['from']?.toString().trim() ?? '';

      final isTyping = data['isTyping'] == true;

      _setGroupUserTyping(from, isTyping);

      return;
    }

    if (type == 'group_messages') {
      final incomingGroupId = data['groupId']?.toString().trim() ?? '';
      if (incomingGroupId != _groupId) return;

      final rawMessages = data['messages'];
      final messages = rawMessages is List
          ? rawMessages
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .where((item) => _messageId(item).isNotEmpty)
                .toList()
          : <Map<String, dynamic>>[];
      messages.sort(
        (a, b) => _messageDateTime(a).compareTo(_messageDateTime(b)),
      );

      final before = data['before']?.toString().trim() ?? '';
      final hasMore = data['hasMore'] == true;
      final isOlderPage = before.isNotEmpty;
      final oldMaxExtent = _scrollController.hasClients
          ? _scrollController.position.maxScrollExtent
          : 0.0;

      setState(() {
        if (isOlderPage) {
          final existingIds = _messages.map(_messageId).toSet();
          final older = messages.where(
            (item) => !existingIds.contains(_messageId(item)),
          );
          _messages.insertAll(0, older);
        } else {
          _messages
            ..clear()
            ..addAll(messages);
        }
        _hasMoreHistory = hasMore;
        _loadingOlderMessages = false;
        _loadingMessages = false;
        _sending = false;
        _recalculateSearchMatches();
      });

      if (isOlderPage) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_scrollController.hasClients) return;
          final newMax = _scrollController.position.maxScrollExtent;
          final delta = newMax - oldMaxExtent;
          if (delta > 0) {
            _scrollController.jumpTo(delta.clamp(0.0, newMax).toDouble());
          }
        });
      } else {
        _scrollToBottom(animated: false);
      }
      unawaited(_prunePinnedMessages());
      return;
    }

    if (type == 'group_message') {
      final incomingGroupId = data['groupId']?.toString().trim() ?? '';

      if (incomingGroupId != _groupId) {
        return;
      }

      final id = data['id']?.toString().trim() ?? '';

      if (id.isEmpty) {
        return;
      }

      final alreadyExists = _messages.any(
        (message) => _messageId(message) == id,
      );

      setState(() {
        if (!alreadyExists) {
          _messages.add(Map<String, dynamic>.from(data));
          _messages.sort(
            (a, b) => _messageDateTime(a).compareTo(_messageDateTime(b)),
          );
        }

        if (data['from']?.toString() == _currentUser) {
          _sending = false;
        }

        _recalculateSearchMatches();
      });

      _scrollToBottom();
      return;
    }

    if (type == 'group_message_edited') {
      final incomingGroupId = data['groupId']?.toString().trim() ?? '';

      if (incomingGroupId != _groupId) {
        return;
      }

      final rawMessage = data['message'];

      if (rawMessage is! Map) {
        return;
      }

      final updated = Map<String, dynamic>.from(rawMessage);
      final id = _messageId(updated);

      if (id.isEmpty) {
        return;
      }

      final index = _messages.indexWhere(
        (message) => _messageId(message) == id,
      );

      if (index < 0) {
        return;
      }

      setState(() {
        _messages[index] = updated;
        _recalculateSearchMatches();
      });
      return;
    }

    if (type == 'group_message_deleted') {
      final incomingGroupId = data['groupId']?.toString().trim() ?? '';

      if (incomingGroupId != _groupId) {
        return;
      }

      final id = data['messageId']?.toString().trim() ?? '';

      if (id.isEmpty) {
        return;
      }

      setState(() {
        _messages.removeWhere((message) => _messageId(message) == id);

        _messageItemKeys.remove(id);
        _pinnedMessageIds.remove(id);

        if (_replyToMessage != null && _messageId(_replyToMessage!) == id) {
          _replyToMessage = null;
        }

        _recalculateSearchMatches();
      });

      unawaited(_savePinnedMessageIds());
      return;
    }

    if (type == 'group_reaction_update') {
      final incomingGroupId = data['groupId']?.toString().trim() ?? '';

      if (incomingGroupId != _groupId) {
        return;
      }

      final id = data['messageId']?.toString().trim() ?? '';
      final index = _messages.indexWhere(
        (message) => _messageId(message) == id,
      );

      if (index < 0) {
        return;
      }

      final rawReactions = data['reactions'];
      final reactions = rawReactions is Map
          ? Map<String, dynamic>.from(rawReactions)
          : <String, dynamic>{};

      setState(() {
        _messages[index] = <String, dynamic>{
          ..._messages[index],
          'reactions': reactions,
        };
      });
      return;
    }

    if (type == 'group_error') {
      final incomingGroupId = data['groupId']?.toString().trim() ?? '';

      if (incomingGroupId.isNotEmpty && incomingGroupId != _groupId) {
        return;
      }

      final reason =
          data['reason']?.toString().trim() ?? 'Ошибка группового чата';

      setState(() {
        _sending = false;
        _loadingMessages = false;
        _loadingOlderMessages = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(reason),
          backgroundColor: SpartanPalette.surface,
        ),
      );
    }
  }

  DateTime _messageDateTime(Map<String, dynamic> message) {
    final raw = message['time']?.toString().trim() ?? '';

    return DateTime.tryParse(raw)?.toLocal() ??
        DateTime.fromMillisecondsSinceEpoch(0);
  }

  List<String> _members() {
    final rawMembers = _group['members'];

    if (rawMembers is! List) {
      return <String>[];
    }

    return rawMembers
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  String _formatTime(dynamic rawValue) {
    final date = DateTime.tryParse(rawValue?.toString() ?? '')?.toLocal();

    if (date == null) {
      return '';
    }

    return '${_twoDigits(date.hour)}:${_twoDigits(date.minute)}';
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final difference = today.difference(target).inDays;

    if (difference == 0) {
      return 'Сегодня';
    }

    if (difference == 1) {
      return 'Вчера';
    }

    return '${_twoDigits(date.day)}.${_twoDigits(date.month)}.${date.year}';
  }

  bool _needsDateSeparator(int index) {
    if (index <= 0) {
      return true;
    }

    final current = _messageDateTime(_messages[index]);
    final previous = _messageDateTime(_messages[index - 1]);

    return current.year != previous.year ||
        current.month != previous.month ||
        current.day != previous.day;
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }

      final target = _scrollController.position.maxScrollExtent;

      if (animated) {
        unawaited(
          _scrollController.animateTo(
            target,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
          ),
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  Map<String, dynamic>? _replySnapshot() {
    final message = _replyToMessage;

    if (message == null) {
      return null;
    }

    final id = _messageId(message);
    final from = message['from']?.toString().trim() ?? '';
    final text = message['text']?.toString().trim() ?? '';

    if (id.isEmpty || from.isEmpty || text.isEmpty) {
      return null;
    }

    return <String, dynamic>{'id': id, 'from': from, 'text': text};
  }

  // ========================================
  // STAGE 28 - GROUP MEDIA
  // ========================================

  String _messageType(Map<String, dynamic> message) {
    final value = message['messageType']?.toString().trim().toLowerCase() ?? '';
    return value.isEmpty ? 'text' : value;
  }

  bool _isVideoAttachment(Map<String, dynamic> message) {
    final type = _messageType(message);
    if (type == 'video') return true;

    final mime = message['mimeType']?.toString().trim().toLowerCase() ?? '';
    if (mime.startsWith('video/')) return true;

    final name = message['fileName']?.toString().trim().toLowerCase() ?? '';

    return name.endsWith('.mp4') ||
        name.endsWith('.mov') ||
        name.endsWith('.m4v') ||
        name.endsWith('.webm') ||
        name.endsWith('.avi') ||
        name.endsWith('.mkv');
  }

  Uint8List? _mediaBytes(Map<String, dynamic> message) {
    return MediaCacheService.readBytesSync(message);
  }

  String? _mediaPath(Map<String, dynamic> message) {
    return MediaCacheService.existingLocalPath(message);
  }

  String _basename(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.isEmpty ? path : parts.last;
  }

  String _safeFileName(String name) {
    final clean = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    return clean.isEmpty
        ? 'spartan_${DateTime.now().millisecondsSinceEpoch}.bin'
        : clean;
  }

  String _mimeFromName(String name, String fallback) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt')) return 'text/plain';
    return fallback;
  }

  String _humanSize(dynamic raw) {
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

  String _durationText(dynamic raw) {
    final ms = raw is num
        ? raw.toInt()
        : int.tryParse(raw?.toString() ?? '') ?? 0;
    final seconds = (ms / 1000).round().clamp(0, 86400);
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  void _mediaSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: SpartanPalette.surface),
    );
  }

  Future<void> _showAttachmentMenu() async {
    if (_sending) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: SpartanPalette.surface,
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
                color: SpartanPalette.ink,
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
              item(Icons.photo_library_outlined, 'Фото', _pickGroupImage),
              item(Icons.video_library_outlined, 'Видео', _pickGroupVideo),
              item(Icons.attach_file_rounded, 'Файл', _pickGroupFile),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickGroupImage() async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
      );
      if (picked == null) return;
      await _sendGroupMediaFile(
        messageType: 'image',
        path: picked.path,
        fileName: _basename(picked.path),
        mimeType: _mimeFromName(picked.path, 'image/jpeg'),
        text: '📷 Фото',
        maxBytes: 20 * 1024 * 1024,
      );
    } catch (error) {
      _mediaSnack('Не удалось выбрать фото: $error');
    }
  }

  Future<void> _pickGroupVideo() async {
    try {
      final picked = await _imagePicker.pickVideo(source: ImageSource.gallery);
      if (picked == null) return;
      await _sendGroupMediaFile(
        messageType: 'video',
        path: picked.path,
        fileName: _basename(picked.path),
        mimeType: _mimeFromName(picked.path, 'video/mp4'),
        text: '🎥 Видео',
        maxBytes: 1024 * 1024 * 1024,
      );
    } catch (error) {
      _mediaSnack('Не удалось выбрать видео: $error');
    }
  }

  Future<void> _pickGroupFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.single;
      final path = picked.path?.trim() ?? '';
      if (path.isEmpty) {
        _mediaSnack('Не удалось получить путь к файлу');
        return;
      }
      final name = picked.name.trim().isEmpty ? 'file.bin' : picked.name.trim();
      final mime = _mimeFromName(name, 'application/octet-stream');
      final isVideo = mime.startsWith('video/');
      await _sendGroupMediaFile(
        messageType: isVideo ? 'video' : 'file',
        path: path,
        fileName: name,
        mimeType: mime,
        text: isVideo ? '🎥 Видео' : '📎 $name',
        maxBytes: isVideo ? 1024 * 1024 * 1024 : 512 * 1024 * 1024,
      );
    } catch (error) {
      _mediaSnack('Не удалось выбрать файл: $error');
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (_sending) return;
    if (_recordingVoice) {
      await _finishVoiceRecording();
      return;
    }
    try {
      if (!await _audioRecorder.hasPermission()) {
        _mediaSnack('Нет разрешения на микрофон');
        return;
      }
      final temp = await getTemporaryDirectory();
      final path =
          '${temp.path}${Platform.pathSeparator}spartan_group_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 96000,
          sampleRate: 44100,
        ),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _recordingVoice = true;
        _voiceStartedAt = DateTime.now();
      });
    } catch (error) {
      _mediaSnack('Не удалось начать запись: $error');
    }
  }

  Future<void> _finishVoiceRecording() async {
    final started = _voiceStartedAt;
    try {
      final path = await _audioRecorder.stop();
      final durationMs = started == null
          ? 0
          : DateTime.now().difference(started).inMilliseconds;
      if (mounted) {
        setState(() {
          _recordingVoice = false;
          _voiceStartedAt = null;
        });
      }
      if (path == null || path.trim().isEmpty || durationMs < 300) return;
      final file = File(path);
      if (!await file.exists()) return;
      await _sendGroupMediaFile(
        messageType: 'voice',
        path: file.path,
        fileName: _basename(path),
        mimeType: 'audio/mp4',
        text: '🎙️ Голосовое сообщение',
        maxBytes: 20 * 1024 * 1024,
        voiceDurationMs: durationMs,
      );
      try {
        await file.delete();
      } catch (_) {}
    } catch (error) {
      if (mounted) {
        setState(() {
          _recordingVoice = false;
          _voiceStartedAt = null;
        });
      }
      _mediaSnack('Не удалось отправить голосовое: $error');
    }
  }

  Future<void> _sendGroupMediaFile({
    required String messageType,
    required String path,
    required String fileName,
    required String mimeType,
    required String text,
    required int maxBytes,
    int? voiceDurationMs,
  }) async {
    if (_groupId.isEmpty || _sending) return;
    if (!SocketService.instance.isConnected) {
      _mediaSnack('Нет соединения с сервером');
      return;
    }
    if (!MediaTransferService.isReady) {
      _mediaSnack('Медиа-сервер не готов. Перезайдите в аккаунт.');
      return;
    }

    final replyTo = _replySnapshot();
    setState(() {
      _sending = true;
      _replyToMessage = null;
      _composerHasText = false;
    });

    try {
      final upload = await MediaTransferService.uploadFile(
        path: path,
        fileName: _safeFileName(fileName),
        mimeType: mimeType,
        messageType: messageType,
        maxBytes: maxBytes,
      );
      SocketService.instance.sendGroupMediaMessage(
        _groupId,
        messageType: messageType,
        mediaId: upload.mediaId,
        fileName: upload.fileName,
        fileSize: upload.fileSize,
        mimeType: upload.mimeType,
        text: text,
        voiceDurationMs: voiceDurationMs,
        replyTo: replyTo,
      );
    } catch (error) {
      if (mounted) setState(() => _sending = false);
      _mediaSnack('Не удалось отправить файл: $error');
    }
  }

  Future<void> _playVoiceMessage(Map<String, dynamic> message) async {
    final id = _messageId(message);
    if (id.isEmpty) {
      _mediaSnack('Голосовое сообщение повреждено');
      return;
    }

    try {
      if (_playingVoiceMessageId == id) {
        await _audioPlayer.stop();
        if (mounted) {
          setState(() {
            _playingVoiceMessageId = null;
          });
        }
        return;
      }

      await _audioPlayer.stop();

      var path = _mediaPath(message);
      if (path == null) {
        final cached = MediaCacheService.hasRemoteMedia(message)
            ? await MediaCacheService.cacheRemoteMedia(message)
            : await MediaCacheService.cacheEmbeddedMedia(message);
        path = MediaCacheService.existingLocalPath(cached);
        if (path != null) {
          message
            ..clear()
            ..addAll(cached);
        }
      }

      if (path == null) {
        _mediaSnack('Голосовое сообщение недоступно');
        return;
      }

      await _audioPlayer.play(DeviceFileSource(path));

      if (mounted) {
        setState(() {
          _playingVoiceMessageId = id;
        });
      }
    } catch (error) {
      _mediaSnack('Не удалось воспроизвести голосовое: $error');
    }
  }

  String _attachmentName(Map<String, dynamic> message) {
    final name = message['fileName']?.toString().trim() ?? '';
    if (name.isNotEmpty) return name;

    switch (_messageType(message)) {
      case 'image':
        return 'photo.jpg';
      case 'video':
        return 'video.mp4';
      case 'voice':
        return 'voice.m4a';
      default:
        return 'file.bin';
    }
  }

  Future<void> _saveMediaAttachment(Map<String, dynamic> message) async {
    final bytes = await MediaCacheService.readBytes(message);
    if (bytes == null || bytes.isEmpty) {
      _mediaSnack('Вложение повреждено');
      return;
    }

    final original = _safeFileName(_attachmentName(message));
    final mime =
        message['mimeType']?.toString().trim() ??
        _mimeFromName(original, 'application/octet-stream');

    try {
      final savedPath = await SpartanDownloadService.saveBytes(
        bytes: bytes,
        fileName: original,
        mimeType: mime,
      );
      _mediaSnack('Сохранено в Spartan Chat: $savedPath');
    } catch (error) {
      _mediaSnack('Не удалось сохранить файл: $error');
    }
  }

  void _openGroupImage(Map<String, dynamic> message) {
    final path = _mediaPath(message);
    final bytes = path == null ? _mediaBytes(message) : null;
    final networkUrl = MediaCacheService.remoteUrl(message);
    if (path == null &&
        (bytes == null || bytes.isEmpty) &&
        networkUrl == null) {
      _mediaSnack('Фото повреждено');
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
                      tooltip: 'Скачать',
                      onPressed: () => unawaited(_saveMediaAttachment(message)),
                      icon: const Icon(Icons.download_rounded),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
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

  Widget _buildMediaBody(Map<String, dynamic> message, {required bool isMe}) {
    final type = _messageType(message);

    if (type == 'image') {
      final path = _mediaPath(message);
      final bytes = path == null ? _mediaBytes(message) : null;
      final networkUrl = MediaCacheService.remoteUrl(message);

      if (path == null &&
          (bytes == null || bytes.isEmpty) &&
          networkUrl == null) {
        return Text(
          '📷 Фото недоступно',
          style: TextStyle(
            color: isMe ? SpartanPalette.ink : SpartanPalette.ink,
          ),
        );
      }

      return GestureDetector(
        onTap: () => _openGroupImage(message),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minWidth: 160,
              maxWidth: 420,
              maxHeight: 360,
            ),
            child: path != null
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
      );
    }

    if (type == 'voice') {
      final playing = _playingVoiceMessageId == _messageId(message);

      return Container(
        constraints: const BoxConstraints(minWidth: 210, maxWidth: 330),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: playing ? 'Стоп' : 'Воспроизвести',
              onPressed: () => unawaited(_playVoiceMessage(message)),
              icon: Icon(
                playing
                    ? Icons.stop_circle_rounded
                    : Icons.play_circle_fill_rounded,
                color: isMe ? SpartanPalette.ink : _gold,
                size: 34,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Голосовое сообщение',
                    style: TextStyle(
                      color: isMe ? SpartanPalette.ink : SpartanPalette.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _durationText(message['voiceDurationMs']),
                    style: TextStyle(
                      color: isMe
                          ? SpartanPalette.secondary
                          : SpartanPalette.secondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_isVideoAttachment(message)) {
      final path = _mediaPath(message);
      final bytes = path == null ? _mediaBytes(message) : null;
      final networkUrl = MediaCacheService.remoteUrl(message);

      if (path == null &&
          (bytes == null || bytes.isEmpty) &&
          networkUrl == null) {
        return Text(
          '🎥 Видео недоступно',
          style: TextStyle(
            color: isMe ? SpartanPalette.ink : SpartanPalette.ink,
          ),
        );
      }

      return _InlineGroupVideo(
        key: ValueKey<String>('group_video_${_messageId(message)}'),
        bytes: bytes,
        filePath: path,
        fileName: _attachmentName(message),
        fileSize: _humanSize(message['fileSize']),
        networkUrl: networkUrl,
        httpHeaders: MediaCacheService.remoteHeaders,
        mediaMessage: Map<String, dynamic>.from(message),
        isMe: isMe,
        gold: SpartanPalette.mediaAccent,
        onSave: () => _saveMediaAttachment(message),
      );
    }

    if (type == 'file') {
      final name = _attachmentName(message);
      final size = _humanSize(message['fileSize']);

      return Container(
        constraints: const BoxConstraints(minWidth: 230, maxWidth: 390),
        padding: const EdgeInsets.all(9),
        decoration: BoxDecoration(
          color: isMe
              ? SpartanPalette.surface.withValues(alpha: 0.08)
              : SpartanPalette.surface.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              color: isMe ? SpartanPalette.ink : _gold,
              size: 34,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: isMe ? SpartanPalette.ink : SpartanPalette.ink,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (size.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      size,
                      style: TextStyle(
                        color: isMe
                            ? SpartanPalette.secondary
                            : SpartanPalette.secondary,
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            IconButton(
              tooltip: 'Сохранить',
              onPressed: () => unawaited(_saveMediaAttachment(message)),
              icon: Icon(
                Icons.download_rounded,
                color: isMe ? SpartanPalette.ink : _gold,
              ),
            ),
          ],
        ),
      );
    }

    final text = message['text']?.toString() ?? '';
    return Text(
      text,
      style: TextStyle(
        color: isMe ? SpartanPalette.ink : SpartanPalette.ink,
        fontSize: 15.5,
        height: 1.28,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  void _sendMessage() {
    if (_sending) {
      return;
    }

    final text = _messageController.text.trim();

    if (_groupId.isEmpty || text.isEmpty) {
      return;
    }

    if (!SocketService.instance.isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нет соединения с сервером')),
      );
      return;
    }

    final replyTo = _replySnapshot();

    setState(() {
      _sending = true;
      _replyToMessage = null;
      _composerHasText = false;
    });

    _messageController.clear();
    _stopGroupTyping();

    SocketService.instance.sendGroupMessage(_groupId, text, replyTo: replyTo);

    _messageFocusNode.requestFocus();
  }

  void _startReply(Map<String, dynamic> message) {
    setState(() {
      _replyToMessage = Map<String, dynamic>.from(message);
    });

    _messageFocusNode.requestFocus();
  }

  void _cancelReply() {
    if (_replyToMessage == null) {
      return;
    }

    setState(() {
      _replyToMessage = null;
    });
  }

  Future<void> _editMessage(Map<String, dynamic> message) async {
    final id = _messageId(message);
    final from = message['from']?.toString().trim() ?? '';
    final oldText = message['text']?.toString() ?? '';

    if (id.isEmpty || from != _currentUser || oldText.trim().isEmpty) {
      return;
    }

    final controller = TextEditingController(text: oldText);
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: SpartanPalette.surface,
          title: const Text(
            'Редактировать сообщение',
            style: TextStyle(color: SpartanPalette.ink),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 6,
            style: const TextStyle(color: SpartanPalette.ink),
            decoration: InputDecoration(
              filled: true,
              fillColor: SpartanPalette.surface,
              hintText: 'Сообщение...',
              hintStyle: const TextStyle(color: SpartanPalette.secondary),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: _gold.withValues(alpha: 0.28)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _gold),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'Отмена',
                style: TextStyle(color: SpartanPalette.secondary),
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: SpartanPalette.blue,
                foregroundColor: SpartanPalette.ink,
              ),
              onPressed: () {
                final value = controller.text.trim();
                if (value.isNotEmpty) {
                  Navigator.of(dialogContext).pop(value);
                }
              },
              child: const Text('Сохранить'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (!mounted || result == null) {
      return;
    }

    final newText = result.trim();

    if (newText.isEmpty || newText == oldText.trim()) {
      return;
    }

    SocketService.instance.editGroupMessage(
      groupId: _groupId,
      messageId: id,
      text: newText,
    );
  }

  Future<void> _deleteMessage(Map<String, dynamic> message) async {
    final id = _messageId(message);
    final from = message['from']?.toString().trim() ?? '';

    if (id.isEmpty || from != _currentUser) {
      return;
    }

    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              backgroundColor: SpartanPalette.surface,
              title: const Text(
                'Удалить сообщение?',
                style: TextStyle(color: SpartanPalette.ink),
              ),
              content: const Text(
                'Сообщение исчезнет у всех участников группы.',
                style: TextStyle(color: SpartanPalette.secondary),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text(
                    'Отмена',
                    style: TextStyle(color: SpartanPalette.secondary),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text(
                    'Удалить у всех',
                    style: TextStyle(color: Color(0xFFFF5A5A)),
                  ),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!confirmed || !mounted) {
      return;
    }

    SocketService.instance.deleteGroupMessage(groupId: _groupId, messageId: id);
  }

  Map<String, String> _messageReactions(Map<String, dynamic> message) {
    final raw = message['reactions'];

    if (raw is! Map) {
      return <String, String>{};
    }

    final result = <String, String>{};

    raw.forEach((key, value) {
      final user = key.toString().trim();
      final reaction = value?.toString().trim() ?? '';

      if (user.isNotEmpty && reaction.isNotEmpty) {
        result[user] = reaction;
      }
    });

    return result;
  }

  Map<String, int> _reactionCounts(Map<String, dynamic> message) {
    final counts = <String, int>{};

    for (final reaction in _messageReactions(message).values) {
      counts[reaction] = (counts[reaction] ?? 0) + 1;
    }

    return counts;
  }

  void _sendReaction(Map<String, dynamic> message, String reaction) {
    final id = _messageId(message);

    if (id.isEmpty || reaction.isEmpty) {
      return;
    }

    SocketService.instance.sendGroupReaction(
      groupId: _groupId,
      messageId: id,
      reaction: reaction,
    );
  }

  Future<void> _showReactionPicker(Map<String, dynamic> message) async {
    if (!mounted) {
      return;
    }

    final selectedReaction = _messageReactions(message)[_currentUser] ?? '';

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 470),
            decoration: const BoxDecoration(
              color: SpartanPalette.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(top: BorderSide(color: _gold, width: 1.2)),
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: SpartanPalette.line,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 14),
                const Row(
                  children: [
                    Icon(Icons.emoji_emotions_outlined, color: _gold),
                    SizedBox(width: 10),
                    Text(
                      'Выберите реакцию',
                      style: TextStyle(
                        color: SpartanPalette.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
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
                              if (mounted) {
                                _sendReaction(message, reaction);
                              }
                            },
                          );
                        },
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? SpartanPalette.blue.withValues(alpha: 0.20)
                                : SpartanPalette.surface.withValues(
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

  Future<void> _saveToSaved(Map<String, dynamic> message) async {
    try {
      await SavedMessagesService.save(_currentUser, {
        ...message,
        'messageType': _messageType(message),
      }, origin: 'Группа: ${_group['name'] ?? _group['id']}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Добавлено в «Сохранённое» на этом устройстве'),
        ),
      );
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Не удалось сохранить. Проверьте доступность вложения.',
            ),
          ),
        );
    }
  }

  Future<void> _showMessageActions(Map<String, dynamic> message) async {
    final isMe = message['from']?.toString().trim() == _currentUser;
    final canEdit = isMe && _messageType(message) == 'text';

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: SpartanPalette.surface,
      showDragHandle: true,
      builder: (sheetContext) {
        Widget action({
          required IconData icon,
          required String title,
          required VoidCallback onTap,
          bool danger = false,
        }) {
          return ListTile(
            leading: Icon(
              icon,
              color: danger ? const Color(0xFFFF5A5A) : _gold,
            ),
            title: Text(
              title,
              style: TextStyle(
                color: danger ? const Color(0xFFFF5A5A) : SpartanPalette.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
            onTap: onTap,
          );
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                action(
                  icon: Icons.bookmark_add_outlined,
                  title: 'Сохранить',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    unawaited(_saveToSaved(message));
                  },
                ),
                action(
                  icon: Icons.reply_rounded,
                  title: 'Ответить',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _startReply(message);
                  },
                ),
                action(
                  icon: Icons.emoji_emotions_outlined,
                  title: 'Реакция',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Future<void>.delayed(const Duration(milliseconds: 80), () {
                      if (mounted) {
                        unawaited(_showReactionPicker(message));
                      }
                    });
                  },
                ),
                action(
                  icon: Icons.copy_rounded,
                  title: 'Копировать',
                  onTap: () {
                    final text = message['text']?.toString() ?? '';
                    Clipboard.setData(ClipboardData(text: text));
                    Navigator.of(sheetContext).pop();
                  },
                ),
                action(
                  icon: Icons.forward_rounded,
                  title: 'Переслать',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Future<void>.delayed(const Duration(milliseconds: 80), () {
                      if (mounted) {
                        unawaited(_forwardMessage(message));
                      }
                    });
                  },
                ),
                action(
                  icon: _pinnedMessageIds.contains(_messageId(message))
                      ? Icons.push_pin_outlined
                      : Icons.push_pin_rounded,
                  title: _pinnedMessageIds.contains(_messageId(message))
                      ? 'Открепить'
                      : 'Закрепить',
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    Future<void>.delayed(const Duration(milliseconds: 80), () {
                      if (mounted) {
                        unawaited(_togglePinnedMessage(message));
                      }
                    });
                  },
                ),
                if (canEdit)
                  action(
                    icon: Icons.edit_rounded,
                    title: 'Редактировать',
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      Future<void>.delayed(
                        const Duration(milliseconds: 80),
                        () {
                          if (mounted) {
                            unawaited(_editMessage(message));
                          }
                        },
                      );
                    },
                  ),
                if (isMe)
                  action(
                    icon: Icons.delete_outline_rounded,
                    title: 'Удалить у всех',
                    danger: true,
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      Future<void>.delayed(
                        const Duration(milliseconds: 80),
                        () {
                          if (mounted) {
                            unawaited(_deleteMessage(message));
                          }
                        },
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAddMembers() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => GroupAddMembersScreen(group: _group)),
    );

    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _group = result;
    });
  }

  void _showMembers() {
    final members = _members();
    final creator = _group['createdBy']?.toString().trim() ?? '';

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SpartanPalette.canvas,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
                  child: Row(
                    children: [
                      const Icon(Icons.groups_rounded, color: _gold),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$_groupName • ${members.length}',
                          style: const TextStyle(
                            color: SpartanPalette.ink,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(color: SpartanPalette.line, height: 1),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: members.length,
                    itemBuilder: (context, index) {
                      final member = members[index];

                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: SpartanPalette.surface,
                          child: Text(
                            member.isEmpty ? '?' : member[0].toUpperCase(),
                            style: const TextStyle(
                              color: _gold,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        title: Text(
                          member,
                          style: const TextStyle(color: SpartanPalette.ink),
                        ),
                        trailing: member == creator
                            ? const Text(
                                'создатель',
                                style: TextStyle(color: _gold, fontSize: 12),
                              )
                            : null,
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

  Widget _buildDateSeparator(Map<String, dynamic> message) {
    final date = _messageDateTime(message);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: SpartanPalette.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _gold.withValues(alpha: 0.18)),
          ),
          child: Text(
            _formatDate(date),
            style: const TextStyle(
              color: SpartanPalette.secondary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReplyPreview(
    Map<String, dynamic> replyTo, {
    required bool isMe,
  }) {
    final from = replyTo['from']?.toString().trim() ?? '';
    final text = replyTo['text']?.toString().trim() ?? '';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
      decoration: BoxDecoration(
        color: isMe
            ? SpartanPalette.surface.withValues(alpha: 0.10)
            : SpartanPalette.surface.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(10),
        border: Border(
          left: BorderSide(
            color: isMe ? SpartanPalette.secondary : _gold,
            width: 3,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            from.isEmpty ? 'Сообщение' : from,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isMe ? SpartanPalette.ink : _gold,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: isMe ? SpartanPalette.secondary : SpartanPalette.secondary,
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReactionRow(Map<String, dynamic> message, {required bool isMe}) {
    final counts = _reactionCounts(message);

    if (counts.isEmpty) {
      return const SizedBox.shrink();
    }

    final selected = _messageReactions(message)[_currentUser] ?? '';

    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Wrap(
        spacing: 6,
        runSpacing: 5,
        children: counts.entries.map((entry) {
          final mine = selected == entry.key;

          return InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _sendReaction(message, entry.key),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: mine
                    ? (isMe
                          ? SpartanPalette.surface.withValues(alpha: 0.16)
                          : SpartanPalette.blue.withValues(alpha: 0.20))
                    : (isMe
                          ? SpartanPalette.surface.withValues(alpha: 0.08)
                          : SpartanPalette.surface.withValues(alpha: 0.24)),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: mine
                      ? (isMe ? SpartanPalette.secondary : _gold)
                      : (isMe ? SpartanPalette.line : SpartanPalette.line),
                ),
              ),
              child: Text(
                '${entry.key} ${entry.value}',
                style: TextStyle(
                  color: isMe ? SpartanPalette.ink : SpartanPalette.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMessageBubble(Map<String, dynamic> message) {
    final from = message['from']?.toString().trim() ?? '';
    final editedAt = message['editedAt']?.toString().trim() ?? '';

    final rawReplyTo = message['replyTo'];
    final replyTo = rawReplyTo is Map
        ? Map<String, dynamic>.from(rawReplyTo)
        : null;

    final isMe = from.isNotEmpty && from == _currentUser;

    final maxWidth = Platform.isWindows
        ? 620.0
        : MediaQuery.sizeOf(context).width * 0.76;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: () {
          unawaited(_showMessageActions(message));
        },
        onDoubleTap: Platform.isWindows
            ? () {
                _startReply(message);
              }
            : null,
        onSecondaryTapDown: Platform.isWindows
            ? (_) {
                unawaited(_showMessageActions(message));
              }
            : null,
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          margin: EdgeInsets.only(
            left: isMe ? 48 : 4,
            right: isMe ? 4 : 48,
            bottom: 8,
          ),
          padding: const EdgeInsets.fromLTRB(14, 9, 14, 8),
          decoration: BoxDecoration(
            border: _highlightedMessageId == _messageId(message)
                ? Border.all(color: _gold, width: 2)
                : null,
            gradient: isMe
                ? const LinearGradient(
                    colors: [SpartanPalette.blue, SpartanPalette.blueDeep],
                  )
                : const LinearGradient(
                    colors: [SpartanPalette.surface, SpartanPalette.surface],
                  ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 5,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isMe && from.isNotEmpty) ...[
                Text(
                  from,
                  style: const TextStyle(
                    color: _gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
              ],
              if (replyTo != null) _buildReplyPreview(replyTo, isMe: isMe),
              _buildMediaBody(message, isMe: isMe),
              _buildReactionRow(message, isMe: isMe),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.bottomRight,
                child: Text(
                  '${editedAt.isNotEmpty ? 'изменено • ' : ''}${_formatTime(message['time'])}',
                  style: TextStyle(
                    color: isMe
                        ? SpartanPalette.secondary
                        : SpartanPalette.secondary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMessages() {
    if (_loadingMessages) {
      return const Center(child: CircularProgressIndicator(color: _gold));
    }

    if (_messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.groups_rounded,
              color: _gold.withValues(alpha: 0.78),
              size: 58,
            ),
            const SizedBox(height: 14),
            const Text(
              'Сообщений пока нет',
              style: TextStyle(
                color: SpartanPalette.ink,
                fontSize: 17,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Напишите первое сообщение в группу',
              style: TextStyle(color: SpartanPalette.secondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(
        horizontal: Platform.isWindows ? 24 : 12,
        vertical: 14,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: _messages.length,
      itemBuilder: (context, index) {
        final message = _messages[index];

        final id = _messageId(message);

        return Container(
          key: id.isEmpty ? null : _messageItemKey(id),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_needsDateSeparator(index)) _buildDateSeparator(message),
              _buildMessageBubble(message),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReplyComposerPreview() {
    final reply = _replyToMessage;

    if (reply == null) {
      return const SizedBox.shrink();
    }

    final from = reply['from']?.toString().trim() ?? '';
    final text = reply['text']?.toString().trim() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
      decoration: BoxDecoration(
        color: SpartanPalette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: const BorderSide(color: _gold, width: 3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply_rounded, color: _gold, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  from.isEmpty ? 'Ответ' : from,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
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
          IconButton(
            tooltip: 'Отменить ответ',
            visualDensity: VisualDensity.compact,
            onPressed: _cancelReply,
            icon: const Icon(
              Icons.close_rounded,
              color: SpartanPalette.secondary,
              size: 20,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    final desktop = Platform.isWindows;

    return Container(
      padding: EdgeInsets.fromLTRB(desktop ? 16 : 8, 9, desktop ? 16 : 8, 10),
      decoration: BoxDecoration(
        color: SpartanPalette.surface,
        border: Border(top: BorderSide(color: _gold.withValues(alpha: 0.16))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: desktop ? 920 : double.infinity,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildReplyComposerPreview(),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    IconButton(
                      tooltip: 'Вложение',
                      onPressed: _sending
                          ? null
                          : () {
                              unawaited(_showAttachmentMenu());
                            },
                      icon: const Icon(
                        Icons.add_circle_outline_rounded,
                        color: _gold,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: CallbackShortcuts(
                        bindings: desktop
                            ? <ShortcutActivator, VoidCallback>{
                                const SingleActivator(LogicalKeyboardKey.enter):
                                    _sendMessage,
                              }
                            : const <ShortcutActivator, VoidCallback>{},
                        child: TextField(
                          controller: _messageController,
                          focusNode: _messageFocusNode,
                          autofocus: desktop,
                          maxLines: 6,
                          minLines: 1,
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          style: const TextStyle(color: SpartanPalette.ink),
                          decoration: InputDecoration(
                            hintText: 'Сообщение...',
                            hintStyle: const TextStyle(
                              color: SpartanPalette.secondary,
                            ),
                            filled: true,
                            fillColor: SpartanPalette.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: BorderSide(
                                color: _gold.withValues(alpha: 0.55),
                              ),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                          ),
                          onChanged: _handleGroupTextChanged,
                          onSubmitted: desktop ? (_) {} : null,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [SpartanPalette.gold, SpartanPalette.gold],
                          ),
                        ),
                        child: IconButton(
                          tooltip: _recordingVoice
                              ? 'Остановить и отправить'
                              : _composerHasText
                              ? 'Отправить сообщение'
                              : 'Голосовое сообщение',
                          onPressed: _sending
                              ? null
                              : _recordingVoice
                              ? () {
                                  unawaited(_toggleVoiceRecording());
                                }
                              : _composerHasText
                              ? _sendMessage
                              : () {
                                  unawaited(_toggleVoiceRecording());
                                },
                          icon: _sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.black,
                                  ),
                                )
                              : Icon(
                                  _recordingVoice
                                      ? Icons.stop_circle_rounded
                                      : _composerHasText
                                      ? Icons.send_rounded
                                      : Icons.mic_rounded,
                                  color: _recordingVoice
                                      ? const Color(0xFFFF3D3D)
                                      : Colors.black,
                                ),
                        ),
                      ),
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

  @override
  Widget build(BuildContext context) {
    final members = _members();
    final creator = _group['createdBy']?.toString().trim() ?? '';

    final canManageMembers = creator.isNotEmpty && _currentUser == creator;

    return Scaffold(
      backgroundColor: SpartanPalette.canvas,
      appBar: AppBar(
        backgroundColor: SpartanPalette.canvas,
        foregroundColor: SpartanPalette.ink,
        titleSpacing: 8,
        title: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _showMembers,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: SpartanPalette.surface,
                  child: Icon(Icons.groups_rounded, color: _gold),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _groupName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SpartanPalette.ink,
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                      Text(
                        _groupSubtitleText(members.length),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _typingUsers.isEmpty
                              ? SpartanPalette.secondary
                              : _gold,
                          fontSize: 12,
                          fontWeight: _typingUsers.isEmpty
                              ? FontWeight.w400
                              : FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Групповой голосовой звонок',
            onPressed: _startGroupCall,
            icon: const Icon(Icons.call_rounded, color: _gold),
          ),
          IconButton(
            tooltip: 'Поиск',
            onPressed: _searchMode ? _closeSearch : _openSearch,
            icon: Icon(
              _searchMode ? Icons.search_off_rounded : Icons.search_rounded,
              color: _gold,
            ),
          ),
          IconButton(
            tooltip: 'Участники',
            onPressed: _showMembers,
            icon: const Icon(Icons.info_outline_rounded, color: _gold),
          ),
          if (canManageMembers)
            IconButton(
              tooltip: 'Добавить участников',
              onPressed: _openAddMembers,
              icon: const Icon(Icons.person_add_alt_1_rounded, color: _gold),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_searchMode) _buildSearchBar(),
          _groupCallBanner(),
          _buildPinnedMessagesBanner(),
          Expanded(child: _buildMessages()),
          _buildComposer(),
        ],
      ),
    );
  }
}
