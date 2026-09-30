import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dart:io';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../services/call_service.dart';
import '../widgets/call_controls.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  String? _windowCallId;
  Offset? _videoPreviewPosition;
  bool _localVideoIsPrimary = false;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();
    _windowCallId = CallService.instance.callId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          CallService.instance.callId == _windowCallId &&
          CallService.instance.hasCall) {
        unawaited(_callWindow('show'));
      }
    });
  }

  Future<void> _callWindow(String action) async {
    if (!Platform.isAndroid || _windowCallId == null) return;
    try {
      await const MethodChannel('spartan_chat/call_window')
          .invokeMethod<void>(action, {'callId': _windowCallId});
    } catch (_) {}
  }

  @override
  void dispose() {
    unawaited(_callWindow('hide'));
    super.dispose();
  }

  static const Color _gold = Color(0xFFD4AF37);

  Offset _resolvePreviewPosition(BoxConstraints constraints, Size previewSize) {
    const margin = 14.0;
    final maxX = (constraints.maxWidth - previewSize.width - margin)
        .clamp(margin, double.infinity)
        .toDouble();
    final reservedBottom = _controlsVisible ? 132.0 : margin;
    final maxY = (constraints.maxHeight - previewSize.height - reservedBottom)
        .clamp(margin, double.infinity)
        .toDouble();
    final preferred = _videoPreviewPosition ?? Offset(maxX, 92);
    return Offset(
      preferred.dx.clamp(margin, maxX).toDouble(),
      preferred.dy.clamp(margin, maxY).toDouble(),
    );
  }

  void _moveVideoPreview(
    DragUpdateDetails details,
    BoxConstraints constraints,
    Size previewSize,
  ) {
    final current = _resolvePreviewPosition(constraints, previewSize);
    setState(() {
      _videoPreviewPosition = current + details.delta;
    });
  }

  void _swapVideoSurfaces() {
    setState(() {
      _localVideoIsPrimary = !_localVideoIsPrimary;
    });
  }

  void _toggleFullscreenVideo() {
    setState(() {
      _controlsVisible = !_controlsVisible;
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = CallService.instance;

    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final peer = service.peerUser ?? 'Собеседник';
        final hasRemoteVideo =
            service.isVideo && service.remoteRenderer.srcObject != null;
        final hasLocalVideo =
            service.isVideo && service.localRenderer.srcObject != null;

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              unawaited(service.hangUp());
            }
          },
          child: Scaffold(
            backgroundColor: const Color(0xFF050505),
            body: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final canSwapVideo = hasRemoteVideo && hasLocalVideo;
                  final localIsPrimary = _localVideoIsPrimary && canSwapVideo;
                  final hasPrimaryVideo = hasRemoteVideo || localIsPrimary;
                  final previewWidth = constraints.maxWidth < 600
                      ? 112.0
                      : 144.0;
                  final previewSize = Size(previewWidth, previewWidth * 1.4);
                  final previewPosition = _resolvePreviewPosition(
                    constraints,
                    previewSize,
                  );
                  final showPreview =
                      service.phase != CallPhase.incoming &&
                      (localIsPrimary ? hasRemoteVideo : hasLocalVideo);

                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onDoubleTap: hasPrimaryVideo
                        ? _toggleFullscreenVideo
                        : null,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (localIsPrimary)
                          RTCVideoView(
                            service.localRenderer,
                            mirror: true,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitCover,
                          )
                        else if (hasRemoteVideo)
                          RTCVideoView(
                            service.remoteRenderer,
                            objectFit: RTCVideoViewObjectFit
                                .RTCVideoViewObjectFitCover,
                          )
                        else
                          _buildAudioBackground(service),
                        if (_controlsVisible)
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.72),
                                  Colors.transparent,
                                  Colors.black.withValues(alpha: 0.82),
                                ],
                                stops: const [0, 0.45, 1],
                              ),
                            ),
                          ),
                        if (showPreview)
                          Positioned(
                            left: previewPosition.dx,
                            top: previewPosition.dy,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onPanUpdate: (details) => _moveVideoPreview(
                                details,
                                constraints,
                                previewSize,
                              ),
                              onTap: canSwapVideo ? _swapVideoSurfaces : null,
                              child: _buildVideoPreview(
                                service: service,
                                size: previewSize,
                                showLocalVideo: !localIsPrimary,
                              ),
                            ),
                          ),
                        if (_controlsVisible)
                          Positioned(
                            top: 18,
                            left: 20,
                            right: 20,
                            bottom: 28,
                            child: _buildContent(
                              peer,
                              service,
                              hasPrimaryVideo,
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildVideoPreview({
    required CallService service,
    required Size size,
    required bool showLocalVideo,
  }) {
    final cameraIsOff = showLocalVideo && !service.cameraEnabled;
    return Semantics(
      button: true,
      label: showLocalVideo
          ? 'Ваше видео. Перетащите или нажмите, чтобы увеличить.'
          : 'Видео собеседника. Перетащите или нажмите, чтобы увеличить.',
      child: Container(
        width: size.width,
        height: size.height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _gold.withValues(alpha: 0.82), width: 1.2),
          boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18)],
        ),
        child: cameraIsOff
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam_off_rounded, color: _gold, size: 32),
                    SizedBox(height: 8),
                    Text(
                      'Камера\nвыключена',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              )
            : RTCVideoView(
                showLocalVideo ? service.localRenderer : service.remoteRenderer,
                mirror: showLocalVideo,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
      ),
    );
  }

  Widget _buildContent(String peer, CallService service, bool hasRemoteVideo) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxHeight < 420 ||
            MediaQuery.textScalerOf(context).scale(14) > 21;
        final children = <Widget>[
          Text(
            peer,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            service.statusText,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _gold.withValues(alpha: 0.95),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (service.connectionQualityText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              key: const ValueKey('call-connection-quality'),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.orangeAccent.withValues(alpha: 0.72),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.signal_cellular_connected_no_internet_0_bar_rounded,
                    color: Colors.orangeAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    service.connectionQualityText,
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                service.callE2ee
                    ? Icons.lock_rounded
                    : Icons.lock_outline_rounded,
                color: service.callE2ee ? Colors.greenAccent : Colors.orange,
                size: 16,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  service.callE2ee
                      ? 'Защищённый звонок'
                      : 'Защита E2EE не подтверждена',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: service.callE2ee
                        ? Colors.greenAccent
                        : Colors.orange,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          if (service.clock.connected) ...[
            const SizedBox(height: 8),
            Text(
              service.clock.label,
              key: const ValueKey('call-duration'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontFeatures: [ui.FontFeature.tabularFigures()],
              ),
            ),
          ],
          if (compact)
            SizedBox(
              height: hasRemoteVideo ? 12 : 100,
              child: hasRemoteVideo ? null : _buildPortrait(peer, service),
            )
          else
            Expanded(
              child: hasRemoteVideo
                  ? const SizedBox.expand()
                  : _buildPortrait(peer, service),
            ),
          service.phase == CallPhase.incoming
              ? _buildIncomingActions(service)
              : _buildCallActions(service),
        ];
        return compact
            ? SingleChildScrollView(child: Column(children: children))
            : Column(children: children);
      },
    );
  }

  Widget _buildAudioBackground(CallService service) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.2),
              radius: 1.15,
              colors: [Color(0xFF3D3210), Color(0xFF17130A), Color(0xFF050505)],
            ),
          ),
        ),
        if (service.avatarBytes != null)
          ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Opacity(
              opacity: 0.28,
              child: Image.memory(
                service.avatarBytes!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildPortrait(String peer, CallService service) {
    return LayoutBuilder(
      builder: (context, size) {
        // Reserve real space for the controls, including wrapped/large labels.
        final diameter = (size.maxWidth * 0.74)
            .clamp(0.0, 320.0)
            .clamp(0.0, size.maxHeight * 0.8);
        return Center(
          child: _CallerPortrait(
            bytes: service.avatarBytes,
            name: peer,
            size: diameter,
            pulse:
                service.phase == CallPhase.incoming ||
                service.phase == CallPhase.outgoing ||
                service.phase == CallPhase.connecting,
          ),
        );
      },
    );
  }

  Widget _buildIncomingActions(CallService service) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        CallActionButton(
          icon: Icons.call_end_rounded,
          label: 'Отклонить',
          tooltip: 'Отклонить звонок',
          color: const Color(0xFFE53935),
          onPressed: () {
            unawaited(service.declineIncoming());
          },
        ),
        CallActionButton(
          icon: service.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
          label: 'Принять',
          tooltip: service.isVideo
              ? 'Принять видеозвонок'
              : 'Принять аудиозвонок',
          color: const Color(0xFF32B768),
          onPressed: () {
            unawaited(service.acceptIncoming());
          },
        ),
      ],
    );
  }

  Widget _buildCallActions(CallService service) {
    return CallControls(
      microphoneEnabled: service.microphoneEnabled,
      cameraEnabled: service.cameraEnabled,
      isVideo: service.isVideo,
      canSwitchCamera: service.canSwitchCamera,
      onMicrophone: service.toggleMicrophone,
      onCamera: service.toggleCamera,
      onSwitchCamera: () => unawaited(service.switchCamera()),
      onHangUp: () => unawaited(service.hangUp()),
      speakerphoneEnabled: service.speakerphoneEnabled,
      onSpeakerphone: service.canSwitchSpeaker
          ? () => unawaited(service.toggleSpeakerphone())
          : null,
    );
  }
}

