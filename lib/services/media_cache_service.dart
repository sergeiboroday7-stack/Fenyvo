import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'media_transfer_service.dart';

class MediaCacheService {
  static Future<Directory> _cacheDirectory() async {
    final root = await getApplicationSupportDirectory();
    final directory = Directory(
      '${root.path}${Platform.pathSeparator}spartan_media_cache',
    );
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static String _safePart(String value) {
    final clean = value
        .replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .trim();
    return clean.isEmpty ? 'media' : clean;
  }

  static String _extensionFor(Map<String, dynamic> message) {
    final name = message['fileName']?.toString().trim() ?? '';
    final dot = name.lastIndexOf('.');
    if (dot >= 0 && dot < name.length - 1) {
      final ext = name.substring(dot).toLowerCase();
      if (RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(ext)) {
        return ext;
      }
    }

    final mime = message['mimeType']?.toString().toLowerCase() ??
        message['voiceMimeType']?.toString().toLowerCase() ??
        '';
    final type = message['messageType']?.toString().toLowerCase() ?? '';

    if (mime.contains('jpeg')) return '.jpg';
    if (mime.contains('png')) return '.png';
    if (mime.contains('webp')) return '.webp';
    if (mime.contains('gif')) return '.gif';
    if (mime.contains('wav')) return '.wav';
    if (mime.contains('ogg')) return '.ogg';
    if (mime.contains('webm')) return '.webm';
    if (mime.contains('quicktime')) return '.mov';
    if (mime.contains('mp4')) return type == 'voice' ? '.m4a' : '.mp4';
    if (mime.contains('mpeg')) return '.mp3';
    if (mime.contains('pdf')) return '.pdf';
    if (mime.contains('text')) return '.txt';

    switch (type) {
      case 'image':
        return '.jpg';
      case 'video':
        return '.mp4';
      case 'voice':
        return '.m4a';
      default:
        return '.bin';
    }
  }

  static String? existingLocalPath(Map<String, dynamic> message) {
    final path = message['localMediaPath']?.toString().trim() ?? '';
    if (path.isEmpty) return null;
    try {
      final file = File(path);
      if (file.existsSync() && file.lengthSync() > 0) return path;
    } catch (_) {}
    return null;
  }

  static String _embeddedData(Map<String, dynamic> message) {
    final media = message['mediaData']?.toString().trim() ?? '';
    if (media.isNotEmpty) return media;
    return message['voiceData']?.toString().trim() ?? '';
  }

  static bool hasEmbeddedData(Map<String, dynamic> message) =>
      _embeddedData(message).isNotEmpty;

  static String? mediaId(Map<String, dynamic> message) {
    final id = message['mediaId']?.toString().trim() ?? '';
    return id.isEmpty ? null : id;
  }

  static bool hasRemoteMedia(Map<String, dynamic> message) =>
      mediaId(message) != null;

  static String? remoteUrl(Map<String, dynamic> message) {
    final id = mediaId(message);
    if (id == null) return null;
    return MediaTransferService.mediaUrl(id);
  }

  static Map<String, String> get remoteHeaders =>
      MediaTransferService.authHeaders;

  static Future<String> _targetPath(Map<String, dynamic> message) async {
    final id = mediaId(message) ??
        message['id']?.toString().trim() ??
        DateTime.now().microsecondsSinceEpoch.toString();
    final directory = await _cacheDirectory();
    return '${directory.path}${Platform.pathSeparator}${_safePart(id)}${_extensionFor(message)}';
  }

  static Future<String?> findCachedRemotePath(
    Map<String, dynamic> message,
  ) async {
    final existing = existingLocalPath(message);
    if (existing != null) return existing;
    if (!hasRemoteMedia(message)) return null;
    final path = await _targetPath(message);
    final file = File(path);
    if (await file.exists() && await file.length() > 0) return path;
    return null;
  }

  static Future<Map<String, dynamic>> cacheEmbeddedMedia(
    Map<String, dynamic> source,
  ) async {
    final message = Map<String, dynamic>.from(source);
    final existing = existingLocalPath(message);
    if (existing != null) {
      message['localMediaPath'] = existing;
      message.remove('mediaData');
      message.remove('voiceData');
      return message;
    }

    final encoded = _embeddedData(message);
    if (encoded.isEmpty) return message;

    final target = File(await _targetPath(message));
    if (!await target.exists() || await target.length() == 0) {
      final bytes = await Isolate.run<Uint8List>(() => base64Decode(encoded));
      if (bytes.isEmpty) return message;
      await target.writeAsBytes(bytes, flush: true);
    }

    message['localMediaPath'] = target.path;
    message.remove('mediaData');
    message.remove('voiceData');
    return message;
  }

  static Future<Map<String, dynamic>> cacheRemoteMedia(
    Map<String, dynamic> source,
  ) async {
    var message = Map<String, dynamic>.from(source);
    final existing = existingLocalPath(message) ??
        await findCachedRemotePath(message);
    if (existing != null) {
      message['localMediaPath'] = existing;
      return message;
    }

    if (hasEmbeddedData(message)) {
      return cacheEmbeddedMedia(message);
    }

    final id = mediaId(message);
    if (id == null) return message;

    final targetPath = await _targetPath(message);
    await MediaTransferService.downloadToFile(
      mediaId: id,
      targetPath: targetPath,
    );
    message['localMediaPath'] = targetPath;
    return message;
  }

  static Future<Uint8List?> readBytes(Map<String, dynamic> message) async {
    var localPath = existingLocalPath(message);
    localPath ??= await findCachedRemotePath(message);
    if (localPath != null) {
      try {
        return await File(localPath).readAsBytes();
      } catch (_) {}
    }

    if (hasRemoteMedia(message)) {
      try {
        final cached = await cacheRemoteMedia(message);
        localPath = existingLocalPath(cached);
        if (localPath != null) return await File(localPath).readAsBytes();
      } catch (_) {
        return null;
      }
    }

    final encoded = _embeddedData(message);
    if (encoded.isEmpty) return null;
    try {
      return await Isolate.run<Uint8List>(() => base64Decode(encoded));
    } catch (_) {
      return null;
    }
  }

  static Uint8List? readBytesSync(Map<String, dynamic> message) {
    final localPath = existingLocalPath(message);
    if (localPath != null) {
      try {
        return File(localPath).readAsBytesSync();
      } catch (_) {}
    }

    final encoded = _embeddedData(message);
    if (encoded.isEmpty) return null;
    try {
      return base64Decode(encoded);
    } catch (_) {
      return null;
    }
  }
}
