import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../services/socket_service.dart';
import '../services/temporary_chat_hub.dart';
import '../services/temporary_recovery_store.dart';
import '../services/temporary_trust_l10n.dart';
import '../services/app_language_service.dart';
import '../services/temporary_trust_message.dart';
import 'temporary_chat_ui_guard.dart';
import 'temporary_trust_end_navigation.dart';

/// One temporary E2EE conversation. Trust events remain ordinary encrypted
/// messages, never server-side metadata and never permanent contact requests.
class TemporaryChatScreen extends StatefulWidget {
  const TemporaryChatScreen({
    super.key,
    required this.sessionId,
    required this.role,
  });

  final String sessionId;
  final String role;

  @override
  State<TemporaryChatScreen> createState() => _TemporaryChatScreenState();
}

class _TemporaryChatScreenState extends State<TemporaryChatScreen> {
  static const _gold = Color(0xFFD8B36C);
  static const _surface = Color(0xFF162539);
  static const _background = Color(0xFF0D1929);

  final _messageController = TextEditingController();
  final _messageFocusNode = FocusNode();
  bool get _isWindows => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  final List<TemporaryChatLine> _messages = [];
  final _hub = TemporaryChatHub.instance;
  late final String? _owner;
  late final String? _accountId;
  late final int _generation;
  bool _closed = false;
  bool _sending = false;
  bool _endingChat = false;
  bool _serverEnded = false;
  bool _navigatingAfterEnd = false;
  bool _incomingProfileRequest = false;
  bool _waitingForProfile = false;
  bool _pausedUntilReply = false;
  bool _sharedMyProfile = false;
  String? _peerSharedUsername;
  String _status = 'Защищённое соединение';

  Timer? _enigmaCountdownTicker;