class _CallerPortrait extends StatefulWidget {
  const _CallerPortrait({
    required this.bytes,
    required this.name,
    required this.size,
    required this.pulse,
  });
  final Uint8List? bytes;
  final String name;
  final double size;
  final bool pulse;
  @override
  State<_CallerPortrait> createState() => _CallerPortraitState();
}

class _CallerPortraitState extends State<_CallerPortrait>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );
  void _sync() {
    final animate = widget.pulse && !MediaQuery.disableAnimationsOf(context);
    if (animate && !_pulse.isAnimating) _pulse.repeat(reverse: true);
    if (!animate) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _CallerPortrait oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    final fallback = Center(
      child: Text(
        widget.name.isEmpty ? '?' : widget.name.characters.first.toUpperCase(),
        style: TextStyle(
          fontSize: widget.size * 0.38,
          color: gold,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
    return Semantics(
      label: 'Аватар: ${widget.name}',
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) => Container(
          width: widget.size,
          height: widget.size,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: gold.withValues(alpha: 0.65 + _pulse.value * 0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: gold.withValues(alpha: 0.12 + _pulse.value * 0.13),
                blurRadius: 28 + _pulse.value * 22,
                spreadRadius: 5 + _pulse.value * 12,
              ),
            ],
          ),
          child: child,
        ),
        child: ClipOval(
          child: ColoredBox(
            color: const Color(0xFF171717),
            child: widget.bytes == null
                ? fallback
                : Image.memory(
                    widget.bytes!,
                    fit: BoxFit.cover,
                    width: widget.size,
                    height: widget.size,
                    errorBuilder: (_, _, _) => fallback,
                  ),
          ),
        ),
      ),
    );
  }
}
