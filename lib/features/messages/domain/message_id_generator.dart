import 'dart:math';

/// Generates opaque IDs for newly created messages.
///
/// Existing numeric message IDs remain valid and unchanged.
class MessageIdGenerator {
  static final Random _random = Random.secure();

  static String generate() {
    final timestamp = DateTime.now().microsecondsSinceEpoch;

    final randomPart = List<int>.generate(
      8,
      (_) => _random.nextInt(256),
    ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

    return '$timestamp-$randomPart';
  }
}