import 'dart:convert';

/// Network orchestration only. Native certificate verification and journaled
/// key/session changes MUST happen in the supplied verified apply callback.
class ContactContinuityRouter {
  ContactContinuityRouter({
    required this.readHead,
    required this.fetchDirectory,
    required this.applyVerified,
  });
  final Future<Map<String, dynamic>> Function(String peer) readHead;
  final Future<Map<String, dynamic>> Function(String peer, int epoch)
  fetchDirectory;
  final Future<void> Function(
    String peer,
    Map<String, dynamic> bundle,
    String accountId,
    List<Map<String, dynamic>> certificates,
    bool Function() current,
  )
  applyVerified;
  Future<bool> applyIfChanged(
    String peer,
    Map<String, dynamic> bundle, {
    required bool Function() isCurrent,
  }) async {
    void check() {
      if (!isCurrent()) throw StateError('Contact continuity session changed');
    }

    check();
    final copy = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(bundle)) as Map,
    );
    if (jsonEncode(copy).length > 32768)
      throw StateError('Continuity bundle too large');
    final head = await readHead(peer);
    check();
    final pinned = head['identityKey'];
    if (pinned == null || pinned == copy['identityKey']) return false;
    final epoch = head['epoch'];
    if (epoch is! int || epoch < 0)
      throw StateError('Invalid local continuity epoch');
    final directory = await fetchDirectory(peer, epoch);
    check();
    const fields = {
      'username',
      'accountId',
      'available',
      'fromEpoch',
      'toEpoch',
      'currentEpoch',
      'certificates',
    };
    if (directory.length != fields.length ||
        directory.keys.any((k) => !fields.contains(k)) ||
        jsonEncode(directory).length > 65536 ||
        directory['username'] != peer ||
        directory['available'] != true ||
        directory['fromEpoch'] != epoch ||
        directory['accountId'] is! String ||
        (head['accountId'] != null &&
            directory['accountId'] != head['accountId']))
      throw StateError('Continuity directory context differs');
    final to = directory['toEpoch'], certs = directory['certificates'];
    if (to is! int ||
        to <= epoch ||
        to - epoch > 32 ||
        directory['currentEpoch'] != to ||
        certs is! List ||
        certs.length != to - epoch ||
        certs.any((c) => c is! Map))
      throw StateError('Complete current continuity chain required');
    final chain = certs
        .map((c) => Map<String, dynamic>.from(c as Map))
        .toList();
    await applyVerified(
      peer,
      copy,
      directory['accountId'] as String,
      chain,
      isCurrent,
    );
    check();
    return true;
  }
}
