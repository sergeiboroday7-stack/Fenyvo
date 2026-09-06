import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:public_file_saver/public_file_saver.dart';

class SpartanDownloadService {
  static const String folderName = 'Spartan Chat';

  static String _safeFileName(String value) {
    final clean = value
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .trim();
    return clean.isEmpty
        ? 'spartan_${DateTime.now().millisecondsSinceEpoch}.bin'
        : clean;
  }

  static Future<String> saveBytes({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final safeName = _safeFileName(fileName);

    if (Platform.isAndroid) {
      final saver = PublicFileSaver();
      final result = await saver.saveBytes(
        bytes: bytes,
        fileName: safeName,
        mimeType: mimeType.trim().isEmpty
            ? 'application/octet-stream'
            : mimeType.trim(),
        subDir: folderName,
      );

      if (result == null || !result.isSuccess) {
        throw FileSystemException('Не удалось сохранить файл');
      }

      final location = result.path?.trim();
      if (location != null && location.isNotEmpty) {
        return location;
      }
      return 'Загрузки/$folderName/$safeName';
    }

    Directory root;
    try {
      root = await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
    } catch (_) {
      root = await getApplicationDocumentsDirectory();
    }

    final directory = Directory(
      '${root.path}${Platform.pathSeparator}$folderName',
    );
    await directory.create(recursive: true);

    var target = File(
      '${directory.path}${Platform.pathSeparator}$safeName',
    );
    if (await target.exists()) {
      final dot = safeName.lastIndexOf('.');
      final stem = dot > 0 ? safeName.substring(0, dot) : safeName;
      final ext = dot > 0 ? safeName.substring(dot) : '';
      target = File(
        '${directory.path}${Platform.pathSeparator}'
        '${stem}_${DateTime.now().millisecondsSinceEpoch}$ext',
      );
    }

    await target.writeAsBytes(bytes, flush: true);
    return target.path;
  }
}
