import 'dart:async';

import 'package:flutter/foundation.dart';

/// Keeps presence presentation stable without weakening server-side presence.
///
/// Online transitions are immediate. Offline transitions get a short UI-only
/// grace period so brief lifecycle changes do not make the indicator flicker.
class PresenceTracker extends ChangeNotifier {
  PresenceTracker({this.offlineGrace = const Duration(seconds: 1)});

  final Duration offlineGrace;
  final Map<String, String> _online = <String, String>{};
  final Map<String, Timer> _offlineTimers = <String, Timer>{};

  Set<String> get onlineUsers => Set<String>.unmodifiable(_online.values);

  bool isOnline(String username) => _online.containsKey(_key(username));

  void replaceOnline(Iterable<String> usernames) {
    final next = <String, String>{};
    for (final raw in usernames) {
      final username = raw.trim();
      final key = _key(username);
      if (key.isNotEmpty) next[key] = username;
    }

    var changed = false;
    for (final entry in next.entries) {
      _offlineTimers.remove(entry.key)?.cancel();
      if (_online[entry.key] != entry.value) {
        _online[entry.key] = entry.value;
        changed = true;
      }
    }

    for (final key in _online.keys.toList(growable: false)) {
      if (!next.containsKey(key)) _scheduleOffline(key);
    }

    if (changed) notifyListeners();
  }

  void updateUser(String username, {required bool online}) {
    final displayName = username.trim();
    final key = _key(displayName);
    if (key.isEmpty) return;

    if (online) {
      _offlineTimers.remove(key)?.cancel();
      if (_online[key] != displayName) {
        _online[key] = displayName;
        notifyListeners();
      }
      return;
    }

    _scheduleOffline(key);
  }

  void clearImmediately() {
    for (final timer in _offlineTimers.values) {
      timer.cancel();
    }
    _offlineTimers.clear();
    if (_online.isEmpty) return;
    _online.clear();
    notifyListeners();
  }

  void _scheduleOffline(String key) {
    if (!_online.containsKey(key) || _offlineTimers.containsKey(key)) return;

    _offlineTimers[key] = Timer(offlineGrace, () {
      _offlineTimers.remove(key);
      if (_online.remove(key) != null) notifyListeners();
    });
  }

  static String _key(String username) => username.trim().toLowerCase();

  @override
  void dispose() {
    for (final timer in _offlineTimers.values) {
      timer.cancel();
    }
    _offlineTimers.clear();
    super.dispose();
  }
}
