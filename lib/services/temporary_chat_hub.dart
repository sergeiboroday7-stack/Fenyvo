import 'dart:async';

import 'package:flutter/foundation.dart';

import 'socket_service.dart';
import 'temporary_chat_history_store.dart';
import 'crypto/temporary_signal_e2ee_service.dart';
import 'temporary_trust_message.dart';
import '../screens/temporary_chat_ui_guard.dart';

/// Short-lived in-memory UI state, never persistent plaintext storage.
/// Server access and E2EE keys remain authoritative. No auto-rejoin is sent.
class TemporaryChatHub extends ChangeNotifier {
  TemporaryChatHub._();
  static final TemporaryChatHub instance = TemporaryChatHub._();

  bool _subscribed = false;
  String? _accountId;
  String? _owner;
  int? _generation;
  final Map<String, TemporaryChatRecord> _records = {};
  final Set<String> _pendingApprovals = {};
  final TemporaryChatHistoryStore _historyStore = TemporaryChatHistoryStore();
  final Map<String, Future<void>> _historyJobs = {};
  final Map<String, int> _historyEpoch = {};
  final Set<String> _restored = {};
  int _accountEpoch = 0;

  String _historyJobKey(String account, String id, String role) =>
      '$account/$id/$role';

  void _queue(String key, Future<void> Function() action) {
    final previous = _historyJobs[key] ?? Future<void>.value();
    final job = previous.catchError((Object _) {}).then((_) => action());
    _historyJobs[key] = job.catchError((Object _) {});
  }

  void _saveHistory(TemporaryChatRecord r) {
    if (!_sameAccount || !r.expiresAt.isAfter(DateTime.now())) return;
    final account = _accountId!;
    final key = _historyJobKey(account, r.sessionId, r.role);
    final epoch = _historyEpoch[key] ?? 0;
    final generation = _accountEpoch;
    final expiry = r.expiresAt;
    final lines = r.messages.where((m) => !m.system).map((m) =>
        TemporaryHistoryLine(text: m.text, outgoing: m.outgoing,
            timestamp: m.timestamp ?? DateTime.now().toUtc())).toList(growable: false);
    _queue(key, () async {
      if (generation != _accountEpoch ||
          epoch != (_historyEpoch[key] ?? 0) ||
          !_sameAccount || _records[r.sessionId] != r) return;
      await _historyStore.save(accountId: account, sessionId: r.sessionId,
          role: r.role, expiresAt: expiry, lines: lines);
    });
  }

  void _restoreHistory(TemporaryChatRecord r) {
    final account = _accountId;
    if (account == null || !_sameAccount) return;
    final key = _historyJobKey(account, r.sessionId, r.role);
    if (!_restored.add(key)) return;
    final generation = _accountEpoch;
    final epoch = _historyEpoch[key] ?? 0;
    _queue(key, () async {
      if (!_sameAccount || generation != _accountEpoch ||
          epoch != (_historyEpoch[key] ?? 0) ||
          _records[r.sessionId] != r) return;
      // A server-accepted UI record alone cannot unlock old plaintext.
      // Require the pre-existing local Signal identity AND peer ratchet.
      final hasSignal = await TemporarySignalE2eeService(accountId: account)
          .hasExistingRecoveryState(r.sessionId, r.role);
      if (!hasSignal || !_sameAccount || generation != _accountEpoch ||
          epoch != (_historyEpoch[key] ?? 0) ||
          _records[r.sessionId] != r) return;
      final saved = await _historyStore.read(
          accountId: account, sessionId: r.sessionId, role: r.role);
      if (!_sameAccount || generation != _accountEpoch ||
          epoch != (_historyEpoch[key] ?? 0) ||
          _records[r.sessionId] != r ||
          !r.expiresAt.isAfter(DateTime.now())) return;
      if (saved.isEmpty) return;
      // Messages arriving while reading secure storage must not disappear.
      final live = List<TemporaryChatLine>.from(r.messages);
      r.messages
        ..clear()
        ..addAll(saved.map((m) => TemporaryChatLine(
            text: m.text, outgoing: m.outgoing, timestamp: m.timestamp)))
        ..addAll(live);
      if (r.messages.length > 200) {
        r.messages.removeRange(0, r.messages.length - 200);
      }
      notifyListeners();
    });
  }

