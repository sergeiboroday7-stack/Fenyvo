import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../services/socket_service.dart';
import '../services/storage_service.dart';
import '../services/incoming_share_service.dart';
import '../services/temporary_chat_hub.dart';
import '../services/temporary_recovery_store.dart';
import '../services/temporary_trust_l10n.dart';
import '../services/app_language_service.dart';
import '../services/temporary_invite_link.dart';
import 'temporary_chat_screen.dart';
import 'chat_screen.dart';
import 'temporary_chat_ui_guard.dart';
import 'temporary_trust_end_navigation.dart';

/// Restored temporary contact entry point. It never routes messages into
/// permanent chats, and accepts only decrypted messages for its active session.
class TemporaryContactScreen extends StatefulWidget {
  const TemporaryContactScreen({super.key, this.initialToken});

  /// Pre-fills an invitation; opening a link never joins without confirmation.
  final String? initialToken;

  @override
  State<TemporaryContactScreen> createState() => _TemporaryContactScreenState();
}

class _TemporaryContactScreenState extends State<TemporaryContactScreen> {
  final _tokenController = TextEditingController();

  late final String? _owner;
  late final String? _accountId;
  late final int _generation;

  String? _sessionId;
  String? _role;
  String? _createdSessionId;
  String? _createdInviteUrl;
  String _status = '';
  bool _busy = false;
  bool _creating = false;
  bool _awaitingJoin = false;
  bool _linkCreated = false;
  bool _closed = false;
  bool _createTab = true;
  bool _openingChat = false;
  bool _navigatingAfterEnd = false;
  bool _restoringGuest = false;
  bool _restoringOnOpen = false;
  String? _recoveryExpectedSessionId;
  String? _pendingApprovalRequestId;
  String? _approvingRequestId;

  final TemporaryRecoveryStore _recoveryStore = TemporaryRecoveryStore();

  final _durationValueController = TextEditingController(text: '1');
  int _durationUnitMinutes = 60;
  int _durationMinutes = 60;

  int? get _selectedDurationMinutes {
    final raw = _durationValueController.text.trim();
    if (!RegExp(r'^[0-9]{1,5}$').hasMatch(raw)) return null;
    final value = int.tryParse(raw);
    if (value == null || value < 1) return null;
    final minutes = value * _durationUnitMinutes;
    return minutes <= 43200 ? minutes : null;
  }
  Timer? _joinTimeout;

  bool get _live {
    final socket = SocketService.instance;
    return !_closed &&
        TemporaryChatUiGuard.live(
          authenticated: socket.isAuthenticated,
          expectedOwner: _owner,
          activeOwner: socket.currentUser,
          expectedAccountId: _accountId,
          activeAccountId: socket.currentAccountId,
          expectedGeneration: _generation,
          activeGeneration: socket.deviceTransferSessionGeneration,
        );
  }

