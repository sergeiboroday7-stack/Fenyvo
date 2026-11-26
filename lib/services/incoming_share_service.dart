import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

@immutable
class IncomingShareImage {
  const IncomingShareImage({
    required this.path,
    required this.fileName,
    required this.mimeType,
  });

  final String path;
  final String fileName;
  final String mimeType;
}

@immutable
class IncomingSharePayload {
  const IncomingSharePayload({required this.text, required this.images});

  final String text;
  final List<IncomingShareImage> images;

  static IncomingSharePayload? fromPlatform(Object? raw) {
    if (raw is! Map) return null;
    final text = raw['text'] is String ? raw['text'] as String : '';
    final imageValues = raw['images'];
    if (imageValues is! List) return null;
    if (imageValues.length > 5 || text.length > 8192) return null;
    final images = <IncomingShareImage>[];
    for (final item in imageValues) {
      if (item is! Map) return null;
      final path = item['path'];
      final fileName = item['fileName'];
      final mimeType = item['mimeType'];
      if (path is! String ||
          fileName is! String ||
          mimeType is! String ||
          !path.startsWith('/') ||
          path.contains('..') ||
          !mimeType.startsWith('image/') ||
          fileName.isEmpty) {
        return null;
      }
      images.add(IncomingShareImage(
        path: path,
        fileName: fileName,
        mimeType: mimeType,
      ));
    }
    if (text.trim().isEmpty && images.isEmpty) return null;
    return IncomingSharePayload(text: text, images: List.unmodifiable(images));
  }
}

/// Android incoming share bridge. External data is queued until login finishes.
class IncomingShareService extends ChangeNotifier {
  IncomingShareService._();
  static final IncomingShareService instance = IncomingShareService._();

  static const _channel = MethodChannel('fenyvo/incoming_share');
  IncomingSharePayload? _pending;
  String? _pendingError;
  bool _initialized = false;
  bool _loading = false;
  bool _reloadRequested = false;

  IncomingSharePayload? get pending => _pending;

  Future<void> initialize() async {
    if (!Platform.isAndroid || _initialized) return;
    _initialized = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'shareAvailable') await _load();
    });
    await _load();
  }

  Future<void> _load() async {
    if (_loading) {
      _reloadRequested = true;
      return;
    }
    _loading = true;
    try {
      final raw = await _channel.invokeMethod<Object?>('getPendingShare');
      if (raw is Map && raw['error'] is String) {
        _pendingError = raw['error'] as String;
        notifyListeners();
      } else {
        final payload = IncomingSharePayload.fromPlatform(raw);
        if (payload != null) {
          _pending = payload;
          notifyListeners();
        }
      }
    } on PlatformException {
      _pendingError = 'Не удалось получить файл из Android';
      notifyListeners();
    } finally {
      _loading = false;
      if (_reloadRequested) {
        _reloadRequested = false;
        unawaited(_load());
      }
    }
  }

  IncomingSharePayload? takePending() {
    final share = _pending;
    _pending = null;
    return share;
  }

  String? takeError() {
    final error = _pendingError;
    _pendingError = null;
    return error;
  }
}
