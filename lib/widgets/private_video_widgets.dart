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
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Start preparing immediately so the existing first-frame cover appears
    // without an extra tap. Duplicate requests are coalesced by the cache.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_prepare());
    });
  }

  Future<void> _prepare() async {
    if (_loading || _controller != null) return;
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
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

      await controller.initialize();
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
        _controller = controller;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      debugPrint('🎥 Private video prepare failed: $error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _toggle() async {
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

  Future<void> _openFullScreen() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
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
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
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

  @override
  Widget build(BuildContext context) {
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