  void _deleteHistory(String id, String role) {
    final account = _accountId;
    if (account == null) return;
    final key = _historyJobKey(account, id, role);
    _historyEpoch[key] = (_historyEpoch[key] ?? 0) + 1;
    _restored.remove(key);
    _queue(key, () => _historyStore.delete(
        accountId: account, sessionId: id, role: role));
  }


  void attach() {
    if (_subscribed) return;
    SocketService.instance.addMessageHandler(_receive);
    _subscribed = true;
  }

  void _scope() {
    final socket = SocketService.instance;
    final account = socket.currentAccountId;
    final owner = socket.currentUser;
    final generation = socket.deviceTransferSessionGeneration;
    if (account == null || owner == null || !socket.isAuthenticated) return;
    if (_accountId != null &&
        (_accountId != account || _owner != owner || _generation != generation)) {
      _accountEpoch++;
      _records.clear();
      _pendingApprovals.clear();
      _restored.clear();
    }
    _accountId = account;
    _owner = owner;
    _generation = generation;
  }

  bool get _sameAccount {
    final s = SocketService.instance;
    return s.isAuthenticated &&
        _accountId != null &&
        _accountId == s.currentAccountId &&
        _owner == s.currentUser &&
        _generation == s.deviceTransferSessionGeneration;
  }

  List<TemporaryChatRecord> get active {
    _scope();
    if (!_sameAccount) return const [];
    final now = DateTime.now();
    _records.removeWhere((_, r) => !r.expiresAt.isAfter(now));
    return _records.values.toList()
      ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
  }

  int get activeCount => active.length;
  int get pendingCount {
    _scope();
    return _sameAccount ? _pendingApprovals.length : 0;
  }

  void clearPending() {
    _pendingApprovals.clear();
    notifyListeners();
  }

  int get unreadCount => active.fold(0, (sum, r) => sum + r.unread);

  TemporaryChatRecord? find(String id) {
    _scope();
    if (!_sameAccount) return null;
    final r = _records[id];
    if (r == null || !r.expiresAt.isAfter(DateTime.now())) return null;
    return r;
  }

  void register({required String sessionId, required String role, required DateTime expiresAt}) {
    attach();
    _scope();
    if (!_sameAccount || !TemporaryChatUiGuard.validSession(sessionId, role) ||
        !expiresAt.isAfter(DateTime.now())) return;
    final old = _records[sessionId];
    if (old != null) {
      if (old.role != role) return;
      old.expiresAt = expiresAt;
    } else {
      _records[sessionId] = TemporaryChatRecord(sessionId, role, expiresAt);
    }
    _restoreHistory(_records[sessionId]!);
    notifyListeners();
  }

  /// Remove UI state only after a positive server revocation or its
  /// authenticated peer notification. Never use this for the Back button.
  void removeServerEnded(String sessionId) {
    _scope();
    if (!_sameAccount || !RegExp(r'^[a-f0-9]{48}$').hasMatch(sessionId)) return;
    final old = _records.remove(sessionId);
    if (old != null) {
      _deleteHistory(sessionId, old.role);
      notifyListeners();
    }
  }

  void viewing(String id, bool isViewing) {
    final r = find(id);
    if (r == null) return;
    r.viewing = isViewing;
    if (isViewing) r.unread = 0;
    notifyListeners();
  }

  void outgoing(String id, String text, {bool system = false}) {
    final r = find(id);
    if (r == null) return;
    _append(r, TemporaryChatLine(text: text, outgoing: true, system: system));
  }

  void system(String id, String text, {bool outgoing = false}) {
    final r = find(id);
    if (r == null) return;
    _append(r, TemporaryChatLine(text: text, outgoing: outgoing, system: true));
  }

