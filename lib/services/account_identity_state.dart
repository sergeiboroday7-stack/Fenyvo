/* Optional account metadata; no chat routing or Signal trust changes. */
class AccountIdentityState {
  String? _username;
  String? _accountId;
  static final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  void bind({required String username, Object? accountId}) {
    clear();
    final owner = username.trim();
    if (owner.isEmpty) return;
    _username = owner;
    if (accountId is String &&
        accountId.length == 36 &&
        _uuid.hasMatch(accountId)) {
      _accountId = accountId;
    }
  }

  String? accountIdFor(String? username) {
    final owner = username?.trim();
    if (owner == null || owner.isEmpty || owner != _username) return null;
    return _accountId;
  }

  void clear() {
    _username = null;
    _accountId = null;
  }
}