  @override
  void initState() {
    super.initState();
    AppLanguageService.instance.code.addListener(_languageChanged);
    final socket = SocketService.instance;
    _owner = socket.currentUser;
    _accountId = socket.currentAccountId;
    _generation = socket.deviceTransferSessionGeneration;
    TemporaryChatHub.instance.attach();
    socket.addMessageHandler(_handleMessage);
    socket.connectionPhase.addListener(_connectionChanged);
    // Recover a missed request when the owner returns to this screen.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _live) {
        SocketService.instance.requestPendingTemporaryJoins();
        unawaited(_restoreConfirmedOnOpen());
      }
    });
    if (!_live) {
      _closed = true;
      _status = 'Для временного контакта требуется активный вход в аккаунт';
    } else if (widget.initialToken != null) {
      _createTab = false;
      final token = TemporaryInviteLink.tokenFromText(widget.initialToken!);
      if (token != null) {
        _tokenController.text = TemporaryInviteLink.urlForToken(token);
        _status = 'Приглашение получено. Нажмите «Подключиться».';
      }
    }
  }

  void _invalidate() {
    if (!mounted || _closed) return;
    _joinTimeout?.cancel();
    setState(() {
      _closed = true;
      _busy = false;
      _creating = false;
      _awaitingJoin = false;
      _restoringGuest = false;
      _recoveryExpectedSessionId = null;
      _linkCreated = false;
      _approvingRequestId = null;
      _pendingApprovalRequestId = null;
      _sessionId = null;
      _role = null;
      _createdSessionId = null;
      _createdInviteUrl = null;
      _tokenController.clear();
      _status = 'Соединение или аккаунт изменились. Откройте экран заново.';
    });
  }

  void _connectionChanged() {
    if (mounted && !_live) _invalidate();
  }

  void _languageChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    AppLanguageService.instance.code.removeListener(_languageChanged);
    _joinTimeout?.cancel();
    SocketService.instance.connectionPhase.removeListener(_connectionChanged);
    SocketService.instance.removeMessageHandler(_handleMessage);
    _tokenController.dispose();
    _durationValueController.dispose();
    super.dispose();
  }

  void _handleMessage(Map<String, dynamic> message) {
    if (!mounted || _closed) return;
    final type = message['type']?.toString() ?? '';
    if (type == 'disconnected' || type == 'login_success') {
      _invalidate();
      return;
    }
    if (!_live) {
      _invalidate();
      return;
    }
    final raw = message['data'];
    if (raw is! Map) return;
    final data = Map<String, dynamic>.from(raw);

    if (type == 'temporary_contact_ended') {
      final id = data['sessionId']?.toString().trim().toLowerCase() ?? '';
      if (RegExp(r'^[a-f0-9]{48}$').hasMatch(id)) {
        TemporaryChatHub.instance.removeServerEnded(id);
        final account = _accountId;
        if (account != null) {
          unawaited(_recoveryStore.remove(account, id).catchError((_) {}));
        }
        if (ModalRoute.of(context)?.isCurrent == true &&
            !_navigatingAfterEnd) {
          _navigatingAfterEnd = true;
          TemporaryTrustEndNavigation.toChats(context, peerEnded: true);
        } else if (mounted) {
          setState(() => _status = 'Собеседник завершил временный чат');
        }
      }
      return;
    }

    if (type == 'temporary_contact_join_request') {
      _showPendingApproval(data);
      return;
    }

    if (type == 'temporary_contact_pending_list') {
      final requests = data['requests'];
      if (requests is List && requests.isNotEmpty) {
        for (final raw in requests) {
          if (raw is Map) {
            _showPendingApproval(Map<String, dynamic>.from(raw));
            break;
          }
        }
      }
      return;
    }

    if (type == 'temporary_contact_join_pending' && _restoringGuest) {
      // A previously approved session must never silently become a new join.
      _joinTimeout?.cancel();
      setState(() {
        _restoringGuest = false;
        _awaitingJoin = false;
        _recoveryExpectedSessionId = null;
        _busy = false;
        _status = 'Нужно новое подтверждение владельца';
      });
      return;
    }

    if (type == 'temporary_contact_join_pending' && _awaitingJoin) {
      _joinTimeout?.cancel();
      _joinTimeout = Timer(const Duration(seconds: 100), () {
        if (!mounted || !_awaitingJoin) return;
        if (!_live) {
          _invalidate();
          return;
        }
        setState(() {
          _awaitingJoin = false;
          _busy = false;
          _status = 'Подтверждение владельца не получено. Попробуйте снова.';
        });
      });
      setState(() => _status = 'Ожидаем подтверждения владельца...');
      return;
    }

    if (type == 'temporary_contact_join_decision_result') {
      if (data['success'] == false) {
        setState(() {
          _approvingRequestId = null;
          _status = data['reason']?.toString() ?? 'Не удалось подтвердить вход';
        });
      }
      // After a denial (or expired request), there may be another pending
      // invitation to show. Approval itself produces a joined event.
      SocketService.instance.requestPendingTemporaryJoins();
      return;
    }

    if (type == 'temporary_contact_joined') {
      if (data['success'] == false) {
        if (!_awaitingJoin && !_creating) return;
        _joinTimeout?.cancel();
        setState(() {
          _busy = false;
          _awaitingJoin = false;
          _restoringGuest = false;
          _recoveryExpectedSessionId = null;
          _status = data['reason']?.toString() ?? 'Ошибка подключения';
        });
        return;
      }
      final sessionId =
          data['sessionId']?.toString().trim().toLowerCase() ?? '';
      final role = data['role']?.toString().trim().toLowerCase() ?? '';
      if (!TemporaryChatUiGuard.validSession(sessionId, role)) return;
      if (_restoringGuest &&
          (role != 'guest' || sessionId != _recoveryExpectedSessionId)) {
        return; // Never let a different session satisfy recovery.
      }
      if (role == 'owner' && _approvingRequestId != null &&
          data['requestId']?.toString() != _approvingRequestId) return;
      if (_sessionId != null && _sessionId != sessionId && !_awaitingJoin) {
        return;
      }
      if (!_awaitingJoin &&
          !_creating &&
          !_linkCreated &&
          _approvingRequestId == null &&
          _sessionId != sessionId) {
        return;
      }
      if (_createdSessionId != null &&
          !_awaitingJoin &&
          sessionId != _createdSessionId) {
        return;
      }
      final expiresAt = DateTime.tryParse(data['expiresAt']?.toString() ?? '');
      if (expiresAt == null || !expiresAt.isAfter(DateTime.now())) return;
      TemporaryChatHub.instance.register(
        sessionId: sessionId, role: role, expiresAt: expiresAt,
      );
      // Only this authenticated, server-confirmed event may persist recovery
      // metadata. A guest must have the original token; owners never store it.
      final recoveryAccount = _accountId;
      final recoveryGuestToken = role == 'guest'
          ? TemporaryInviteLink.tokenFromText(_tokenController.text)
          : null;
      if (recoveryAccount != null && recoveryAccount.isNotEmpty &&
          (role == 'owner' || recoveryGuestToken != null)) {
        unawaited(_saveConfirmedRecovery(
          accountId: recoveryAccount,
          sessionId: sessionId,
          role: role,
          expiresAt: expiresAt,
          guestToken: recoveryGuestToken,
        ));
      }
      _joinTimeout?.cancel();
      setState(() {
        _sessionId = sessionId;
        _role = role;
        _busy = false;
        _awaitingJoin = false;
        _restoringGuest = false;
        _recoveryExpectedSessionId = null;
        _approvingRequestId = null;
        _status = 'Временный контакт подключён';
      });
      // The entry screen must never compete with the single E2EE chat.
      _openChat();
      return;
    }

    // Decrypted temporary messages are rendered only by TemporaryChatScreen.
  }

  /// Save only after a server-confirmed join. The saved record is NOT a
  /// permission to display or send messages after process restart: the server
  /// must re-authorize the session on a fresh authenticated connection.
  Future<void> _saveConfirmedRecovery({
    required String accountId,
    required String sessionId,
    required String role,
    required DateTime expiresAt,
    String? guestToken,
  }) async {
    try {
      final entry = TemporaryRecoveryEntry(
        sessionId: sessionId,
        role: role,
        expiresAt: expiresAt,
        invitationToken: role == 'guest' ? guestToken : null,
      );
      if (!entry.validAt(DateTime.now().toUtc())) return;
      await _recoveryStore.upsert(accountId, entry);
    } catch (_) {
      // Storage errors must never downgrade server approval or E2EE rules.
      // This device simply will not have a recoverable local entry.
    }
  }

  /// Owner recovery requires BOTH previously stored local account metadata
  /// and a fresh server listing, followed by a successful Signal bundle
  /// publication on this authenticated socket. No invitation tokens are read.
  Future<void> _restoreConfirmedOnOpen() async {
    final account = _accountId;
    if (!_live || account == null || _busy || _restoringOnOpen) return;
    _restoringOnOpen = true;
    try {
      final local = await _recoveryStore.read(account).catchError(
        (_) => <TemporaryRecoveryEntry>[],
      );
      if (!mounted || !_live || _accountId != account || _busy) return;
      final server = await SocketService.instance.fetchConfirmedTemporarySessions();
      if (!mounted || !_live || _accountId != account || _busy ||
          server == null) return; // Never restore on a legacy/unknown server.
      final owners = TemporaryRecoveryCodec.confirmedOwners(
        local, server, DateTime.now().toUtc(),
      );
      for (final owner in owners) {
        if (!mounted || !_live || _accountId != account || _busy) return;
        if (TemporaryChatHub.instance.find(owner.sessionId) != null) continue;
        final activated = await SocketService.instance
            .activateConfirmedTemporaryOwner(owner.sessionId);
        if (!mounted || !_live || _accountId != account || _busy) return;
        if (activated) {
          TemporaryChatHub.instance.register(
            sessionId: owner.sessionId,
            role: 'owner',
            expiresAt: owner.expiresAt,
          );
        }
      }
      // Do not skip guest recovery when an unrelated owner chat is active.
      await _restorePreviouslyApprovedGuest(local: local, server: server);
    } finally {
      _restoringOnOpen = false;
    }
  }

  /// A stored invitation token alone is not authorization. Both the local
  /// secure metadata and a fresh authenticated server list must match.
  /// Before rejoining, require the original local Signal identity and ratchet.
  Future<void> _restorePreviouslyApprovedGuest({
    required List<TemporaryRecoveryEntry> local,
    required List<Map<String, dynamic>> server,
  }) async {
    final account = _accountId;
    if (!_live || _busy || _restoringGuest || account == null) return;
    final activeIds = TemporaryChatHub.instance.active
        .map((record) => record.sessionId).toSet();
    final candidate = TemporaryRecoveryCodec.confirmedGuest(
      local, server, activeIds, DateTime.now().toUtc(),
    );
    if (candidate == null) return;
    final token = candidate.invitationToken!;
    final hasSignal = await SocketService.instance
        .hasPersistedTemporaryGuestRecoveryState(candidate.sessionId);
    if (!mounted || !_live || _accountId != account || _busy) return;
    if (!hasSignal) {
      setState(() => _status =
          'Прежние ключи защищённого чата недоступны. Восстановление остановлено.');
      return;
    }
    setState(() {
      _restoringGuest = true;
      _awaitingJoin = true;
      _busy = true;
      _createTab = false;
      _recoveryExpectedSessionId = candidate.sessionId;
      _tokenController.text = TemporaryInviteLink.urlForToken(token);
      _status = 'Проверяем прежний временный чат на сервере...';
    });
    final sent = await SocketService.instance.joinTemporaryContactSecurely(token);
    if (!mounted || !_restoringGuest) return;
    if (!_live || !sent) {
      setState(() {
        _restoringGuest = false;
        _awaitingJoin = false;
        _recoveryExpectedSessionId = null;
        _busy = false;
        _status = 'Восстановление не подтверждено сервером';
      });
      return;
    }
    _joinTimeout?.cancel();
    _joinTimeout = Timer(const Duration(seconds: 12), () {
      if (!mounted || !_restoringGuest) return;
      setState(() {
        _restoringGuest = false;
        _awaitingJoin = false;
        _recoveryExpectedSessionId = null;
        _busy = false;
        _status = 'Сервер не подтвердил восстановление чата';
      });
    });
  }

  void _showPendingApproval(Map<String, dynamic> data) {
    if (!_live || !mounted) return;
    final requestId = data['requestId']?.toString().trim() ?? '';
    final token = data['token']?.toString().trim() ?? '';
    final expiresAt = DateTime.tryParse(data['expiresAt']?.toString() ?? '');
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(requestId) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(token) ||
        expiresAt == null ||
        !expiresAt.isAfter(DateTime.now())) return;
    // The server has already bound this request to the authenticated owner.
    // The creator screen may have been closed since the link was shared.
    setState(() {
      _createTab = true;
      _pendingApprovalRequestId = requestId;
      _status = 'Новый собеседник ожидает разрешения на вход';
    });
  }

  Future<void> _create() async {
    if (!_live || _busy) return;
    if (_restoringGuest) return;
    final chosenDuration = _selectedDurationMinutes;
    if (chosenDuration == null) {
      setState(() => _status = 'Укажите целый срок от 1 минуты до 30 дней');
      return;
    }
    _durationMinutes = chosenDuration;
    final requestedAt = DateTime.now().toUtc();
    setState(() {
      _busy = true;
      _creating = true;
      _sessionId = null;
      _role = null;
      _createdSessionId = null;
      _createdInviteUrl = null;
      _linkCreated = false;
      _approvingRequestId = null;
      _pendingApprovalRequestId = null;
      _status = '';
    });
    final result = await SocketService.instance.createTemporaryContact(
      durationMinutes: _durationMinutes,
      allowMessages: true,
      allowCalls: false,
      allowFiles: false,
    );
    if (!mounted) return;
    if (!_live) {
      _invalidate();
      return;
    }
    if (result == null || result['success'] != true) {
      setState(() {
        _busy = false;
        _creating = false;
        _status =
            result?['reason']?.toString() ??
            'Не удалось создать временный контакт';
      });
      return;
    }
    // Old production silently changes unsupported durations to one hour.
    // Never present such a link as if it had the user-selected expiry.
    final confirmedExpiry = DateTime.tryParse(
      result['expiresAt']?.toString() ?? '',
    )?.toUtc();
    final minimum = requestedAt.add(Duration(minutes: chosenDuration))
        .subtract(const Duration(seconds: 10));
    final maximum = DateTime.now().toUtc()
        .add(Duration(minutes: chosenDuration))
        .add(const Duration(seconds: 10));
    if (confirmedExpiry == null || confirmedExpiry.isBefore(minimum) ||
        confirmedExpiry.isAfter(maximum)) {
      setState(() {
        _busy = false;
        _creating = false;
        _status = 'Сервер не подтвердил выбранный срок. '
            'Ссылка не показана; не отправляйте её. '
            'Требуется обновление сервера Trust.';
      });
      return;
    }
    final link = result['link']?.toString().trim() ?? '';
    final token = result['token']?.toString().trim() ?? '';
    final inviteToken =
        TemporaryInviteLink.tokenFromText(link) ??
        TemporaryInviteLink.tokenFromText(token);
    if (inviteToken == null) {
      setState(() {
        _busy = false;
        _creating = false;
        _status = 'Сервер вернул некорректную временную ссылку';
      });
      return;
    }
    final createdId =
        result['sessionId']?.toString().trim().toLowerCase() ?? '';
    setState(() {
      _busy = false;
      _creating = false;
      _linkCreated = true;
      _createdInviteUrl = TemporaryInviteLink.urlForToken(inviteToken);
      _createdSessionId = TemporaryChatUiGuard.validSession(createdId, 'owner')
          ? createdId
          : null;
      _status = 'Временная ссылка создана';
    });
  }

  void _decideJoin(bool approved) {
    final requestId = _pendingApprovalRequestId;
    if (requestId == null || !_live || _busy) return;
    final sent = SocketService.instance.decideTemporaryContactJoin(
      requestId,
      approved,
    );
    if (!sent) {
      setState(() => _status = 'Не удалось отправить решение');
      return;
    }
    TemporaryChatHub.instance.clearPending();
    setState(() {
      _pendingApprovalRequestId = null;
      _approvingRequestId = approved ? requestId : null;
      _status = approved
          ? 'Подтверждаем подключение...'
          : 'Запрос на подключение отклонён';
    });
  }

  Future<void> _join() async {
    if (!_live || _busy) return;
    final value = TemporaryInviteLink.tokenFromText(_tokenController.text);
    if (value == null) {
      setState(() => _status = 'Некорректная временная ссылка или токен');
      return;
    }
    setState(() {
      _busy = true;
      _awaitingJoin = true;
      _status = 'Подключение...';
    });
    final sent = await SocketService.instance.joinTemporaryContactSecurely(value);
    if (!mounted) return;
    if (!_live) {
      _invalidate();
      return;
    }
    if (!sent) {
      setState(() {
        _busy = false;
        _awaitingJoin = false;
        _status = 'Безопасное подключение недоступно. Проверьте версию сервера.';
      });
      return;
    }
    _joinTimeout?.cancel();
    _joinTimeout = Timer(const Duration(seconds: 12), () {
      if (!mounted || !_awaitingJoin) return;
      if (!_live) {
        _invalidate();
        return;
      }
      setState(() {
        _awaitingJoin = false;
        _busy = false;
        _status = 'Сервер не ответил на запрос подключения';
      });
    });
  }

  Future<void> _endConfirmedChat(String sessionId) async {
    if (!_live || _busy ||
        TemporaryChatHub.instance.find(sessionId) == null) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const TemporaryTrustText('Завершить чат?'),
        content: const TemporaryTrustText(
          'Доступ будет закрыт для обоих участников. '
          'Повторно войти по старой ссылке будет нельзя. '
          'Это не то же самое, что свернуть чат.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const TemporaryTrustText('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const TemporaryTrustText('Завершить для обоих'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted || !_live || _busy ||
        TemporaryChatHub.instance.find(sessionId) == null) return;
    setState(() {
      _busy = true;
      _status = 'Запрашиваем завершение чата на сервере...';
    });
    final ended = await SocketService.instance.endConfirmedTemporarySession(sessionId);
    if (!mounted) return;
    if (!_live) { _invalidate(); return; }
    if (ended) {
      TemporaryChatHub.instance.removeServerEnded(sessionId);
      final account = _accountId;
      if (account != null) {
        try { await _recoveryStore.remove(account, sessionId); } catch (_) {}
      }
    }
    if (!mounted) return;
    if (ended) {
      if (!_navigatingAfterEnd) {
        _navigatingAfterEnd = true;
        TemporaryTrustEndNavigation.toChats(context, peerEnded: false);
      }
      return;
    }
    setState(() {
      _busy = false;
      _status = 'Сервер не подтвердил завершение. Чат не закрыт.';
    });
  }

  Future<void> _copyInvite() async {
    final link = _createdInviteUrl;
    if (!_live || _busy || link == null) return;
    await Clipboard.setData(ClipboardData(text: link));
    if (!mounted) return;
    if (!_live) {
      _invalidate();
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: TemporaryTrustText('Временная ссылка скопирована')),
    );
  }

  Future<void> _shareInvite() async {
    final link = _createdInviteUrl;
    if (!_live || _busy || link == null) return;
    try {
      await SharePlus.instance.share(
        ShareParams(
          title: TemporaryTrustL10n.text('FENYVO — временный контакт'),
          text: '${TemporaryTrustL10n.text('Приглашение во временный защищённый чат FENYVO:')}\n$link',
        ),
      );
    } catch (_) {
      if (mounted && _live) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: TemporaryTrustText('Не удалось открыть меню отправки')),
        );
      }
    }
  }

  Future<void> _shareInviteToFenyvo() async {
    final link = _createdInviteUrl;
    final owner = _owner;
    final accountId = _accountId;
    if (!Platform.isWindows || !_live || _busy || link == null ||
        owner == null || accountId == null) return;

    final contacts = StorageService.getChatUsers(owner)
        .where((user) => user.isNotEmpty && user != owner &&
            !user.startsWith('group::'))
        .toSet()
        .toList()
      ..sort();

    final target = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Отправить приглашение контакту FENYVO'),
        content: SizedBox(
          width: 420,
          child: contacts.isEmpty
              ? const Text('Нет доступных личных чатов. Сначала добавьте контакт.')
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: contacts.length,
                    itemBuilder: (_, index) => ListTile(
                      leading: const Icon(Icons.person_outline),
                      title: Text(contacts[index]),
                      onTap: () => Navigator.of(dialogContext).pop(contacts[index]),
                    ),
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
    if (!mounted || !_live || target == null ||
        _owner != owner || _accountId != accountId ||
        _createdInviteUrl != link) return;

    // Reuse the ordinary chat composer and E2EE send pipeline. The user
    // confirms the recipient, then presses Send; only then return to ENIGMA.
    // Do not bypass E2EE or claim that remote delivery was confirmed.
    await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ChatScreen(
          targetUser: target,
          initialShare: IncomingSharePayload(
            text: '${TemporaryTrustL10n.text('Приглашение во временный защищённый чат FENYVO:')}\n$link',
            images: const <IncomingShareImage>[],
          ),
          returnToTrustAfterShare: true,
        ),
      ),
    );
  }

  void _showInviteQr() {
    final link = _createdInviteUrl;
    if (!_live || _busy || link == null) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const TemporaryTrustText('QR-код приглашения'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TemporaryTrustText('Покажите код только тому, кого хотите пригласить.'),
            const SizedBox(height: 16),
            ColoredBox(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: QrImageView(
                  data: link,
                  version: QrVersions.auto,
                  size: 224,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const TemporaryTrustText('Закрыть'),
          ),
        ],
      ),
    );
  }

  void _openChat() {
    final sessionId = _sessionId;
    final role = _role;
    if (!_live || _openingChat || sessionId == null || role == null) return;
    _openingChat = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_live) {
        _openingChat = false;
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TemporaryChatScreen(sessionId: sessionId, role: role),
        ),
      ).then((_) {
        if (mounted) _openingChat = false;
      });
    });
  }

  Future<void> _showEnigmaDurationPicker() async {
    if (!_live || _busy) return;
    const gold = Color(0xFFD8B36C);
    const navy = Color(0xFF0D1929);
    const panel = Color(0xFF162539);
    int unit = _durationUnitMinutes;
    int amount = int.tryParse(_durationValueController.text) ?? 1;
    if (unit != 1 && unit != 60 && unit != 1440 && unit != 43200) {
      unit = 1;
    }
    amount = amount.clamp(1, 43200 ~/ unit).toInt();
    final selected = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, update) {
          final total = amount * unit;
          void choose(int minutes) => update(() {
                unit = 1;
                amount = minutes;
              });
          return SafeArea(
            top: false,
            child: Container(
              padding: EdgeInsets.fromLTRB(
                22, 14, 22, 22 + MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              decoration: BoxDecoration(
                color: panel,
                border: Border.all(color: gold.withValues(alpha: .6)),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(width: 50, height: 5,
                      decoration: BoxDecoration(color: Colors.white30,
                        borderRadius: BorderRadius.circular(10)))),
                    const SizedBox(height: 20),
                    const Row(children: [
                      Icon(Icons.calendar_month_outlined, color: gold),
                      SizedBox(width: 12),
                      Text('Свій термін дії', style: TextStyle(color: Colors.white,
                        fontSize: 22, fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 8),
                    const Text('Вкажіть власний термін дії запрошення. Максимум — 30 днів.',
                      style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 18),
                    Container(
                      decoration: BoxDecoration(
                        color: navy, borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: gold.withValues(alpha: .45)),
                      ),
                      child: Row(children: [
                        IconButton(
                          tooltip: 'Зменшити',
                          onPressed: amount > 1 ? () => update(() => amount--) : null,
                          icon: const Icon(Icons.remove_circle_outline, color: gold),
                        ),
                        Expanded(child: Text('$amount', textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white,
                            fontSize: 32, fontWeight: FontWeight.bold))),
                        IconButton(
                          tooltip: 'Збільшити',
                          onPressed: amount * unit < 43200
                              ? () => update(() => amount++) : null,
                          icon: const Icon(Icons.add_circle_outline, color: gold),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 12),
                    Wrap(spacing: 7, runSpacing: 7, children: [
                      for (final entry in const <int, String>{
                        60: 'година', 1440: 'день', 43200: 'місяць',
                      }.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: unit == entry.key,
                          selectedColor: gold,
                          backgroundColor: navy,
                          side: const BorderSide(color: gold),
                          labelStyle: TextStyle(color: unit == entry.key
                              ? navy : Colors.white),
                          onSelected: (_) => update(() {
                            unit = entry.key;
                            amount = amount.clamp(1, 43200 ~/ unit).toInt();
                          }),
                        ),
                    ]),
                    const SizedBox(height: 16),
                    const Text('Швидкі варіанти', style: TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 7, runSpacing: 7, children: [
                      for (final entry in const <int, String>{
                        15: '15 хв', 60: '1 година', 1440: '1 день',
                        10080: '7 днів', 43200: '30 днів',
                      }.entries)
                        ChoiceChip(
                          label: Text(entry.value),
                          selected: total == entry.key,
                          selectedColor: gold,
                          backgroundColor: navy,
                          side: const BorderSide(color: gold),
                          labelStyle: TextStyle(color: total == entry.key
                              ? navy : Colors.white),
                          onSelected: (_) => choose(entry.key),
                        ),
                    ]),
                    const SizedBox(height: 20),
                    Row(children: [
                      Expanded(child: OutlinedButton(
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: gold)),
                        child: const Text('Скасувати', style: TextStyle(color: Colors.white)),
                      )),
                      const SizedBox(width: 12),
                      Expanded(child: FilledButton(
                        onPressed: () => Navigator.of(sheetContext).pop(total),
                        style: FilledButton.styleFrom(
                          backgroundColor: gold, foregroundColor: navy),
                        child: const Text('Застосувати'),
                      )),
                    ]),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
    if (!mounted || !_live || _busy || selected == null) return;
    if (selected < 1 || selected > 43200) return;
    setState(() {
      _durationUnitMinutes = 1;
      _durationValueController.text = selected.toString();
    });
  }
  Widget _informationCard({required IconData icon, required String message}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF162539),
        border: Border.all(
          color: const Color(0xFFB59357).withValues(alpha: .6),
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFD8B36C)),
          const SizedBox(width: 12),
          Expanded(
            child: TemporaryTrustText(message, style: const TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD8B36C);
    return Scaffold(
      backgroundColor: const Color(0xFF0D1929),
      appBar: AppBar(title: const TemporaryTrustText('FENYVO ENIGMA', style: TextStyle(color: Color(0xFFD8B36C), fontWeight: FontWeight.w800, letterSpacing: 1.1))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const SizedBox(height: 8),
            const Icon(Icons.shield_outlined, size: 60, color: gold),
            const SizedBox(height: 14),
            const TemporaryTrustText('FENYVO ENIGMA',
              textAlign: TextAlign.center,
              style: TextStyle(color: gold, fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: 1.4),
            ),
            const SizedBox(height: 10),
            const TemporaryTrustText('Защищённое пространство для анонимного общения',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 9),
            const TemporaryTrustText('Анонимно · Ограничено по времени · E2EE',
              textAlign: TextAlign.center,
              style: TextStyle(color: gold, fontSize: 12),
            ),
            const SizedBox(height: 20),
            AnimatedBuilder(
              animation: TemporaryChatHub.instance,
              builder: (context, _) {
                final sessions = TemporaryChatHub.instance.active;
                final unread = TemporaryChatHub.instance.unreadCount;
                final pending = TemporaryChatHub.instance.pendingCount;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const Icon(Icons.forum_outlined, color: gold),
                      const SizedBox(width: 8),
                      Expanded(child: TemporaryTrustText(
                        'Активные чаты: ${sessions.length}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                      )),
                      if (unread > 0 || pending > 0) TemporaryTrustText(
                        pending > 0 ? 'Ожидают: $pending' : 'Непрочитанных: $unread',
                        style: const TextStyle(color: gold, fontSize: 12),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    for (final item in sessions) Card(
                      color: const Color(0xFF162539),
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFFB59357), width: 1)),
                      child: ListTile(
                        leading: Image.asset('assets/images/fenyvo_enigma_hood.png', width: 58, height: 58, fit: BoxFit.contain),
                        title: TemporaryTrustText(item.peerUsername == null
                          ? 'Анонимный собеседник'
                          : '@${item.peerUsername}',
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: TemporaryTrustText(
                          'E2EE · до ${TimeOfDay.fromDateTime(item.expiresAt.toLocal()).format(context)}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (item.unread > 0) CircleAvatar(
                              radius: 13, backgroundColor: gold,
                              child: TemporaryTrustText('${item.unread}',
                                style: const TextStyle(color: Colors.black, fontSize: 11)),
                            ),
                            IconButton(
                              tooltip: 'Завершить чат для обоих',
                              icon: const Icon(Icons.close_rounded, color: gold),
                              onPressed: _live && !_busy
                                  ? () => _endConfirmedChat(item.sessionId)
                                  : null,
                            ),
                          ],
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(builder: (_) => TemporaryChatScreen(
                            sessionId: item.sessionId, role: item.role)),
                        ),
                      ),
                    ),
                    if (sessions.isEmpty) const TemporaryTrustText(
                      'Здесь будут ваши действующие временные чаты. Выход из экрана их не завершает.',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: true,
                  label: TemporaryTrustText('Создать ссылку'),
                  icon: Icon(Icons.add_link_rounded),
                ),
                ButtonSegment<bool>(
                  value: false,
                  label: TemporaryTrustText('Войти по ссылке'),
                  icon: Icon(Icons.login_rounded),
                ),
              ],
              selected: {_createTab},
              showSelectedIcon: false,
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.selected) ? const Color(0xFFD8B36C) : const Color(0xFF162539)),
                foregroundColor: WidgetStateProperty.resolveWith<Color?>((states) => states.contains(WidgetState.selected) ? const Color(0xFF0D1929) : Colors.white),
                side: const WidgetStatePropertyAll(BorderSide(color: Color(0xFFB59357))),
                shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                padding: WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 8),
                ),
                textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
              ),
              onSelectionChanged: _busy || !_live
                  ? null
                  : (selected) => setState(() {
                      _createTab = selected.first;
                      _status = '';
                    }),
            ),
            const SizedBox(height: 20),
            if (_createTab) ...[
              _informationCard(
                icon: Icons.visibility_off_rounded,
                message: 'Ваш основной профиль не показывается по этой ссылке.',
              ),
              const SizedBox(height: 18),
              const Text('Термін дії', style: TextStyle(color: gold, fontSize: 15, fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in const <int, String>{
                    15: '15 хв',
                    60: '1 година',
                    1440: '1 день',
                    10080: '7 днів',
                    43200: '30 днів',
                  }.entries)
                    ChoiceChip(
                      label: Text(preset.value),
                      selected: _selectedDurationMinutes == preset.key,
                      selectedColor: gold,
                      backgroundColor: const Color(0xFF162539),
                      side: const BorderSide(color: Color(0xFFB59357)),
                      labelStyle: TextStyle(
                        color: _selectedDurationMinutes == preset.key
                            ? const Color(0xFF0D1929)
                            : Colors.white,
                      ),
                      onSelected: !_live || _busy
                          ? null
                          : (selected) {
                              if (!selected) return;
                              setState(() {
                                _durationUnitMinutes = 1;
                                _durationValueController.text = preset.key.toString();
                              });
                            },
                    ),
                ],
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: _live && !_busy ? _showEnigmaDurationPicker : null,
                icon: const Icon(Icons.tune_rounded, color: Color(0xFFD8B36C)),
                label: const Text('Свій варіант', style: TextStyle(color: Colors.white)),
                style: OutlinedButton.styleFrom(
                  alignment: Alignment.centerLeft,
                  side: const BorderSide(color: Color(0xFFB59357)),
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                ),
              ),
              if (_selectedDurationMinutes == null)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Разрешено от 1 минуты до 30 дней',
                      style: TextStyle(color: Color(0xFFFFC187))),
                ),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFFD8B36C), foregroundColor: const Color(0xFF0D1929), minimumSize: const Size.fromHeight(54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                onPressed: _live && !_busy && _selectedDurationMinutes != null ? _create : null,
                icon: const Icon(Icons.link_rounded),
                label: TemporaryTrustText(
                  _busy && _creating ? 'Создаём...' : 'Создать приглашение',
                ),
              ),
              if (_pendingApprovalRequestId != null && _live) ...[
                const SizedBox(height: 16),
                _informationCard(
                  icon: Icons.person_add_alt_1_rounded,
                  message:
                      'Новый собеседник хочет войти в этот чат. Разрешить?',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _busy ? null : () => _decideJoin(true),
                  icon: const Icon(Icons.check_rounded),
                  label: const TemporaryTrustText('Разрешить вход'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _decideJoin(false),
                  icon: const Icon(Icons.close_rounded),
                  label: const TemporaryTrustText('Отклонить'),
                ),
              ],
              if (_createdInviteUrl != null && _live) ...[
                const SizedBox(height: 22),
                _informationCard(
                  icon: Icons.check_circle_outline_rounded,
                  message: 'Ссылка готова. Отправьте её человеку и дождитесь подключения.',
                ),
                const SizedBox(height: 12),
                SelectableText(
                  _createdInviteUrl!,
                  style: const TextStyle(color: gold, fontSize: 13),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _copyInvite,
                      icon: const Icon(Icons.copy_rounded),
                      label: const TemporaryTrustText('Копировать'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _shareInvite,
                      icon: const Icon(Icons.share_rounded),
                      label: const TemporaryTrustText('Поделиться'),
                    ),
                    if (Platform.isWindows)
                      OutlinedButton.icon(
                        onPressed: _busy ? null : _shareInviteToFenyvo,
                        icon: const Icon(Icons.people_alt_outlined),
                        label: const TemporaryTrustText('Контакту FENYVO'),
                      ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _showInviteQr,
                      icon: const Icon(Icons.qr_code_rounded),
                      label: const TemporaryTrustText('QR-код'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const TemporaryTrustText(
                  'Ссылка секретная. Любой, кому её перешлют, может попытаться подключиться, пока она действует.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ] else ...[
              _informationCard(
                icon: Icons.lock_outline_rounded,
                message: 'Откройте ссылку-приглашение или вставьте её сюда. Вход без вашего нажатия не происходит.',
              ),
              const SizedBox(height: 18),
              TextField(
                controller: _tokenController,
                enabled: _live && !_busy,
                autocorrect: false,
                enableSuggestions: false,
                maxLines: 2,
                minLines: 1,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: TemporaryTrustL10n.text('Ссылка-приглашение'),
                  hintText: 'https://fenyvo.com/t/...',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _live && !_busy ? _join : null,
                icon: const Icon(Icons.login_rounded),
                label: TemporaryTrustText(
                  _awaitingJoin ? 'Подключаемся...' : 'Начать защищённый чат',
                ),
              ),
            ],
            if (_status.isNotEmpty) ...[
              const SizedBox(height: 16),
              TemporaryTrustText(_status, style: const TextStyle(color: Colors.white70)),
            ],
            const SizedBox(height: 24),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.lock_rounded, size: 16, color: gold),
                SizedBox(width: 6),
                TemporaryTrustText(
                  'Защищённые сообщения • E2EE',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
