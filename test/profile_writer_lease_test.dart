import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/profile_writer_lease.dart';

Future<({Process process, StreamIterator<String> lines, String status})> child(
  Directory directory,
) async {
  final dart = Platform.environment['FENYVO_DART'];
  if (dart == null) throw StateError('FENYVO_DART missing');
  final process = await Process.start(dart, [
    '--packages=.dart_tool/package_config.json',
    'test/support/profile_writer_probe.dart',
    directory.path,
  ], workingDirectory: Directory.current.path);
  final errors = StringBuffer();
  process.stderr.transform(utf8.decoder).listen(errors.write);
  final lines = StreamIterator<String>(
    process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
  );
  if (!await lines.moveNext().timeout(const Duration(seconds: 15)))
    throw StateError('Probe failed: ' + errors.toString());
  return (process: process, lines: lines, status: lines.current);
}

Future<void> finish(Process process, StreamIterator<String> lines) async {
  try {
    process.stdin.writeln('close');
    await process.stdin.flush();
    await process.stdin.close();
  } catch (_) {}
  try {
    await process.exitCode.timeout(const Duration(seconds: 5));
  } catch (_) {
    process.kill();
    await process.exitCode;
  }
  await lines.cancel();
}

void main() {
  test(
    'second lease in same isolate is blocked and close releases it',
    () async {
      final dir = await Directory.systemTemp.createTemp('fenyvo-writer-test-');
      ProfileWriterLease? first, next;
      try {
        first = await ProfileWriterLease.acquire(dir);
        await expectLater(
          ProfileWriterLease.acquire(dir),
          throwsA(isA<ProfileWriterUnavailable>()),
        );
        await first.close();
        next = await ProfileWriterLease.acquire(dir);
      } finally {
        await next?.close();
        await first?.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'child process writer blocks foreground writer and orderly exit releases',
    () async {
      final dir = await Directory.systemTemp.createTemp('fenyvo-writer-test-');
      final probe = await child(dir);
      ProfileWriterLease? next;
      try {
        expect(probe.status, 'ACQUIRED');
        await expectLater(
          ProfileWriterLease.acquire(dir),
          throwsA(isA<ProfileWriterUnavailable>()),
        );
        await finish(probe.process, probe.lines);
        next = await ProfileWriterLease.acquire(dir);
      } finally {
        await next?.close();
        await finish(probe.process, probe.lines);
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'foreground writer blocks another process using the same profile',
    () async {
      final dir = await Directory.systemTemp.createTemp('fenyvo-writer-test-');
      final first = await ProfileWriterLease.acquire(dir);
      try {
        final probe = await child(dir);
        expect(probe.status, 'BLOCKED');
        expect(
          await probe.process.exitCode.timeout(const Duration(seconds: 5)),
          0,
        );
        await probe.lines.cancel();
      } finally {
        await first.close();
        await dir.delete(recursive: true);
      }
    },
  );
  test(
    'process termination releases lease without deleting stable lock file',
    () async {
      final dir = await Directory.systemTemp.createTemp('fenyvo-writer-test-');
      final probe = await child(dir);
      ProfileWriterLease? next;
      try {
        expect(probe.status, 'ACQUIRED');
        probe.process.kill();
        await probe.process.exitCode.timeout(const Duration(seconds: 5));
        await probe.lines.cancel();
        expect(
          await File(
            dir.path + Platform.pathSeparator + 'fenyvo-profile-writer-v1.lock',
          ).exists(),
          isTrue,
        );
        next = await ProfileWriterLease.acquire(dir);
      } finally {
        await next?.close();
        await finish(probe.process, probe.lines);
        await dir.delete(recursive: true);
      }
    },
  );
  test('lease close is idempotent', () async {
    final dir = await Directory.systemTemp.createTemp('fenyvo-writer-test-');
    final lease = await ProfileWriterLease.acquire(dir);
    try {
      await Future.wait([lease.close(), lease.close()]);
      await lease.close();
      final next = await ProfileWriterLease.acquire(dir);
      await next.close();
    } finally {
      await dir.delete(recursive: true);
    }
  });
}
