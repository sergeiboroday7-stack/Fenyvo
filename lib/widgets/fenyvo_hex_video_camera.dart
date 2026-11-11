import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../features/messages/data/private_video_note_capture.dart';
import '../theme/fenyvo_theme.dart';

/// Embedded camera for short FENYVO video notes.
///
/// The parent owns transmission. Captured files are passed to [onCaptured];
/// nothing is transmitted by this widget itself.
enum FenyvoHexCameraCommand { start, send, cancel, lock, switchCamera }

class FenyvoHexCameraControl extends ChangeNotifier {
  FenyvoHexCameraCommand? _command;

  FenyvoHexCameraCommand? get command => _command;

  void _emit(FenyvoHexCameraCommand command) {
    _command = command;
    notifyListeners();
  }

  void startRecording() => _emit(FenyvoHexCameraCommand.start);
  void sendRecording() => _emit(FenyvoHexCameraCommand.send);
  void cancelRecording() => _emit(FenyvoHexCameraCommand.cancel);
  void lockRecording() => _emit(FenyvoHexCameraCommand.lock);
  void switchCamera() => _emit(FenyvoHexCameraCommand.switchCamera);
}

class FenyvoHexVideoCamera extends StatefulWidget {
  const FenyvoHexVideoCamera({
    super.key,
    this.control,
    required this.onCaptured,
    required this.onCancel,
    this.onRecordingChanged,
    required this.languageCode,
  });

  final FenyvoHexCameraControl? control;
  final Future<void> Function(String path) onCaptured;
  final VoidCallback onCancel;
  final ValueChanged<bool>? onRecordingChanged;
  final String languageCode;

  /// Prefer the selfie camera; fall back to an available camera.
  static CameraDescription? preferredCamera(List<CameraDescription> cameras) {
    if (cameras.isEmpty) return null;
    for (final camera in cameras) {
      if (camera.lensDirection == CameraLensDirection.front) {
        return camera;
      }
    }
    return cameras.first;
  }

  @override
  State<FenyvoHexVideoCamera> createState() => _FenyvoHexVideoCameraState();
}

