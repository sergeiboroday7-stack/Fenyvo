import 'dart:io';

import 'app_update_service.dart';
import 'windows_update_download_service.dart';

/// Downloads and verifies a Windows update archive.
/// Does not install, extract, or close the running application.
class WindowsUpdatePreparationService {
  const WindowsUpdatePreparationService();

  Future<File> prepare(AppRelease release) async {
    if (!Platform.isWindows || release.platform != 'windows') {
      throw const FormatException('Windows update required');
    }

    if (release.sha256 == null || release.sizeBytes == null) {
      throw const FormatException(
        'Update cannot be installed without integrity metadata',
      );
    }

    return const WindowsUpdateDownloadService().downloadAndVerify(release);
  }
}
