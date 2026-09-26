import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'crypto/e2ee_media_cipher.dart';

class SpartanMediaUpload {
  final String mediaId;
  final String fileName;
  final int fileSize;
  final String mimeType;
  final Map<String, dynamic>? e2eeMedia;

  const SpartanMediaUpload({
    required this.mediaId,
    required this.fileName,
    required this.fileSize,
    required this.mimeType,
    this.e2eeMedia,
  });
}

class MediaTransferService {
  static Uri? _baseUri;
  static String _token = '';
  static const int defaultMaxBytes = 1024 * 1024 * 1024;

  static bool get isReady => _baseUri != null && _token.trim().isNotEmpty;

  static Map<String, String> get authHeaders => _token.trim().isEmpty
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
    _baseUri = Uri(scheme: scheme, host: ws.host, port: mediaPort);
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

  static String? mediaUrl(String mediaId) => mediaUri(mediaId)?.toString();

  static Future<SpartanMediaUpload> uploadFile({
    required String path,
    required String fileName,
    required String mimeType,
    required String messageType,
    int maxBytes = defaultMaxBytes,
    bool encryptForE2ee = false,
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

    File uploadSource = file;
    Map<String, dynamic>? e2eeMedia;
    String? encryptedPath;
    var uploadName = fileName;
    var uploadMime = mimeType;
    var uploadType = messageType;
    if (encryptForE2ee) {
      final temporary = await getTemporaryDirectory();
      encryptedPath =
          '${temporary.path}${Platform.pathSeparator}spartan_e2ee_${DateTime.now().microsecondsSinceEpoch}.bin';
      final encrypted = await E2eeMediaCipher.encryptFile(
        sourcePath: path,
        targetPath: encryptedPath,
      );
      uploadSource = File(encrypted.encryptedPath);
      e2eeMedia = encrypted.metadata;
      uploadName = 'protected.bin';
      uploadMime = 'application/octet-stream';
      uploadType = 'file';
    }

    final base = _baseUri!;
    final uri = base.replace(
      path: '/media/upload',
      queryParameters: <String, String>{
        'fileName': uploadName,
        'mimeType': uploadMime,
        'messageType': uploadType,
      },
    );

    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);

    try {
      final request = await client.postUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      request.headers.set(
        HttpHeaders.contentTypeHeader,
        uploadMime.trim().isEmpty
            ? 'application/octet-stream'
            : uploadMime.trim(),
      );
      request.contentLength = await uploadSource.length();
      await request.addStream(uploadSource.openRead());

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
        fileName: fileName,
        fileSize: size,
        mimeType: mimeType,
        e2eeMedia: e2eeMedia,
      );
    } finally {
      client.close(force: true);
      if (encryptedPath != null) {
        final encryptedFile = File(encryptedPath);
        if (await encryptedFile.exists()) {
          try {
            await encryptedFile.delete();
          } catch (_) {}
        }
      }
    }
  }

  static Future<void> downloadToFile({
    required String mediaId,
    required String targetPath,
    void Function(int receivedBytes, int? totalBytes)? onProgress,
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
      var downloaded = await partial.exists() ? await partial.length() : 0;
      final request = await client.getUrl(uri);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      if (downloaded > 0) {
        request.headers.set(HttpHeaders.rangeHeader, 'bytes=$downloaded-');
      }
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        final body = await utf8.decoder.bind(response).join();
        throw HttpException(
          body.trim().isEmpty
              ? 'Ошибка скачивания (${response.statusCode})'
              : body,
          uri: uri,
        );
      }

      // A server may ignore Range and return the whole file. In that case the
      // partial file must be replaced instead of appending duplicate bytes.
      final append =
          downloaded > 0 && response.statusCode == HttpStatus.partialContent;
      if (!append) downloaded = 0;
      final responseBytes = response.contentLength >= 0
          ? response.contentLength
          : null;
      final totalBytes = responseBytes == null
          ? null
          : downloaded + responseBytes;
      onProgress?.call(downloaded, totalBytes);

      final sink = partial.openWrite(
        mode: append ? FileMode.append : FileMode.write,
      );
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          downloaded += chunk.length;
          onProgress?.call(downloaded, totalBytes);
        }
        await sink.flush();
        await sink.close();
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
      // Keep an interrupted .part file. The next attempt continues from the
      // last received byte using HTTP Range instead of starting over.
    }
  }
}