  String get _enigmaRemainingLabel {
    final record = _hub.find(widget.sessionId);
    if (record == null) return 'Срок недоступен';
    final remaining = record.expiresAt.difference(DateTime.now());
    if (remaining <= Duration.zero) return 'Срок истёк';
    final days = remaining.inDays;
    final hours = remaining.inHours.remainder(24);
    final minutes = remaining.inMinutes.remainder(60);
    final seconds = remaining.inSeconds.remainder(60);
    String two(int value) => value.toString().padLeft(2, '0');
    if (days > 0) return '$days д ${two(hours)}:${two(minutes)}:${two(seconds)}';
    return '${two(remaining.inHours)}:${two(minutes)}:${two(seconds)}';
  }
  bool get _live {
    final socket = SocketService.instance;
    return !_closed && !_serverEnded &&
        TemporaryChatUiGuard.validSession(widget.sessionId, widget.role) &&
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
    _hub.attach();
    _hub.viewing(widget.sessionId, true);
    _syncFromHub();
    _hub.addListener(_hubChanged);
    socket.addMessageHandler(_handleMessage);
    socket.connectionPhase.addListener(_connectionChanged);
    _enigmaCountdownTicker = Timer.periodic(
      const Duration(seconds: 1),
      (_) {
        if (mounted && _live) setState(() {});
      },
    );
    if (!_live) {
      _closed = true;
      _status = 'Нет действующей защищённой сессии';
    }
    if (_isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _live && !_pausedUntilReply) {
          _messageFocusNode.requestFocus();
        }
      });
    }
  }

  void _syncFromHub() {
    final record = _hub.find(widget.sessionId);
    if (record == null) return;
    _messages
      ..clear()
      ..addAll(record.messages);
    _peerSharedUsername = record.peerUsername;
    _incomingProfileRequest = record.profileRequested;
    _waitingForProfile = record.profileWaiting;
    if (!_waitingForProfile) _pausedUntilReply = false;
    _sharedMyProfile = record.myProfileShared;
  }

  void _hubChanged() {
    if (!mounted) return;
    if (_hub.find(widget.sessionId) == null && !_serverEnded && !_endingChat && !_navigatingAfterEnd) {
      setState(() {
        _serverEnded = true;
        _sending = false;
        _status = 'Временный чат больше не доступен';
      });
      return;
    }
    setState(_syncFromHub);
  }

  void _invalidate() {
    if (!mounted || _closed) return;
    setState(() {
      _closed = true;
      _sending = false;
      // Keep already displayed text until the screen is closed.
      // No plaintext is written to disk.
      _incomingProfileRequest = false;
      _peerSharedUsername = null;
      _sharedMyProfile = false;
      _waitingForProfile = false;
      _pausedUntilReply = false;
      _status = 'Соединение или аккаунт изменились. Откройте чат заново.';
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
    _hub.removeListener(_hubChanged);
    _hub.viewing(widget.sessionId, false);
    SocketService.instance.connectionPhase.removeListener(_connectionChanged);
    SocketService.instance.removeMessageHandler(_handleMessage);
    _enigmaCountdownTicker?.cancel();
    _messageFocusNode.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _handleMessage(Map<String, dynamic> message) {
    if (!mounted) return;
    final type = message['type']?.toString() ?? '';
    // An end notice remains terminal even when the local session was already
    // marked closed during a socket transition. Do not gate it on _live.
    if (type == 'temporary_contact_ended' &&
        message['data'] is Map &&
        (message['data'] as Map)['sessionId']?.toString().toLowerCase() ==
            widget.sessionId.toLowerCase() &&
        _accountId != null &&
        SocketService.instance.isAuthenticated &&
        SocketService.instance.currentAccountId == _accountId &&
        SocketService.instance.currentUser == _owner) {
      final account = _accountId;
      unawaited(
        TemporaryRecoveryStore()
            .remove(account, widget.sessionId)
            .catchError((_) {}),
      );
      _returnToChats(peerEnded: true);
      return;
    }
    if (_closed) return;
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

    if (type == 'temporary_message' &&
        TemporaryChatUiGuard.acceptsMessage(
          sessionId: widget.sessionId,
          role: widget.role,
          data: data,
        )) {
      // TemporaryChatHub receives the authenticated, decrypted event once.
      // It also keeps messages while this screen is not visible.
      return;
    } else if (type == 'temporary_message_error' &&
        data['sessionId'] == widget.sessionId) {
      setState(() {
        _status =
            data['reason']?.toString() ?? 'Не удалось расшифровать сообщение';
      });
    }
  }

  void _returnToChats({required bool peerEnded}) {
    if (!mounted || _navigatingAfterEnd) return;
    // A server-confirmed end is terminal. A Back gesture is never terminal.
    _navigatingAfterEnd = true;
    _serverEnded = true;
    TemporaryTrustEndNavigation.toChats(context, peerEnded: peerEnded);
  }

  Future<bool> _sendEncryptedText(
    String text, {
    bool showMessage = true,
  }) async {
    if (!_live || _sending || _endingChat || text.trim().isEmpty) return false;
    setState(() {
      _sending = true;
      _status = 'Шифрование и отправка...';
    });
    final sent = await SocketService.instance.sendTemporaryEncryptedMessage(
      sessionId: widget.sessionId,
      role: widget.role,
      text: text,
    );
    if (!mounted) return false;
    if (!_live) {
      _invalidate();
      return false;
    }
    setState(() {
      _sending = false;
      _status = sent ? 'Сообщение отправлено • E2EE' : 'Не удалось отправить';
    });
    if (sent && showMessage) _hub.outgoing(widget.sessionId, text);
    return sent;
  }

  Future<void> _endChat() async {
    if (!_live || _endingChat || _sending) return;
    final approve = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const TemporaryTrustText('Завершить чат?'),
        content: const TemporaryTrustText(
          'Чат закроется для обоих. Старая ссылка не даст войти снова. '
          'Для обычного выхода используйте «Свернуть чат».',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const TemporaryTrustText('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const TemporaryTrustText('Завершить для обоих'),
          ),
        ],
      ),
    );
    if (approve != true || !mounted || !_live || _endingChat) return;
    setState(() { _endingChat = true; _status = 'Подтверждаем завершение на сервере...'; });
    final ended = await SocketService.instance.endConfirmedTemporarySession(widget.sessionId);
    if (!mounted) return;
    if (ended) {
      _hub.removeServerEnded(widget.sessionId);
      final account = _accountId;
      if (account != null) {
        try { await TemporaryRecoveryStore().remove(account, widget.sessionId); } catch (_) {}
      }
    }
    if (ended) {
      _returnToChats(peerEnded: false);
      return;
    }
    setState(() {
      _endingChat = false;
      if (ended) _serverEnded = true;
      _status = ended
          ? 'Чат завершён для обоих участников'
          : 'Сервер не подтвердил завершение. Чат остаётся открытым.';
    });
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (_pausedUntilReply || text.isEmpty) return;
    final sent = await _sendEncryptedText(text);
    if (sent && mounted && _messageController.text.trim() == text) {
      _messageController.clear();
      if (_isWindows && _live && !_pausedUntilReply) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _live && !_sending && !_pausedUntilReply) {
            _messageFocusNode.requestFocus();
          }
        });
      }
    }
  }

  void _submitWithEnter() {
    if (!_isWindows || !_live || _sending || _endingChat ||
        _pausedUntilReply || _messageController.text.trim().isEmpty) {
      return;
    }
    unawaited(_send());
  }

  Future<void> _askForProfile() async {
    if (!_live || _sending) return;
    bool pause = false;
    final requested = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.shield_outlined, color: _gold, size: 46),
                const SizedBox(height: 12),
                const TemporaryTrustText(
                  'Запросить профиль',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const TemporaryTrustText(
                  'Собеседник сам решит, хочет ли показать свой профиль. Отказ не раскрывает никаких данных.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                CheckboxListTile(
                  value: pause,
                  title: const TemporaryTrustText('Приостановить мои сообщения до ответа'),
                  subtitle: const TemporaryTrustText(
                    'Вы сможете возобновить общение в любой момент',
                  ),
                  onChanged: (value) =>
                      setSheetState(() => pause = value ?? false),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: const TemporaryTrustText('Отправить запрос'),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(sheetContext, false),
                  child: const TemporaryTrustText('Отмена'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (!mounted || requested != true || !_live) return;
    final sent = await _sendEncryptedText(
      TemporaryTrustMessage.requestText,
      showMessage: false,
    );
    if (!sent || !mounted) return;
    setState(() {
      _waitingForProfile = true;
      final r = _hub.find(widget.sessionId);
      if (r != null) r.profileWaiting = true;
      _pausedUntilReply = pause;
    });
    _hub.system(widget.sessionId, 'Вы запросили профиль собеседника', outgoing: true);
  }

  Future<void> _revealMyProfile() async {
    if (!_live || _sending) return;
    final username = SocketService.instance.currentUser?.trim() ?? '';
    final text = TemporaryTrustMessage.revealTextFor(username);
    if (text == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: TemporaryTrustText('Не удалось безопасно подготовить профиль'),
        ),
      );
      return;
    }
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const TemporaryTrustText('Показать свой профиль?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TemporaryTrustText('Собеседник увидит ваше имя пользователя:'),
            const SizedBox(height: 12),
            SelectableText(
              '@$username',
              style: const TextStyle(fontWeight: FontWeight.bold, color: _gold),
            ),
            const SizedBox(height: 14),
            const TemporaryTrustText(
              'После отправки собеседник сможет сохранить эти данные. Фото, номер телефона и постоянные контакты не передаются.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const TemporaryTrustText('Остаться анонимным'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const TemporaryTrustText('Показать профиль'),
          ),
        ],
      ),
    );
    if (!mounted || approved != true || !_live) return;
    final sent = await _sendEncryptedText(text, showMessage: false);
    if (!sent || !mounted) return;
    setState(() {
      _incomingProfileRequest = false;
      _sharedMyProfile = true;
      final r = _hub.find(widget.sessionId);
      if (r != null) {
        r.myProfileShared = true;
        r.profileRequested = false;
      }
    });
    _hub.system(widget.sessionId, 'Вы добровольно открыли свой никнейм', outgoing: true);
  }

  Future<void> _declineProfile() async {
    if (!_live || _sending) return;
    final sent = await _sendEncryptedText(
      TemporaryTrustMessage.declineText,
      showMessage: false,
    );
    if (!sent || !mounted) return;
    setState(() {
      _incomingProfileRequest = false;
      final r = _hub.find(widget.sessionId);
      if (r != null) r.profileRequested = false;
    });
    _hub.system(widget.sessionId, 'Вы решили остаться анонимным', outgoing: true);
  }

  Widget _trustCard({required Widget child}) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: _surface,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: _gold.withValues(alpha: .50)),
    ),
    child: child,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        leading: const BackButton(),
        title: Row(
          children: [
            Container(width: 46, height: 46, decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: _gold, width: 2)), child: const CircleAvatar(backgroundColor: _surface, backgroundImage: AssetImage('assets/images/fenyvo_enigma_hood.png'))) ,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TemporaryTrustText(
                    _peerSharedUsername == null
                        ? 'Анонимный собеседник'
                        : '@$_peerSharedUsername',
                    style: const TextStyle(fontSize: 17),
                  ),
                  const TemporaryTrustText('Временный чат • E2EE',
                      style: TextStyle(fontSize: 12, color: _gold)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'profile') _askForProfile();
              if (value == 'leave') Navigator.of(context).pop();
              if (value == 'end') _endChat();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'profile', child: TemporaryTrustText('Запросить профиль')),
              PopupMenuItem(value: 'leave', child: TemporaryTrustText('Свернуть чат (не завершать)')),
              PopupMenuItem(value: 'end', child: TemporaryTrustText('Завершить чат для обоих')),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: _trustCard(
              child: Row(
                children: [
                  const Icon(Icons.timer_outlined, color: _gold),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TemporaryTrustText(
                      _enigmaRemainingLabel,
                      style: const TextStyle(
                        color: _gold,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Icon(Icons.lock_outline_rounded, color: _gold, size: 17),
                  const SizedBox(width: 5),
                  const TemporaryTrustText(
                    'E2EE',
                    style: TextStyle(color: _gold, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: _trustCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(
                        _peerSharedUsername == null
                            ? Icons.visibility_off_rounded
                            : Icons.person_outline_rounded,
                        color: _gold,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TemporaryTrustText(
                          _peerSharedUsername == null
                              ? 'Профиль собеседника скрыт'
                              : 'Собеседник назвал себя @$_peerSharedUsername',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  TemporaryTrustText(
                    _peerSharedUsername == null
                        ? 'Если сомневаетесь — попросите показать профиль.'
                        : 'Эти данные сообщил собеседник. Личность не проверена.',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  if (_peerSharedUsername == null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(backgroundColor: const Color(0xFF162539), foregroundColor: const Color(0xFFD8B36C), disabledForegroundColor: Colors.white38, side: const BorderSide(color: Color(0xFFD8B36C)), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                        onPressed: _live && !_sending && !_waitingForProfile
                            ? _askForProfile
                            : null,
                        icon: const Icon(Icons.badge_outlined),
                        label: TemporaryTrustText(
                          _waitingForProfile
                              ? 'Ожидаем ответ на запрос'
                              : 'Запросить профиль',
                        ),
                      ),
                    ),
                  if (_sharedMyProfile)
                    const TemporaryTrustText(
                      'Ваш никнейм уже открыт собеседнику',
                      style: TextStyle(color: _gold, fontSize: 12),
                    ),
                ],
              ),
            ),
          ),
          if (_incomingProfileRequest)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: _trustCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const TemporaryTrustText(
                      'Собеседник просит показать профиль',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const TemporaryTrustText(
                      'Решение только за вами.',
                      style: TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 9),
                    FilledButton(
                      onPressed: _live && !_sending ? _revealMyProfile : null,
                      child: const TemporaryTrustText('Показать профиль'),
                    ),
                    OutlinedButton(
                      onPressed: _live && !_sending ? _declineProfile : null,
                      child: const TemporaryTrustText('Остаться анонимным'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const TemporaryTrustText('Свернуть чат'),
                    ),
                  ],
                ),
              ),
            ),
          if (_pausedUntilReply)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: _trustCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const TemporaryTrustText(
                      'Вы приостановили отправку сообщений',
                      style: TextStyle(color: Colors.white),
                    ),
                    TextButton(
                      onPressed: () =>
                          setState(() => _pausedUntilReply = false),
                      child: const TemporaryTrustText('Продолжить анонимно'),
                    ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            child: TemporaryTrustText(
              _status,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: TemporaryTrustText(
                      'Начните общение. Ваш профиль пока скрыт.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white70),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final item = _messages[index];
                      return Align(
                        alignment: item.outgoing
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 300),
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: item.system ? _background : (item.outgoing ? _gold : _surface),
                            border: Border.all(
                              color: item.system
                                  ? _gold.withValues(alpha: .35)
                                  : item.outgoing
                                  ? _gold
                                  : Colors.white24,
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            item.system ? TemporaryTrustL10n.text(item.text) : item.text,
                            style: TextStyle(
                              color: item.system ? _gold : (item.outgoing ? _background : Colors.white),
                              fontSize: item.system ? 13 : 15,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: CallbackShortcuts(
                      bindings: _isWindows
                          ? <ShortcutActivator, VoidCallback>{
                              const SingleActivator(
                                LogicalKeyboardKey.enter,
                                includeRepeats: false,
                              ): _submitWithEnter,
                              const SingleActivator(
                                LogicalKeyboardKey.numpadEnter,
                                includeRepeats: false,
                              ): _submitWithEnter,
                            }
                          : const <ShortcutActivator, VoidCallback>{},
                      child: TextField(
                        controller: _messageController,
                        focusNode: _messageFocusNode,
                      enabled: _live && !_pausedUntilReply && (!_sending || _isWindows),
                      readOnly: _isWindows && _sending,
                      style: const TextStyle(color: Colors.white),
                      maxLines: 4,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: _pausedUntilReply
                            ? TemporaryTrustL10n.text('Ожидаем ответ на запрос')
                            : TemporaryTrustL10n.text('Сообщение'),

                        filled: true,
                        fillColor: const Color(0xFF162539),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(color: Color(0xFFB59357), width: 1.3),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(color: _gold, width: 2),
                        ),
                        disabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: const BorderSide(color: Colors.white24),
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    style: IconButton.styleFrom(backgroundColor: _gold, foregroundColor: _background, disabledBackgroundColor: const Color(0xFF344055), disabledForegroundColor: Colors.white38, minimumSize: const Size(48, 48), shape: const CircleBorder()),
                    onPressed: _live && !_sending && !_pausedUntilReply
                        ? _send
                        : null,
                    icon: const Icon(Icons.send_rounded),
                    tooltip: TemporaryTrustL10n.text('Отправить сообщение'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
