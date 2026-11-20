import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

class ProfileWriterUnavailable implements Exception {
  const ProfileWriterUnavailable();
  @override
  String toString() => 'FENYVO profile writer unavailable';
}

/// Foreground profile writer lease. OS socket excludes same-process isolates;
/// advisory file lock excludes cooperating processes using this profile path.
/// Never delete/replace the lock file: its stable inode is part of the lease.
class ProfileWriterLease {
  ProfileWriterLease._(this._file, this._socket, this._clients);
  final RandomAccessFile _file;
  final ServerSocket _socket;
  final StreamSubscription<Socket> _clients;
  Future<void>? _closing;
  static Future<ProfileWriterLease> acquire(Directory directory) async {
    RandomAccessFile? file;
    ServerSocket? socket;
    StreamSubscription<Socket>? clients;
    try {
      await directory.create(recursive: true);
      var canonical = await directory.resolveSymbolicLinks();
      if (Platform.isWindows)
        canonical = canonical.replaceAll('\\', '/').toLowerCase();
      final digest = sha256
          .convert(utf8.encode('FENYVO_PROFILE_WRITER_V1\u0000' + canonical))
          .bytes;
      final port = 20000 + ((digest[0] << 8) | digest[1]) % 40000;
      socket = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
        shared: false,
      );
      clients = socket.listen(
        (client) => client.destroy(),
        onError: (Object _) {},
      );
      file = await File(
        directory.path +
            Platform.pathSeparator +
            'fenyvo-profile-writer-v1.lock',
      ).open(mode: FileMode.append);
      await file.lock(FileLock.exclusive);
      return ProfileWriterLease._(file, socket, clients);
    } catch (_) {
      try {
        await file?.close();
      } catch (_) {}
      try {
        await clients?.cancel();
      } catch (_) {}
      try {
        await socket?.close();
      } catch (_) {}
      throw const ProfileWriterUnavailable();
    }
  }

  Future<void> close() => _closing ??= _close();
  Future<void> _close() async {
    try {
      await _file.unlock();
    } finally {
      try {
        await _file.close();
      } finally {
        try {
          await _clients.cancel();
        } finally {
          await _socket.close();
        }
      }
    }
  }
}
