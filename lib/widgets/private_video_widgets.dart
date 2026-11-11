part of '../screens/chat_screen.dart';

class _InlinePrivateVideo extends StatefulWidget {
  final Uint8List? bytes;
  final String? filePath;
  final String fileName;
  final String? networkUrl;
  final Map<String, String> httpHeaders;
  final Map<String, dynamic>? mediaMessage;
  final bool isMe;
  final Color gold;
  final VoidCallback onDownload;

  const _InlinePrivateVideo({
    super.key,
    this.bytes,
    this.filePath,
    required this.fileName,
    this.networkUrl,
    this.httpHeaders = const <String, String>{},
    this.mediaMessage,
    required this.isMe,
    required this.gold,
    required this.onDownload,
  });

  @override
  State<_InlinePrivateVideo> createState() => _InlinePrivateVideoState();
}

class _InlinePrivateVideoState extends State<_InlinePrivateVideo> {
  VideoPlayerController? _controller;
  File? _tempFile;
  double _hexSpeed = 1.0;
  bool _hexMuted = true;
  List<double> _hexAudioEnvelope = const <double>[];
  String? _hexAudioSourcePath;
  double _hexAudioLevel = 0.0;

  static final Map<_InlinePrivateVideoState, double> _hexVisible =
      <_InlinePrivateVideoState, double>{};
  static _InlinePrivateVideoState? _hexActive;
  static _InlinePrivateVideoState? _hexSecondActive;
  static _InlinePrivateVideoState? _hexThirdActive;

  Timer? _hexAutoTimer;
  Timer? _hexReleaseTimer;
  bool _hexReleaseInProgress = false;
  bool _hexUserPaused = false;
  bool _hexFullScreenOpen = false;
  bool _hexSyncBusy = false;

  void _checkHexVisibility() {
    if (!mounted || !_isHexVideoNote) return;

    final route = ModalRoute.of(context);
    final box = context.findRenderObject();
    double? distance;

    if ((route == null || route.isCurrent) &&
        !_hexFullScreenOpen &&
        AppVisibility.instance.foreground &&
        box is RenderBox &&
        box.attached &&
        box.hasSize) {
      final origin = box.localToGlobal(Offset.zero);
      final screenHeight = MediaQuery.sizeOf(context).height;
      final top = origin.dy;
      final bottom = top + box.size.height;
      final start = top.clamp(75.0, screenHeight - 75.0).toDouble();
      final end = bottom.clamp(75.0, screenHeight - 75.0).toDouble();

      if (end - start >= 95.0) {
        distance = ((start + end) / 2 - screenHeight / 2).abs();
      }
    }

    if (distance == null) {
      _hexVisible.remove(this);
      _hexUserPaused = false;
    } else {
      _hexVisible[this] = distance;
    }
    _selectActiveHex();
  }

  static void _selectActiveHex() {
    final candidates =
        _hexVisible.entries.where((entry) => entry.key.mounted).toList()
          ..sort((a, b) => a.value.compareTo(b.value));

    final first = candidates.isNotEmpty ? candidates[0].key : null;
    // Play at most two visible inline HEX videos.
    final _InlinePrivateVideoState? second =
        candidates.length > 1 ? candidates[1].key : null;
    final _InlinePrivateVideoState? third = null;

    final previous = <_InlinePrivateVideoState>{
      if (_hexActive != null) _hexActive!,
      if (_hexSecondActive != null) _hexSecondActive!,
      if (_hexThirdActive != null) _hexThirdActive!,
    };

    final next = <_InlinePrivateVideoState>{
      if (first != null) first,
      if (second != null) second,
      if (third != null) third,
    };

    if (previous.length == next.length && previous.containsAll(next)) {
      return;
    }

    _hexActive = first;
    _hexSecondActive = second;
    _hexThirdActive = third;

    for (final entry in <_InlinePrivateVideoState>{...previous, ...next}) {
      if (!entry.mounted) continue;

      if (next.contains(entry)) {
        entry._hexReleaseTimer?.cancel();
        entry._hexReleaseTimer = null;

        if (!HexInlineVoiceCoordinator.isVoiceActive &&
            entry._controller == null &&
            !entry._loading &&
            !entry._hexReleaseInProgress) {
          unawaited(entry._prepare());
        }
      } else {
        entry._scheduleHexReleaseIfNeeded();
      }

      unawaited(entry._syncHexPlayback());
    }
  }

