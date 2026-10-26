import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';

class WindowsUpdateCore {
  const WindowsUpdateCore();

  Future<File> downloadAndVerify({
    required Uri uri,
    required int build,
    required String sha256Hex,
    required int sizeBytes,
    required Directory temporaryDirectory,
  }) async {
    if (!Platform.isWindows) {
      throw const FormatException('Windows platform required');
    }

    if (build <= 0 ||
        uri.scheme != 'https' ||
        uri.host != 'fenyvo.com' ||
        uri.port != 443 ||
        !uri.path.endsWith('.zip') ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Untrusted update URL');
    }

    final expectedHash = sha256Hex.trim().toLowerCase();

    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedHash)) {
      throw const FormatException('Invalid update SHA-256');
    }

    if (sizeBytes <= 0 || sizeBytes > 500 * 1024 * 1024) {
      throw const FormatException('Invalid update size');
    }

    final updateDir = Directory(
      '${temporaryDirectory.path}${Platform.pathSeparator}fenyvo-updates',
    );

    await updateDir.create(recursive: true);

    final file = File(
      '${updateDir.path}${Platform.pathSeparator}fenyvo-$build.zip',
    );

    final partial = File('${file.path}.part');

    if (await partial.exists()) {
      await partial.delete();
    }

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);

    IOSink? sink;

    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;

      final response = await request.close();

      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Update HTTP ${response.statusCode}', uri: uri);
      }

      sink = partial.openWrite();

      final digestSink = _DigestCollector();
      final hashSink = sha256.startChunkedConversion(digestSink);

      var received = 0;

      await for (final chunk in response.timeout(const Duration(seconds: 60))) {
        received += chunk.length;

        if (received > sizeBytes) {
          throw const FormatException('Update exceeds expected size');
        }

        hashSink.add(chunk);
        sink.add(chunk);
      }

      hashSink.close();

      await sink.flush();
      await sink.close();
      sink = null;

      if (received != sizeBytes) {
        throw const FormatException('Update size mismatch');
      }

      if (digestSink.digest.toString() != expectedHash) {
        throw const FormatException('Update SHA-256 mismatch');
      }

      if (await file.exists()) {
        await file.delete();
      }

      return await partial.rename(file.path);
    } catch (_) {
      if (sink != null) {
        try {
          await sink.close();
        } catch (_) {}
      }

      if (await partial.exists()) {
        await partial.delete();
      }

      rethrow;
    } finally {
      client.close(force: true);
    }
  }
}

class _DigestCollector implements Sink<Digest> {
  Digest? _value;

  Digest get digest {
    final result = _value;
    if (result == null) {
      throw StateError('SHA-256 digest not available');
    }
    return result;
  }

  @override
  void add(Digest data) {
    _value = data;
  }

  @override
  void close() {}
}
