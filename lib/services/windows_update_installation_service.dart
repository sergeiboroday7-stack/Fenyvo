import 'dart:io';

/// Stages a verified Windows archive and starts the independent updater.
///
/// The caller must terminate FENYVO only after this method returns. The
/// independent PowerShell controller retains the verified process identity,
/// waits for that process to exit, applies the staged files, verifies the first
/// Flutter frame, and rolls back if the new build does not start.
class WindowsUpdateInstallationService {
  const WindowsUpdateInstallationService();

  Future<void> stageAndStart(File archive) async {
    if (!Platform.isWindows) {
      throw const FormatException('Windows platform required');
    }

    if (!await archive.exists()) {
      throw const FileSystemException('Update archive not found');
    }

    final executable = File(Platform.resolvedExecutable);
    final install = executable.parent;
    final installName = install.uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .last;

    if (installName.toLowerCase() != 'fenyvo') {
      throw const FileSystemException(
        'Automatic update requires the standard Fenyvo installation folder',
      );
    }

    final staged = Directory('${install.path}.staged');
    if (await staged.exists() || await File(staged.path).exists()) {
      throw const FileSystemException(
        'A previous staged update exists; recovery is required',
      );
    }

    final expandScript = File(
      '${install.path}${Platform.pathSeparator}Expand-FenyvoUpdate.ps1',
    );
    final startScript = File(
      '${install.path}${Platform.pathSeparator}Start-FenyvoUpdate.ps1',
    );

    if (!await expandScript.exists() || !await startScript.exists()) {
      throw const FileSystemException('Windows update components are missing');
    }

    final powershell = _powershellExecutable();

    try {
      await _runChecked(powershell, [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        expandScript.path,
        '-ArchivePath',
        archive.path,
        '-DestinationPath',
        staged.path,
      ]);

      final startTicksResult = await _runChecked(
        powershell,
        [
          '-NoProfile',
          '-NonInteractive',
          '-Command',
          '(Get-Process -Id $pid).StartTime.ToUniversalTime().Ticks',
        ],
        environment: {'pid': '$pid'},
      );

      final startTicks = int.tryParse(startTicksResult.stdout.trim());
      if (startTicks == null || startTicks <= 0) {
        throw const ProcessException(
          'powershell.exe',
          [],
          'Cannot determine FENYVO process start time',
        );
      }

      await _runChecked(powershell, [
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        startScript.path,
        '-InstallPath',
        install.path,
        '-StagedPath',
        staged.path,
        '-AppProcessId',
        '$pid',
        '-AppProcessStartTicks',
        '$startTicks',
        '-ExecuteController',
      ]);
    } catch (_) {
      if (await staged.exists()) {
        try {
          await staged.delete(recursive: true);
        } catch (_) {
          // Preserve the original failure. The guarded updater will refuse to
          // overwrite a remaining staging directory on the next attempt.
        }
      }
      rethrow;
    }
  }

  String _powershellExecutable() {
    final windowsDirectory = Platform.environment['SystemRoot'];
    if (windowsDirectory != null && windowsDirectory.isNotEmpty) {
      final candidate = File(
        '$windowsDirectory${Platform.pathSeparator}System32'
        '${Platform.pathSeparator}WindowsPowerShell'
        '${Platform.pathSeparator}v1.0'
        '${Platform.pathSeparator}powershell.exe',
      );
      if (candidate.existsSync()) return candidate.path;
    }
    return 'powershell.exe';
  }

  Future<ProcessResult> _runChecked(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
  }) async {
    final result = await Process.run(
      executable,
      arguments,
      runInShell: false,
      environment: environment,
      includeParentEnvironment: true,
    );

    if (result.exitCode != 0) {
      final error = result.stderr.toString().trim();
      throw ProcessException(
        executable,
        arguments,
        error.isEmpty ? 'Windows updater failed' : error,
        result.exitCode,
      );
    }
    return result;
  }
}
