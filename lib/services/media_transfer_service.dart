import 'dart:convert';
import 'dart:io';

class SpartanMediaUpload {
  final String mediaId;
  final String fileName;
  final int fileSize;
  final String mimeType;

  const SpartanMediaUpload({
    required this.mediaId,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
  });
}

class MediaTransferService {
  static Uri? _baseUri;
  static String _token = '';
  static const int defaultMaxBytes = 1024 * 1024 * 1024;

  static bool get isReady =>
      _baseUri != null && _token.trim().isNotEmpty;

  static Map<String, String> get authHeaders =>
      _token.trim().isEmpty
          ? const <String, String>{}
          : <String, String>{'Authorization': 'Bearer $_token'};

  static void configure({
    required String webSocketUrl,
    required String token,
    required int mediaPort,
  }) {
    final ws = Uri.tryParse(webSocketUrl.trim());
    if (ws == null || ws.host.isEmpty || token.trim().isEmpty) {
      clear();
      return;
    }

    final scheme = ws.scheme.toLowerCase() == 'wss' ? 'https' : 'http';
    _baseUri = Uri(
      scheme: scheme,
      host: ws.host,
      port: mediaPort,
    );
    _token = token.trim();
  }

  static void clear() {
    _baseUri = null;
    _token = '';
  }

  static Uri? mediaUri(String mediaId) {
    final base = _baseUri;
    final id = mediaId.trim();
    if (base == null || id.isEmpty) return null;
    return base.replace(path: '/media/$id', query: null);
  }

  static String? mediaUrl(String mediaId) =>
      mediaUri(mediaId)?.toString();

  static Future<SpartanMediaUpload> uploadFile({
    required String path,
    required String fileName,
    required String mimeType,
    required String messageType,
    int maxBytes = defaultMaxBytes,
  }) async {
    if (!isReady) {
      throw StateError('Медиа-сервер не готов. Перезайдите в аккаунт.');
    }

    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Файл не найден', path);
    }

    final size = await file.length();
    if (size <= 0) {
      throw FileSystemException('Файл пустой', path);
    }
    if (size > maxBytes) {
      throw FileSystemException(
        'Файл слишком большой. Максимум ${(maxBytes / (1024 * 1024)).round()} МБ',
        path,
      );
    }

    final base = _baseUri!;
    final uri = base.replace(
      path: '/media/upload',
      queryParameters: <String, String>{
        'fileName': fileName,
        'mimeType': mimeType,
        'messageType': messageType,
      },
    );

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);

    try {
      final request = await client.postUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        mimeType.trim().isEmpty ? 'application/octet-stream' : mimeType.trim(),
      );
      request.contentLength = size;
      await request.addStream(file.openRead());

      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        String reason = 'Ошибка загрузки файла (${response.statusCode})';
        try {
          final decoded = jsonDecode(body);
          if (decoded is Map && decoded['error'] != null) {
            reason = decoded['error'].toString();
          }
        } catch (_) {}
        throw HttpException(reason, uri: uri);
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        throw const FormatException('Некорректный ответ медиа-сервера');
      }

      final data = Map<String, dynamic>.from(decoded);
      final mediaId = data['mediaId']?.toString().trim() ?? '';
      if (mediaId.isEmpty) {
        throw const FormatException('Медиа-сервер не вернул mediaId');
      }

      return SpartanMediaUpload(
        mediaId: mediaId,
        fileName: data['fileName']?.toString().trim().isNotEmpty == true
            ? data['fileName'].toString().trim()
            : fileName,
        fileSize: int.tryParse(data['fileSize']?.toString() ?? '') ?? size,
        mimeType: data['mimeType']?.toString().trim().isNotEmpty == true
            ? data['mimeType'].toString().trim()
            : mimeType,
      );
    } finally {
      client.close(force: true);
    }
  }

  static Future<void> downloadToFile({
    required String mediaId,
    required String targetPath,
  }) async {
    if (!isReady) {
      throw StateError('Медиа-сервер не готов. Перезайдите в аккаунт.');
    }

    final uri = mediaUri(mediaId);
    if (uri == null) {
      throw ArgumentError('Некорректный mediaId');
    }

    final target = File(targetPath);
    await target.parent.create(recursive: true);
    final partial = File('$targetPath.part');

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        final body = await utf8.decoder.bind(response).join();
        throw HttpException(
          body.trim().isEmpty ? 'Ошибка скачивания (${response.statusCode})' : body,
          uri: uri,
        );
      }

      final sink = partial.openWrite();
      try {
        await response.pipe(sink);
      } catch (_) {
        await sink.close();
        rethrow;
      }

      if (await target.exists()) {
        await target.delete();
      }
      await partial.rename(target.path);
    } finally {
      client.close(force: true);
      if (await partial.exists()) {
        try {
          await partial.delete();
        } catch (_) {}
      }
    }
  }
}
