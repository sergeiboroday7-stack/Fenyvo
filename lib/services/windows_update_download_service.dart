import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'app_update_service.dart';
import 'windows_update_core.dart';

class WindowsUpdateDownloadService {
  const WindowsUpdateDownloadService();

  Future<File> downloadAndVerify(
    AppRelease release, {
    Directory? temporaryDirectory,
  }) async {
    if (!Platform.isWindows || release.platform != 'windows') {
      throw const FormatException('Windows update required');
    }

    final expectedHash = release.sha256;
    final expectedSize = release.sizeBytes;

    if (expectedHash == null || expectedSize == null) {
      throw const FormatException('Incomplete update metadata');
    }

    final temp = temporaryDirectory ?? await getTemporaryDirectory();

    return WindowsUpdateCore().downloadAndVerify(
      uri: release.downloadUrl,
      build: release.build,
      sha256Hex: expectedHash,
      sizeBytes: expectedSize,
      temporaryDirectory: temp,
    );
  }
}