  void _append(TemporaryChatRecord r, TemporaryChatLine line) {
    r.messages.add(line);
    if (r.messages.length > 200) r.messages.removeAt(0);
    r.lastActivity = DateTime.now();
    if (!r.viewing && !line.outgoing) r.unread++;
    if (!line.system) _saveHistory(r);
    notifyListeners();
  }

  void _receive(Map<String, dynamic> event) {
    // No raw ciphertext is handled here: SocketService notifies only after decrypt.
    _scope();
    if (!_sameAccount) return;
    if (event['type'] == 'temporary_contact_join_request') {
      final data = event['data'];
      if (data is Map) {
        final id = data['requestId']?.toString() ?? '';
        if (RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
          _pendingApprovals.add(id);
          notifyListeners();
        }
      }
      return;
    }
    if (event['type'] == 'temporary_contact_pending_list') {
      final data = event['data'];
      if (data is Map && data['requests'] is List) {
        _pendingApprovals.clear();
        for (final request in data['requests'] as List) {
          if (request is! Map) continue;
          final id = request['requestId']?.toString() ?? '';
          if (RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) _pendingApprovals.add(id);
        }
        notifyListeners();
      }
      return;
    }
    if (event['type'] == 'temporary_contact_ended') {
      final raw = event['data'];
      if (raw is! Map) return;
      final id = raw['sessionId']?.toString() ?? '';
      // Transported by the authenticated WebSocket, not guest-supplied text.
      removeServerEnded(id);
      return;
    }
    if (event['type'] != 'temporary_message') return;
    final raw = event['data'];
    if (raw is! Map) return;
    final data = Map<String, dynamic>.from(raw);
    final id = data['sessionId']?.toString() ?? '';
    final r = find(id);
    if (r == null || !TemporaryChatUiGuard.acceptsMessage(
      sessionId: r.sessionId, role: r.role, data: data,
    )) return;
    final mid = data['messageId']?.toString() ?? '';
    if (mid.isEmpty || !r.seenMessageIds.add(mid)) return;
    if (r.seenMessageIds.length > 500) r.seenMessageIds.remove(r.seenMessageIds.first);
    final text = data['text'] as String;
    final control = TemporaryTrustMessage.parse(text);
    if (control == null) {
      _append(r, TemporaryChatLine(text: text, outgoing: false));
    } else if (control.kind == TemporaryTrustKind.request) {
      r.profileRequested = true;
      system(id, 'Собеседник просит показать профиль');
    } else if (control.kind == TemporaryTrustKind.decline) {
      r.profileWaiting = false;
      system(id, 'Собеседник предпочёл остаться анонимным');
    } else if (control.kind == TemporaryTrustKind.reveal) {
      r.peerUsername = control.username;
      r.profileWaiting = false;
      system(id, 'Собеседник добровольно показал имя профиля');
    }
  }

  /// Hides an expired or explicitly ended session in the UI.
  /// This is not a server revoke: no local UI action can pretend to revoke access.
  void hideExpired(String id) {
    final r = find(id);
    if (r == null || r.expiresAt.isAfter(DateTime.now())) return;
    _records.remove(id);
    _deleteHistory(id, r.role);
    notifyListeners();
  }
}

class TemporaryChatRecord {
  TemporaryChatRecord(this.sessionId, this.role, this.expiresAt);
  final String sessionId;
  final String role;
  DateTime expiresAt;
  DateTime lastActivity = DateTime.now();
  final List<TemporaryChatLine> messages = [];
  final Set<String> seenMessageIds = {};
  int unread = 0;
  bool viewing = false;
  bool profileRequested = false;
  bool profileWaiting = false;
  bool myProfileShared = false;
  String? peerUsername;
}

class TemporaryChatLine {
  const TemporaryChatLine({required this.text, required this.outgoing,
      this.system = false, this.timestamp});
  final String text;
  final bool outgoing;
  final bool system;
  final DateTime? timestamp;
}
