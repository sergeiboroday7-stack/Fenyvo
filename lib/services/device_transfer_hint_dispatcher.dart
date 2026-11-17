import 'dart:async';

/// Advisory hints cannot authorize an identity change.
class DeviceTransferHintDispatcher {
  DeviceTransferHintDispatcher({
    required this.readTrustedHead,
    required this.refreshBundle,
  });
  final Future<Map<String, dynamic>> Function(
    String peer,
    bool Function() isCurrent,
  )
  readTrustedHead;
  final Future<void> Function(String peer) refreshBundle;
  final Set<String> _inFlight = <String>{};

  Future<void> handle({
    required Object? username,
    required String? owner,
    required bool enabled,
    required bool Function() isCurrent,
  }) async {
    if (!enabled ||
        !isCurrent() ||
        owner == null ||
        owner.isEmpty ||
        username is! String ||
        username.isEmpty ||
        username.length > 128 ||
        username != username.trim() ||
        username == owner)
      return;
    if (!_inFlight.add(username)) return;
    try {
      if (!isCurrent()) return;
      final head = await readTrustedHead(username, isCurrent);
      if (!isCurrent() || head['identityKey'] == null) return;
      await refreshBundle(username);
    } catch (_) {
      // A failed advisory refresh must not change trust.
    } finally {
      _inFlight.remove(username);
    }
  }
}