class _FenyvoHexVideoCameraState extends State<FenyvoHexVideoCamera>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  CameraController? _camera;
  List<CameraDescription> _available = const [];
  bool _busy = true;
  bool _recording = false;
  bool _recordingActivityNotified = false;
  bool _locked = false;
  bool _closing = false;
  int _elapsed = 0;
  String? _error;
  Timer? _timer;
  late final AnimationController _gestureHintController;
  bool _startPending = false;
  bool _starting = false;
  bool _sendAfterStart = false;
  bool _cancelAfterStart = false;

  void _notifyRecordingActivity(bool active) {
    if (_recordingActivityNotified == active) return;
    _recordingActivityNotified = active;
    widget.onRecordingChanged?.call(active);
  }

  void _handleExternalCommand() {
    if (_closing || !mounted) return;
    switch (widget.control?.command) {
      case FenyvoHexCameraCommand.start:
        if (_recording || _starting) return;
        _startPending = true;
        _locked = false;
        _sendAfterStart = false;
        _cancelAfterStart = false;
        if (!_busy) unawaited(_start());
      case FenyvoHexCameraCommand.send:
        _startPending = false;
        if (_recording && !_starting) {
          unawaited(_finish(send: true));
        } else if (_starting) {
          _sendAfterStart = true;
        } else {
          widget.onCancel();
        }
      case FenyvoHexCameraCommand.cancel:
        _startPending = false;
        _sendAfterStart = false;
        if (_recording && !_starting) {
          unawaited(_finish(send: false));
        } else if (_starting) {
          _cancelAfterStart = true;
        } else {
          widget.onCancel();
        }
      case FenyvoHexCameraCommand.lock:
        if (_recording || _starting || _startPending) {
          setState(() => _locked = true);
        }
      case FenyvoHexCameraCommand.switchCamera:
        unawaited(_switchCamera());
      case null:
        break;
    }
  }

  String _text(String ru, String uk, String en) {
    if (widget.languageCode.startsWith('uk')) return uk;
    if (widget.languageCode.startsWith('en')) return en;
    return ru;
  }

  @override
  void initState() {
    super.initState();
    _gestureHintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addObserver(this);
    widget.control?.addListener(_handleExternalCommand);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      final cameras = await availableCameras();
      if (!mounted || _closing) return;

      final preferred = FenyvoHexVideoCamera.preferredCamera(cameras);
      if (preferred == null) {
        throw StateError('No camera is available');
      }
      _available = cameras;
      await _selectCamera(preferred);
    } catch (error) {
      if (mounted && !_closing) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _selectCamera(CameraDescription description) async {
    if (_closing || _recording) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final previous = _camera;
    _camera = null;
    if (previous != null) await previous.dispose();

    final next = CameraController(
      description,
      ResolutionPreset.medium,
      enableAudio: true,
    );

    try {
      await next.initialize();
      if (!mounted || _closing) {
        await next.dispose();
        return;
      }
      _camera = next;
      setState(() => _busy = false);
      if (_startPending && !_closing) {
        unawaited(_start());
      }
    } catch (error) {
      await next.dispose();
      if (mounted && !_closing) {
        setState(() {
          _busy = false;
          _error = '$error';
        });
      }
    }
  }

  Future<void> _switchCamera() async {
    final current = _camera;
    if (_busy || _recording || current == null) return;
    final alternatives = _available.where(
      (camera) => camera.lensDirection != current.description.lensDirection,
    );
    if (alternatives.isEmpty) return;
    await _selectCamera(alternatives.first);
  }

  Future<void> _start() async {
    final camera = _camera;
    if (_busy ||
        _recording ||
        _starting ||
        camera == null ||
        !camera.value.isInitialized) {
      return;
    }

    _starting = true;
    _startPending = false;
    try {
      await camera.startVideoRecording();
      if (!mounted || _closing) {
        await _discardRecording(camera);
        return;
      }
      _timer?.cancel();
      setState(() {
        _recording = true;
        _elapsed = 0;
      });
      _notifyRecordingActivity(true);

      _starting = false;
      if (_cancelAfterStart || _sendAfterStart) {
        final shouldSend = _sendAfterStart && !_cancelAfterStart;
        _cancelAfterStart = false;
        _sendAfterStart = false;
        unawaited(_finish(send: shouldSend));
        return;
      }

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || !_recording) {
          timer.cancel();
          return;
        }
        setState(() => _elapsed += 1);
        if (_elapsed >= PrivateVideoNoteCapture.maximumDuration.inSeconds) {
          timer.cancel();
          unawaited(_finish(send: true));
        }
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      _starting = false;
    }
  }

  Future<void> _discardRecording(CameraController camera) async {
    if (!camera.value.isRecordingVideo) return;
    try {
      final recording = await camera.stopVideoRecording();
      final file = File(recording.path);
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  Future<void> _finish({required bool send}) async {
    if (!_recording || _busy) return;
    final camera = _camera;
    if (camera == null) return;

    _timer?.cancel();
    setState(() {
      _busy = true;
      _recording = false;
      _locked = false;
    });
    _notifyRecordingActivity(false);

    try {
      final recorded = await camera.stopVideoRecording();
      final file = File(recorded.path);
      final valid =
          await file.exists() &&
          PrivateVideoNoteCapture.isValidSize(await file.length());

      if (!send || !valid) {
        if (await file.exists()) await file.delete();
        if (!valid && send) throw StateError('Invalid video note size');
        if (mounted) widget.onCancel();
        return;
      }

      await widget.onCaptured(recorded.path);
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
    } finally {
      if (mounted && !_closing) setState(() => _busy = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      _timer?.cancel();
      _notifyRecordingActivity(false);
      final camera = _camera;
      if (camera != null && camera.value.isRecordingVideo) {
        unawaited(_discardRecording(camera));
      }
      if (mounted) {
        setState(() {
          _recording = false;
          _busy = true;
        });
      }
      unawaited(_camera?.dispose());
      _camera = null;
    } else if (state == AppLifecycleState.resumed &&
        !_closing &&
        _camera == null) {
      unawaited(_initialize());
    }
  }

  @override
  void dispose() {
    _closing = true;
    _notifyRecordingActivity(false);
    _timer?.cancel();
    _gestureHintController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    widget.control?.removeListener(_handleExternalCommand);
    final camera = _camera;
    _camera = null;
    if (camera != null) {
      unawaited(() async {
        await _discardRecording(camera);
        await camera.dispose();
      }());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final ready = !_busy && camera != null && camera.value.isInitialized;

    return Material(
      color: const Color(0xFF071527),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _text('Видеосообщение', 'Відеоповідомлення', 'Video message'),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: 260,
              height: 290,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipPath(
                    clipper: const _HexCameraClipper(),
                    child: ColoredBox(
                      color: const Color(0xFF142840),
                      child: ready
                          ? CameraPreview(camera)
                          : Center(
                              child: _busy
                                  ? const CircularProgressIndicator(
                                      color: FenyvoPalette.gold,
                                    )
                                  : const Icon(
                                      Icons.videocam_off_outlined,
                                      color: FenyvoPalette.gold,
                                      size: 42,
                                    ),
                            ),
                    ),
                  ),
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _HexCameraBorder(
                        recording: _recording,
                        progress: _recording
                            ? (_elapsed /
                                      PrivateVideoNoteCapture
                                          .maximumDuration
                                          .inSeconds)
                                  .clamp(0.0, 1.0)
                                  .toDouble()
                            : 1.0,
                      ),
                    ),
                  ),
                  if (_recording)
                    Positioned(
                      top: 7,
                      right: 7,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: const Color(0xFF071527)
                                .withValues(alpha: 0.82),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: FenyvoPalette.gold,
                              width: 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: Icon(
                              _locked
                                  ? Icons.lock_rounded
                                  : Icons.lock_open_rounded,
                              color: FenyvoPalette.gold,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_recording)
                    Positioned(
                      top: 45,
                      left: 65,
                      right: 65,
                      child: Text(
                        '● 0:${_elapsed.toString().padLeft(2, '0')}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: FenyvoPalette.gold,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_recording)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: _locked
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.lock_rounded,
                            color: FenyvoPalette.gold,
                            size: 20,
                          ),
                          const SizedBox(width: 7),
                          Text(
                            _text(
                              'Запись закреплена',
                              'Запис закріплено',
                              'Recording locked',
                            ),
                            style: const TextStyle(
                              color: FenyvoPalette.gold,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : AnimatedBuilder(
                        animation: _gestureHintController,
                        builder: (context, child) {
                          final shift = _gestureHintController.value * 6.0;
                          return Wrap(
                            alignment: WrapAlignment.center,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 14,
                            runSpacing: 7,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Transform.translate(
                                    offset: Offset(-shift, 0),
                                    child: const Icon(
                                      Icons.arrow_back_rounded,
                                      color: FenyvoPalette.gold,
                                      size: 21,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _text(
                                      'Влево — отмена',
                                      'Вліво — скасувати',
                                      'Left — cancel',
                                    ),
                                    style: const TextStyle(
                                      color: FenyvoPalette.gold,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Transform.translate(
                                    offset: Offset(0, -shift),
                                    child: const Icon(
                                      Icons.lock_open_rounded,
                                      color: FenyvoPalette.gold,
                                      size: 21,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _text(
                                      'Вверх — замок',
                                      'Вгору — замок',
                                      'Up — lock',
                                    ),
                                    style: const TextStyle(
                                      color: FenyvoPalette.gold,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  _text('Ошибка камеры', 'Помилка камери', 'Camera error'),
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: _text('Отмена', 'Скасувати', 'Cancel'),
                  onPressed: () {
                    if (_recording) {
                      unawaited(_finish(send: false));
                    } else {
                      widget.onCancel();
                    }
                  },
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _busy
                      ? null
                      : _recording
                      ? () => unawaited(_finish(send: true))
                      : () => unawaited(_start()),
                  style: FilledButton.styleFrom(
                    backgroundColor: FenyvoPalette.gold,
                    foregroundColor: Colors.black,
                  ),
                  icon: Icon(
                    _recording
                        ? Icons.send_rounded
                        : Icons.fiber_manual_record_rounded,
                  ),
                  label: Text(
                    _recording
                        ? _text('Отправить', 'Надіслати', 'Send')
                        : _text('Запись', 'Запис', 'Record'),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton(
                  tooltip: _text(
                    'Сменить камеру',
                    'Змінити камеру',
                    'Switch camera',
                  ),
                  onPressed: ready && !_recording
                      ? () => unawaited(_switchCamera())
                      : null,
                  icon: const Icon(
                    Icons.cameraswitch_rounded,
                    color: FenyvoPalette.gold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HexCameraClipper extends CustomClipper<Path> {
  const _HexCameraClipper();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(w * .5, 0)
      ..lineTo(w, h * .25)
      ..lineTo(w, h * .75)
      ..lineTo(w * .5, h)
      ..lineTo(0, h * .75)
      ..lineTo(0, h * .25)
      ..close();
  }

  @override
  bool shouldReclip(covariant _HexCameraClipper oldClipper) => false;
}

class _HexCameraBorder extends CustomPainter {
  const _HexCameraBorder({required this.recording, required this.progress});

  final bool recording;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final path = const _HexCameraClipper().getClip(size);

    // Keep the complete hexagon visible as a dim track.
    canvas.drawPath(
      path,
      Paint()
        ..color = recording
            ? FenyvoPalette.gold.withValues(alpha: 0.22)
            : FenyvoPalette.gold
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round,
    );

    if (!recording) return;

    final fraction = progress.clamp(0.0, 1.0).toDouble();
    if (fraction <= 0) return;

    final progressPaint = Paint()
      ..color = FenyvoPalette.gold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // The golden line follows the six actual edges.
    for (final metric in path.computeMetrics()) {
      canvas.drawPath(
        metric.extractPath(0.0, metric.length * fraction),
        progressPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HexCameraBorder oldDelegate) {
    return oldDelegate.recording != recording ||
        oldDelegate.progress != progress;
  }
}
