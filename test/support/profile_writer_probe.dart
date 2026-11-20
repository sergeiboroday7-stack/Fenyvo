import 'dart:convert';
import 'dart:io';

import '../../lib/services/profile_writer_lease.dart';

Future<void> main(List<String> args) async {
  ProfileWriterLease? lease;
  try {
    lease = await ProfileWriterLease.acquire(Directory(args.single));
    stdout.writeln('ACQUIRED');
    await stdout.flush();
    await stdin.transform(utf8.decoder).transform(const LineSplitter()).first;
  } on ProfileWriterUnavailable {
    stdout.writeln('BLOCKED');
  } finally {
    await lease?.close();
  }
}