  bool get _hexIsSelected =>
      identical(_hexActive, this) ||
      identical(_hexSecondActive, this) ||
      identical(_hexThirdActive, this);

  void _scheduleHexReleaseIfNeeded() {
    if (!mounted || !_isHexVideoNote) return;

    if (_hexIsSelected || _hexFullScreenOpen) {
      _hexReleaseTimer?.cancel();
      _hexReleaseTimer = null;
      return;
    }

    if (_controller == null ||
        _loading ||
        _hexReleaseInProgress ||
        _hexReleaseTimer != null) {
      return;
    }

    _hexReleaseTimer = Timer(const Duration(seconds: 2), () {
      _hexReleaseTimer = null;
      if (mounted) unawaited(_releaseOffscreenHexController());
    });
  }

  // FENYVO_VOICE_HEX_DECODER_RELEASE_995
  Future<void> _releaseOffscreenHexController({
    bool forVoice = false,
  }) async {
    if (!mounted ||
        !_isHexVideoNote ||
        (_hexIsSelected && !forVoice) ||
        _hexFullScreenOpen ||
        _hexReleaseInProgress) {
      return;
    }

    if (_hexSyncBusy || _loading) {
      _scheduleHexReleaseIfNeeded();
      return;
    }

    final player = _controller;
    if (player == null) return;

    _hexReleaseInProgress = true;
    final temporaryFile = _tempFile;
    player.removeListener(_changed);

    setState(() {
      _controller = null;
      _tempFile = null;
      _hexAudioEnvelope = const <double>[];
      _hexAudioLevel = 0.0;
    });

    try {
      try {
        await player.setVolume(0.0);
        if (player.value.isPlaying) await player.pause();
      } catch (error) {
        debugPrint('HEX offscreen pause failed: $error');
      }

      await player.dispose();

      // Never delete files owned by the shared media cache.
      if (temporaryFile != null) {
        try {
          if (await temporaryFile.exists()) {
            await temporaryFile.delete();
          }
        } catch (error) {
          debugPrint('HEX temporary cleanup failed: $error');
        }
      }
    } catch (error) {
      debugPrint('HEX decoder release failed: $error');
    } finally {
      _hexReleaseInProgress = false;

      if (mounted &&
          _hexIsSelected &&
          _controller == null &&
          !_loading &&
          !HexInlineVoiceCoordinator.isVoiceActive) {
        unawaited(_prepare());
      }
    }
  }

  void _onHexForegroundChanged() {
    _checkHexVisibility();
    if (!AppVisibility.instance.foreground) {
      unawaited(_syncHexPlayback());
    }
  }

  Future<void> _syncHexPlayback() async {
    if (!_isHexVideoNote || _hexSyncBusy || _hexFullScreenOpen) return;
    final player = _controller;
    if (player == null || !player.value.isInitialized) return;

    _hexSyncBusy = true;
    try {
      final active =
          mounted &&
          (identical(_hexActive, this) ||
              identical(_hexSecondActive, this) ||
              identical(_hexThirdActive, this)) &&
          AppVisibility.instance.foreground &&
          !_hexUserPaused &&
          !HexInlineVoiceCoordinator.isVoiceActive;

      if (!active) {
        if (player.value.isPlaying) {
          await player.setVolume(0.0);
          await player.pause();
        }
        if (mounted && identical(_controller, player)) {
          _hexAudioLevel = 0.0;
          if (!_hexMuted) setState(() => _hexMuted = true);
        }
      } else if (!player.value.isPlaying) {
        // Send platform commands only when starting playback.
        // Inline HEX video must always remain silent.
        await player.setVolume(0.0);
        await player.setLooping(true);
        if (mounted &&
            identical(_controller, player) &&
            !_hexFullScreenOpen &&
            !_hexUserPaused &&
            AppVisibility.instance.foreground &&
            !HexInlineVoiceCoordinator.isVoiceActive &&
            (identical(_hexActive, this) ||
                identical(_hexSecondActive, this) ||
                identical(_hexThirdActive, this))) {
          await player.play();
        }
      }
    } catch (error) {
      debugPrint('HEX autoplay sync failed: $error');
    } finally {
      _hexSyncBusy = false;
    }
  }

