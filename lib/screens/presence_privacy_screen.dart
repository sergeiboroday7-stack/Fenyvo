import 'dart:async';

import 'package:flutter/material.dart';

import '../services/socket_service.dart';
import '../services/app_language_service.dart';

/// Server-controlled visibility preferences.
/// This screen never treats a local selection as a saved server preference.
class PresencePrivacyScreen extends StatefulWidget {
  const PresencePrivacyScreen({super.key});

  @override
  State<PresencePrivacyScreen> createState() => _PresencePrivacyScreenState();
}

class _PresencePrivacyScreenState extends State<PresencePrivacyScreen> {
  static const _modes = <String, String>{
    'all': 'presenceAll',
    'contacts': 'presenceContacts',
    'nobody': 'presenceNobody',
  };

  String _online = 'contacts';
  String _lastSeen = 'contacts';

  bool _loading = true;
  bool _saving = false;
  bool _loaded = false;
  String? _expectedSaveOnline;
  String? _expectedSaveLastSeen;
  String? _pendingRequestId;
  int _requestSequence = 0;

  String _nextRequestId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${++_requestSequence}';

  String? _notice;
  Timer? _requestTimeout;

  SocketService get _socket => SocketService.instance;

  String _t(String key) => AppLanguageService.instance.text(key);

  @override
  void initState() {
    super.initState();
    _socket.addMessageHandler(_handleServerMessage);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fetchSettings();
    });
  }

  void _fetchSettings() {
    if (!_socket.isAuthenticated) {
      setState(() {
        _loading = false;
        _loaded = false;
        _notice = 'presenceNeedConnection';
      });
      return;
    }

    setState(() {
      _loading = true;
      _loaded = false;
      _notice = null;
    });

    _pendingRequestId = _nextRequestId();
    _socket.getPresencePrivacy(requestId: _pendingRequestId);
    _startTimeout();
  }

  void _startTimeout() {
    _requestTimeout?.cancel();
    _requestTimeout = Timer(const Duration(seconds: 12), () {
      if (!mounted) return;
      setState(() {
        _pendingRequestId = null;
        _expectedSaveOnline = null;
        _expectedSaveLastSeen = null;
        _loading = false;
        _saving = false;
        _notice = 'presenceTimeout';
      });
    });
  }

  void _handleServerMessage(Map<String, dynamic> message) {
    if (!mounted) return;

    final type = message['type']?.toString() ?? '';

    if (type == 'disconnected') {
      _requestTimeout?.cancel();
      _pendingRequestId = null;
      _expectedSaveOnline = null;
      _expectedSaveLastSeen = null;
      setState(() {
        _loading = false;
        _saving = false;
        _loaded = false;
        _notice = 'presenceDisconnected';
      });
      return;
    }

    if (type == 'error' && _saving) {
      final rawError = message['data'];
      final reason = rawError is Map
          ? rawError['reason']?.toString() ?? ''
          : '';

      if (reason == 'Недопустимые настройки приватности' &&
          rawError is Map &&
          rawError['requestId'] == _pendingRequestId &&
          _pendingRequestId != null) {
        _requestTimeout?.cancel();
        _pendingRequestId = null;
        setState(() {
          _saving = false;
          _notice = 'presenceInvalid';
        });
        return;
      }
    }

    if (type != 'presence_privacy') return;

    final raw = message['data'];
    if (raw is! Map) return;

    if (_pendingRequestId == null || raw['requestId'] != _pendingRequestId) {
      return;
    }

    final online = raw['onlineVisibility'];
    final lastSeen = raw['lastSeenVisibility'];

    if (online is! String ||
        lastSeen is! String ||
        !_modes.containsKey(online) ||
        !_modes.containsKey(lastSeen)) {
      return;
    }

    // A delayed GET response must not acknowledge a different SAVE.
    if (!_loading && !_saving) return;
    if (_saving &&
        (online != _expectedSaveOnline || lastSeen != _expectedSaveLastSeen)) {
      return;
    }

    final wasSaving = _saving;

    _requestTimeout?.cancel();

    setState(() {
      _pendingRequestId = null;
      _expectedSaveOnline = null;
      _expectedSaveLastSeen = null;
      _online = online;
      _lastSeen = lastSeen;
      _loaded = true;
      _loading = false;
      _saving = false;
      _notice = wasSaving ? 'presenceSaved' : 'presenceLoaded';
    });
  }

  void _save() {
    if (!_loaded || _loading || _saving) return;

    if (!_socket.isAuthenticated) {
      setState(() {
        _notice = 'presenceNotAuthenticated';
      });
      return;
    }

    setState(() {
      _saving = true;
      _expectedSaveOnline = _online;
      _expectedSaveLastSeen = _lastSeen;
      _notice = 'presenceSaving';
    });

    _pendingRequestId = _nextRequestId();
    _socket.updatePresencePrivacy(
      onlineVisibility: _online,
      lastSeenVisibility: _lastSeen,
      requestId: _pendingRequestId,
    );

    _startTimeout();
  }

  Widget _visibilitySelector({
    required String title,
    required String description,
    required String value,
    required ValueChanged<String?> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        Text(description),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: ValueKey('$title:$value'),
          initialValue: value,
          isExpanded: true,
          decoration: const InputDecoration(border: OutlineInputBorder()),
          items: _modes.entries
              .map(
                (entry) => DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(_t(entry.value)),
                ),
              )
              .toList(),
          onChanged: !_loaded || _loading || _saving ? null : onChanged,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_t('presenceTitle'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(_t('presenceIntro')),
            const SizedBox(height: 24),
            _visibilitySelector(
              title: _t('presenceOnlineTitle'),
              description: _t('presenceOnlineDescription'),
              value: _online,
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _online = value;
                  _notice = null;
                });
              },
            ),
            const SizedBox(height: 28),
            _visibilitySelector(
              title: _t('presenceLastSeenTitle'),
              description: _t('presenceLastSeenDescription'),
              value: _lastSeen,
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _lastSeen = value;
                  _notice = null;
                });
              },
            ),
            const SizedBox(height: 24),
            Text(_t('presenceIndependentNotice')),
            const SizedBox(height: 16),
            if (_loading || _saving)
              const Center(child: CircularProgressIndicator()),
            if (_notice != null) ...[
              const SizedBox(height: 12),
              Text(_t(_notice!)),
            ],
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _loaded && !_loading && !_saving ? _save : null,
              child: Text(_t('presenceSave')),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: _loading || _saving ? null : _fetchSettings,
              child: Text(_t('presenceRefresh')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _requestTimeout?.cancel();
    _socket.removeMessageHandler(_handleServerMessage);
    super.dispose();
  }
}
