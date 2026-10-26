import 'dart:io';

import 'package:flutter/widgets.dart';

/// Reports that the first Flutter frame has been rendered.
///
/// This is a startup signal, not proof that networking or every
/// application feature is healthy.
class WindowsUpdateReadyService {
  WindowsUpdateReadyService._();

  static const _tokenPrefix = '--fenyvo-update-token=';
  static const _filePrefix = '--fenyvo-update-ready-file=';
  static const _tokenEnvironment = 'FENYVO_UPDATE_TOKEN';
  static const _fileEnvironment = 'FENYVO_UPDATE_READY_FILE';

  static void initialize(List<String> arguments) {
    if (!Platform.isWindows) return;

    String? token;
    String? filePath;

    for (final argument in arguments) {
      if (argument.startsWith(_tokenPrefix)) {
        token = argument.substring(_tokenPrefix.length);
      } else if (argument.startsWith(_filePrefix)) {
        filePath = argument.substring(_filePrefix.length);
      }
    }

    token ??= Platform.environment[_tokenEnvironment];
    filePath ??= Platform.environment[_fileEnvironment];

    if (token == null ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(token) ||
        filePath == null ||
        filePath.isEmpty) {
      return;
    }

    final expectedToken = token;
    final destination = filePath;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _writeReadySignal(destination, expectedToken);
    });
  }

  static void _writeReadySignal(String filePath, String token) {
    try {
      final file = File(filePath);

      if (file.existsSync()) return;

      file.writeAsStringSync('$token\n', flush: true);
    } catch (_) {
      // Reporting must never prevent FENYVO from starting.
    }
  }
}