  Future<void> _loadHexAudioEnvelope(
    String path,
    VideoPlayerController controller,
  ) async {
    if (!_isHexVideoNote || path.isEmpty) return;

    final levels = await HexVideoAudioLevels.analyze(path);

    if (!mounted || !identical(_controller, controller)) return;

    setState(() {
      _hexAudioEnvelope = levels;
      _hexAudioLevel = 0.0;
    });
  }

  bool get _isHexVideoNote =>
      widget.fileName.toLowerCase().startsWith('fenyvo_hex_note_');

  Future<void> _restoreHexSpeed() async {
    if (!_isHexVideoNote) return;
    try {
      final speed = await PrivateVideoNoteSpeedSettings.load();
      if (!mounted) return;
      _hexSpeed = speed;

      final controller = _controller;
      if (controller != null && controller.value.isInitialized) {
        await controller.setPlaybackSpeed(speed);
      }
      if (mounted) setState(() {});
    } catch (error) {
      debugPrint('HEX speed restore failed: $error');
    }
  }

  Future<void> _cycleHexSpeed() async {
    final speeds = PrivateVideoNoteSpeedSettings.supportedSpeeds;
    final current = speeds.indexOf(_hexSpeed);
    final next = speeds[(current + 1) % speeds.length];
    try {
      final controller = _controller;
      if (controller != null && controller.value.isInitialized) {
        await controller.setPlaybackSpeed(next);
      }
      if (!mounted) return;
      setState(() => _hexSpeed = next);
      await PrivateVideoNoteSpeedSettings.save(next);
    } catch (error) {
      debugPrint('HEX speed change failed: $error');
    }
  }

  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_isHexVideoNote) {
      AppVisibility.instance.changes.addListener(_onHexForegroundChanged);
      _hexAutoTimer = Timer.periodic(const Duration(milliseconds: 450), (_) {
        if (!mounted) return;
        _checkHexVisibility();
        _scheduleHexReleaseIfNeeded();
        if (identical(_hexActive, this) ||
            identical(_hexSecondActive, this) ||
            identical(_hexThirdActive, this) ||
            (_controller?.value.isPlaying ?? false)) {
          unawaited(_syncHexPlayback());
        }
      });
    }
    unawaited(_restoreHexSpeed());
    // Start preparing immediately so the existing first-frame cover appears
    // without an extra tap. Duplicate requests are coalesced by the cache.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // FENYVO_LAZY_HEX_PREPARE_894
      // Ordinary videos keep the existing preparation flow.
      // HEX videos wait until selected for visible autoplay.
      if (mounted && !_isHexVideoNote) {
        unawaited(_prepare());
      }
    });
  }

  Future<void> _prepare() async {
    if (_isHexVideoNote &&
        HexInlineVoiceCoordinator.isVoiceActive) {
      return;
    }
    if (_loading || _controller != null || _hexReleaseInProgress) return;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    // FENYVO_HEX_LIFECYCLE_967
    // Track resources until the controller belongs to widget state.
    VideoPlayerController? pendingController;
    File? pendingTempFile;
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
            final extension = widget.fileName.contains('.')
                ? '.${widget.fileName.split('.').last.toLowerCase()}'
                : '.mp4';
            file = File(
              '${temp.path}${Platform.pathSeparator}'
              'spartan_private_video_${DateTime.now().microsecondsSinceEpoch}$extension',
            );
            await file.writeAsBytes(bytes, flush: true);
            ownsTemp = true;
            controller = VideoPlayerController.file(file);
          }
        }
      }

      pendingController = controller;
      if (ownsTemp) pendingTempFile = file;
      await controller.initialize();
      if (_isHexVideoNote) {
        // Never route HEX audio to speakers on initialization.
        await controller.setVolume(0.0);
        await controller.setPlaybackSpeed(_hexSpeed);
      }
      controller.addListener(_changed);
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
        _hexAudioSourcePath = file.path.isNotEmpty && file.existsSync()
            ? file.path
            : null;
        _controller = controller;
        _loading = false;
        _error = null;
      });
      // Widget state now owns the initialized controller.
      pendingController = null;
      pendingTempFile = null;

      if (_isHexVideoNote &&
          HexInlineVoiceCoordinator.isVoiceActive) {
        unawaited(
          _releaseOffscreenHexController(forVoice: true),
        );
        return;
      }

      if (_isHexVideoNote) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _checkHexVisibility();
            unawaited(_syncHexPlayback());
          }
        });
      }
    } catch (error) {
      // Release partially initialized decoders after failures.
      if (pendingController != null) {
        try {
          await pendingController.dispose();
        } catch (_) {}
      }
      if (pendingTempFile != null) {
        try {
          if (await pendingTempFile.exists()) {
            await pendingTempFile.delete();
          }
        } catch (_) {}
      }
      debugPrint('🎥 Private video prepare failed: $error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _changed() {
    // VideoPlayer paints frames itself. Avoid rebuilding the
    // whole inline HEX bubble for every playback position update.
    // Expanded playback uses its own AnimatedBuilder.
    if (!mounted || _isHexVideoNote) return;
    setState(() {});
  }

  Future<void> _toggle() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.position >= controller.value.duration &&
        controller.value.duration > Duration.zero) {
      await controller.seekTo(Duration.zero);
    }
    if (controller.value.isPlaying) {
      if (_isHexVideoNote) _hexUserPaused = true;
      await controller.pause();
    } else {
      if (_isHexVideoNote) _hexUserPaused = false;
      await controller.play();
    }
  }

  Future<void> _openHexExpanded() async {
    final player = _controller;
    if (!_isHexVideoNote ||
        _hexFullScreenOpen ||
        !mounted ||
        player == null ||
        !player.value.isInitialized ||
        !AppVisibility.instance.foreground) {
      return;
    }

    _hexFullScreenOpen = true;

    // Never analyze inline videos in the chat.
    // A file-backed video is analyzed only when expanded.
    final audioPath = _hexAudioSourcePath;
    if (audioPath != null && _hexAudioEnvelope.isEmpty) {
      unawaited(_loadHexAudioEnvelope(audioPath, player));
    }

    _checkHexVisibility();
    setState(() {});

    BuildContext? dialogContext;
    var dialogAlive = true;
    var playbackStarted = false;
    // FENYVO_EXPANDED_CONTROLS_970
    var fullscreenRequested = false;

    void closeDialog() {
      final ctx = dialogContext;
      if (!dialogAlive || ctx == null || !ctx.mounted) return;
      if (ModalRoute.of(ctx)?.isCurrent == true) {
        Navigator.of(ctx).pop();
      }
    }

    void playbackChanged() {
      if (!dialogAlive) return;
      if (player.value.isCompleted) closeDialog();
    }

    void visibilityChanged() {
      if (!AppVisibility.instance.foreground) {
        unawaited(player.setVolume(0.0));
        closeDialog();
      }
    }

    try {
      await player.setVolume(0.0);
      await player.pause();
      await player.setLooping(false);
      await player.seekTo(Duration.zero);

      if (!mounted || !AppVisibility.instance.foreground) return;

      player.addListener(playbackChanged);
      AppVisibility.instance.changes.addListener(visibilityChanged);

      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierColor: const Color(0xE6071527),
        builder: (ctx) {
          dialogContext = ctx;
          if (!playbackStarted) {
            playbackStarted = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!dialogAlive || !ctx.mounted) return;
              unawaited(() async {
                try {
                  if (!AppVisibility.instance.foreground) {
                    closeDialog();
                    return;
                  }
                  await player.setVolume(1.0);
                  if (!dialogAlive || !AppVisibility.instance.foreground) {
                    await player.setVolume(0.0);
                    return;
                  }
                  await player.play();
                } catch (error) {
                  debugPrint('HEX expanded start failed: $error');
                  closeDialog();
                }
              }());
            });
          }

          return Dialog(
            backgroundColor: Colors.transparent,
            elevation: 0,
            insetPadding: const EdgeInsets.all(16),
            child: AnimatedBuilder(
              animation: player,
              builder: (context, _) {
                final size = MediaQuery.sizeOf(context);
                final extent = (size.shortestSide * 0.85)
                    .clamp(180.0, 420.0)
                    .toDouble();

                final level = player.value.isPlaying
                    ? HexVideoAudioLevels.atPosition(
                        _hexAudioEnvelope,
                        player.value.position,
                      )
                    : 0.0;

                return Center(
                  child: SizedBox(
                    width: extent,
                    height: extent,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onDoubleTap: () {
                            fullscreenRequested = true;
                            closeDialog();
                          },
                          child: ClipPath(
                          clipper: _FenyvoHexVideoClipper(),
                          child: ColoredBox(
                            color: const Color(0xFF071527),
                            child: FittedBox(
                              fit: BoxFit.cover,
                              child: SizedBox(
                                width:
                                    extent *
                                    (player.value.aspectRatio > 0
                                        ? player.value.aspectRatio
                                        : 1.0),
                                height: extent,
                                child: VideoPlayer(player),
                              ),
                            ),
                          ),
                          ),
                        ),
                        FenyvoHexAudioBorder(
                          level: level,
                          color: const Color(0xFFFFD54F),
                        ),
                        Positioned(
                          bottom: 12,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: StatefulBuilder(
                              builder: (speedContext, setSpeedState) {
                                return TextButton(
                                  style: TextButton.styleFrom(
                                    backgroundColor:
                                        const Color(0xD9071527),
                                    foregroundColor:
                                        const Color(0xFFFFD54F),
                                  ),
                                  onPressed: () async {
                                    await _cycleHexSpeed();
                                    if (dialogAlive &&
                                        speedContext.mounted) {
                                      setSpeedState(() {});
                                    }
                                  },
                                  child: Text(
                                    PrivateVideoNoteSpeedSettings.label(
                                      _hexSpeed,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        Positioned(
                          top: extent * 0.23,
                          right: 14,
                          child: IconButton(
                            tooltip: MaterialLocalizations.of(context)
                                .closeButtonTooltip,
                            onPressed: closeDialog,
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      );
    } catch (error) {
      debugPrint('HEX expanded playback failed: $error');
    } finally {
      dialogAlive = false;
      player.removeListener(playbackChanged);
      AppVisibility.instance.changes.removeListener(visibilityChanged);

      try {
        await player.setVolume(0.0);
        await player.pause();
        await player.setLooping(true);
        if (!fullscreenRequested) {
          await player.seekTo(Duration.zero);
        }
      } catch (error) {
        debugPrint('HEX inline return failed: $error');
      }

      if (mounted && identical(_controller, player)) {
        _hexFullScreenOpen = false;
        _hexMuted = true;
        _hexUserPaused = false;
        _hexAudioLevel = 0.0;
        setState(() {});

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (fullscreenRequested) {
            unawaited(_openFullScreen(continuePlayback: true));
            return;
          }
          _checkHexVisibility();
          unawaited(_syncHexPlayback());
        });
      }
    }
  }

  Future<void> _openFullScreen({
    bool continuePlayback = false,
  }) async {
    final controller = _controller;
    if (controller == null ||
        !controller.value.isInitialized ||
        !mounted ||
        (_isHexVideoNote && _hexFullScreenOpen)) {
      return;
    }

    final isHex = _isHexVideoNote;
    if (isHex) {
      _hexFullScreenOpen = true;
      _checkHexVisibility();
      setState(() {});
    }

    try {
      if (isHex) {
        await controller.setVolume(0.0);
        await controller.pause();
        await controller.setLooping(false);
        if (!continuePlayback) {
          await controller.seekTo(Duration.zero);
        }
        if (!mounted || !AppVisibility.instance.foreground) return;
        await controller.setVolume(1.0);
        await controller.play();
      }

      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) => _PrivateVideoFullScreen(
            controller: controller,
            fileName: widget.fileName,
            gold: widget.gold,
            onDownload: widget.onDownload,
          ),
        ),
      );
    } finally {
      if (isHex) {
        try {
          await controller.setVolume(0.0);
          await controller.pause();
          await controller.setLooping(true);
          await controller.seekTo(Duration.zero);
        } catch (error) {
          debugPrint('HEX fullscreen return failed: $error');
        }

        if (mounted) {
          _hexFullScreenOpen = false;
          _hexMuted = true;
          _hexUserPaused = false;
          _hexAudioLevel = 0.0;
          setState(() {});
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _checkHexVisibility();
            unawaited(_syncHexPlayback());
          });
        }
      } else if (mounted) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    if (_isHexVideoNote) {
      _hexAutoTimer?.cancel();
      _hexReleaseTimer?.cancel();
      _hexReleaseTimer = null;
      AppVisibility.instance.changes.removeListener(_onHexForegroundChanged);
      _hexVisible.remove(this);
      if (identical(_hexActive, this)) _hexActive = null;
      if (identical(_hexSecondActive, this)) {
        _hexSecondActive = null;
      }
      if (identical(_hexThirdActive, this)) _hexThirdActive = null;
      _selectActiveHex();
    }
    final controller = _controller;
    if (controller != null) {
      controller.removeListener(_changed);
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

  Widget _buildHexVideoNote() {
    final controller = _controller;
    final ready = controller != null && controller.value.isInitialized;
    final duration = ready ? controller.value.duration : Duration.zero;
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');

    return SizedBox(
      width: 224,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 216,
            height: 224,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipPath(
                  clipper: _FenyvoHexVideoClipper(),
                  child: ColoredBox(
                    color: const Color(0xFF071527),
                    child: ready && !_hexFullScreenOpen
                        ? FittedBox(
                            fit: BoxFit.cover,
                            child: SizedBox(
                              width:
                                  224 *
                                  (controller.value.aspectRatio > 0
                                      ? controller.value.aspectRatio
                                      : 1),
                              height: 224,
                              child: VideoPlayer(controller),
                            ),
                          )
                        : Center(
                            child: _loading
                                ? CircularProgressIndicator(color: widget.gold)
                                : Icon(
                                    _error == null
                                        ? Icons.videocam_rounded
                                        : Icons.refresh_rounded,
                                    color: widget.gold,
                                    size: 40,
                                  ),
                          ),
                  ),
                ),
                FenyvoHexAudioBorder(
                  level: _hexAudioLevel,
                  color: const Color(0xFFFFD54F),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (ready) {
                        unawaited(_openHexExpanded());
                      } else {
                        unawaited(_prepare());
                      }
                    },
                    child: Center(
                      child: AnimatedOpacity(
                        opacity: 1.0,
                        duration: const Duration(milliseconds: 150),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: const Color(0xCC071527),
                            border: Border.all(color: widget.gold, width: 1.5),
                          ),
                          child: Icon(
                            ready
                                ? Icons.play_arrow_rounded
                                : Icons.refresh_rounded,
                            color: widget.gold,
                            size: 30,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Hide the placeholder 0:00 until media duration is known.
                if (ready && duration > Duration.zero)
                  Positioned(
                  bottom: 23,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: const Color(0xCC071527),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 3,
                          ),
                          child: Text(
                            '$minutes:$seconds',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isHexVideoNote) return _buildHexVideoNote();
    if (_loading) {
      return const SizedBox(
        width: 250,
        height: 140,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final controller = _controller;
    if (_error != null ||
        controller == null ||
        !controller.value.isInitialized) {
      return Material(
        color: FenyvoPalette.surface.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => unawaited(_prepare()),
          child: SizedBox(
            width: 250,
            height: 140,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _error == null
                        ? Icons.play_circle_fill_rounded
                        : Icons.refresh_rounded,
                    color: widget.gold,
                    size: 48,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _error == null
                        ? '${_chatText('download')} ${_chatText('video').toLowerCase()}'
                        : _chatText('videoUnavailable'),
                    style: const TextStyle(color: FenyvoPalette.ink),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    final playing = controller.value.isPlaying;
    return Container(
      constraints: const BoxConstraints(minWidth: 230, maxWidth: 340),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: controller.value.aspectRatio > 0
                ? controller.value.aspectRatio
                : 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                VideoPlayer(controller),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => unawaited(_toggle()),
                    child: Center(
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 150),
                        opacity: playing ? 0 : 1,
                        child: Container(
                          width: 54,
                          height: 54,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.70),
                            shape: BoxShape.circle,
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: () => unawaited(_toggle()),
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
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: _chatText('fullScreen'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => unawaited(_openFullScreen()),
                  icon: const Icon(
                    Icons.fullscreen_rounded,
                    color: Colors.white,
                  ),
                ),
                IconButton(
                  tooltip: _chatText('download'),
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onDownload,
                  icon: Icon(Icons.download_rounded, color: widget.gold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FenyvoHexVideoClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w / 2, 0)
      ..lineTo(w, h / 4)
      ..lineTo(w, h * 3 / 4)
      ..lineTo(w / 2, h)
      ..lineTo(0, h * 3 / 4)
      ..lineTo(0, h / 4)
      ..close();
  }

  @override
  bool shouldReclip(covariant _FenyvoHexVideoClipper oldClipper) => false;
}

class _PrivateVideoFullScreen extends StatefulWidget {
  final VideoPlayerController controller;
  final String fileName;
  final Color gold;
  final VoidCallback onDownload;

  const _PrivateVideoFullScreen({
    required this.controller,
    required this.fileName,
    required this.gold,
    required this.onDownload,
  });

  @override
  State<_PrivateVideoFullScreen> createState() =>
      _PrivateVideoFullScreenState();
}

class _PrivateVideoFullScreenState extends State<_PrivateVideoFullScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
    final controller = widget.controller;
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
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final playing = controller.value.isPlaying;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: _chatText('download'),
            onPressed: widget.onDownload,
            icon: Icon(Icons.download_rounded, color: widget.gold),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio > 0
                      ? controller.value.aspectRatio
                      : 16 / 9,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      VideoPlayer(controller),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: () => unawaited(_toggle()),
                          child: Center(
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 150),
                              opacity: playing ? 0 : 1,
                              child: Container(
                                width: 68,
                                height: 68,
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.70),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 48,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => unawaited(_toggle()),
                    icon: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      color: widget.gold,
                    ),
                  ),
                  Expanded(
                    child: VideoProgressIndicator(
                      controller,
                      allowScrubbing: true,
                      padding: const EdgeInsets.symmetric(vertical: 10),
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
          ],
        ),
      ),
    );
  }
}


/// FENYVO_VOICE_HEX_COORDINATOR_990
/// Keeps silent inline HEX playback from competing with voice messages.
class HexInlineVoiceCoordinator {
  // FENYVO_VOICE_RECORD_HEX_999
  static bool _voicePlaybackActive = false;
  static bool _voiceRecordingActive = false;

  static bool get isVoiceActive =>
      _voicePlaybackActive || _voiceRecordingActive;

  static Future<void> setVoiceActive(bool active) async {
    _voicePlaybackActive = active;
    await _syncMediaState();
  }

  static Future<void> setVoiceRecordingActive(bool active) async {
    _voiceRecordingActive = active;
    await _syncMediaState();
  }

  static Future<void> _syncMediaState() async {
    final active = isVoiceActive;
    final states = _InlinePrivateVideoState._hexVisible.keys.toList();

    if (active) {
      // Release both the selected and still-visible video decoders.
      // Give an in-flight sync a chance to finish before releasing.
      for (var attempt = 0; attempt < 5; attempt++) {
        var pending = false;

        for (final state in states) {
          if (!state.mounted || state._hexFullScreenOpen) continue;

          if (state._loading ||
              state._hexSyncBusy ||
              state._hexReleaseInProgress) {
            pending = true;
            continue;
          }

          if (state._controller != null) {
            await state._releaseOffscreenHexController(
              forVoice: true,
            );
          }

          if (state._controller != null) pending = true;
        }

        if (!pending || !isVoiceActive) break;

        await Future<void>.delayed(
          const Duration(milliseconds: 120),
        );
      }

      debugPrint('FENYVO_VOICE_HEX event=decoder_release_requested');
    } else {
      // Restore controllers only for the two selected inline videos.
      for (final state in states) {
        if (!state.mounted || !state._hexIsSelected) continue;

        if (state._controller == null &&
            !state._loading &&
            !state._hexReleaseInProgress) {
          unawaited(state._prepare());
        } else {
          unawaited(state._syncHexPlayback());
        }
      }

      debugPrint('FENYVO_VOICE_HEX event=decoder_restore_requested');
    }
  }
}
