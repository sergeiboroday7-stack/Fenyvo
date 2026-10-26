import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/socket_service.dart';
import '../theme/fenyvo_theme.dart';

class SupportAiScreen extends StatefulWidget {
  const SupportAiScreen({super.key});

  @override
  State<SupportAiScreen> createState() => _SupportAiScreenState();
}

class _SupportAiScreenState extends State<SupportAiScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_SupportMessage> _messages = <_SupportMessage>[
    const _SupportMessage(
      text: 'Я автоматический помощник Fenyvo. Я могу объяснить функции приложения и помочь с обычными неполадками. Не отправляйте пароли, ключи, платёжные данные или документы. Для вопросов о персональных данных напишите на privacy@fenyvo.com.',
      fromUser: false,
    ),
  ];

  String? _pendingRequestId;
  bool _waiting = false;
  String? _pendingTicketId;
  bool _ticketWaiting = false;

  @override
  void initState() {
    super.initState();
    SocketService.instance.addMessageHandler(_handleMessage);
  }

  @override
  void dispose() {
    SocketService.instance.removeMessageHandler(_handleMessage);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _handleMessage(Map<String, dynamic> data) {
    if (!mounted) return;
    final type = data['type']?.toString() ?? '';
    final payload = data['data'] is Map
        ? Map<String, dynamic>.from(data['data'] as Map)
        : data;
    final requestId = payload['requestId']?.toString() ?? '';
    if (requestId.isNotEmpty && requestId == _pendingTicketId) {
      if (type == 'support_ticket_result' || type == 'support_ticket_error') {
        final accepted =
            type == 'support_ticket_result' && payload['accepted'] == true;
        final ticketId = payload['ticketId']?.toString().trim() ?? '';
        final reason = payload['reason']?.toString().trim() ?? '';
        setState(() {
          _pendingTicketId = null;
          _ticketWaiting = false;
          _messages.add(
            _SupportMessage(
              text: accepted && ticketId.isNotEmpty
                  ? 'Обращение передано специалисту. Номер: $ticketId. '
                        'Ответ придёт на указанный email.'
                  : (reason.isNotEmpty
                        ? reason
                        : 'Подтверждение отправки не получено. '
                              'Не создавайте повторное обращение до проверки.'),
              fromUser: false,
            ),
          );
        });
        _scrollToEnd();
        return;
      }
    }
    if (requestId.isEmpty || requestId != _pendingRequestId) return;

    if (type == 'support_ai_result') {
      final result = payload['result']?.toString().trim() ?? '';
      setState(() {
        _waiting = false;
        _pendingRequestId = null;
        _messages.add(
          _SupportMessage(
            text: result.isEmpty
                ? 'Не удалось сформировать ответ. Напишите на support@fenyvo.com.'
                : result,
            fromUser: false,
          ),
        );
      });
      _scrollToEnd();
      return;
    }

    if (type == 'support_ai_error') {
      final reason = payload['reason']?.toString().trim() ?? '';
      setState(() {
        _waiting = false;
        _pendingRequestId = null;
        _messages.add(
          _SupportMessage(
            text: reason.isEmpty
                ? 'Помощник временно недоступен. Напишите на support@fenyvo.com.'
                : reason,
            fromUser: false,
          ),
        );
      });
      _scrollToEnd();
    }
  }

  void _startResponseTimeout(String requestId) {
    Future<void>.delayed(const Duration(seconds: 55), () {
      if (!mounted || _pendingRequestId != requestId) return;
      setState(() {
        _waiting = false;
        _pendingRequestId = null;
        _messages.add(
          const _SupportMessage(
            text: 'Помощник не ответил вовремя. Проверьте соединение и попробуйте снова.',
            fromUser: false,
          ),
        );
      });
      _scrollToEnd();
    });
  }

  void _send() {
    if (_waiting) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    if (!SocketService.instance.isConnected) {
      setState(() {
        _messages.add(
          const _SupportMessage(
            text: 'Нет соединения с сервером Fenyvo. Проверьте интернет и попробуйте снова.',
            fromUser: false,
          ),
        );
      });
      _scrollToEnd();
      return;
    }
    final requestId =
        'support_${DateTime.now().microsecondsSinceEpoch.toString()}';

    setState(() {
      _messages.add(_SupportMessage(text: text, fromUser: true));
      _pendingRequestId = requestId;
      _waiting = true;
      _controller.clear();
    });
    _startResponseTimeout(requestId);
    SocketService.instance.sendSupportAiRequest(
      requestId: requestId,
      text: text,
    );
    _scrollToEnd();
  }

  Future<void> _openTicketDialog() async {
    if (_ticketWaiting) return;
    final initialText = _controller.text.trim().isNotEmpty
        ? _controller.text.trim()
        : _messages.reversed
                  .where((m) => m.fromUser)
                  .map((m) => m.text)
                  .firstOrNull ??
              '';
    final issueController = TextEditingController(text: initialText);
    final emailController = TextEditingController();
    bool consent = false;
    String? validationError;
    final submitted = await showDialog<({String text, String email})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: const Text('Передать вопрос специалисту'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Проверьте текст перед отправкой. '
                  'Личные чаты не прикладываются автоматически.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: issueController,
                  maxLength: 2000,
                  maxLines: 5,
                  minLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Текст обращения',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  maxLength: 254,
                  decoration: const InputDecoration(
                    labelText: 'Email для ответа',
                    border: OutlineInputBorder(),
                  ),
                ),
                CheckboxListTile(
                  value: consent,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text(
                    'Согласен передать указанный текст и email '
                    'в службу поддержки Fenyvo для ответа.',
                    style: TextStyle(fontSize: 13),
                  ),
                  onChanged: (value) => setDialogState(() {
                    consent = value == true;
                    validationError = null;
                  }),
                ),
                if (validationError != null)
                  Text(
                    validationError!,
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () {
                final text = issueController.text.trim();
                final email = emailController.text.trim();
                final validEmail = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                    .hasMatch(email);
                if (text.length < 5 ||
                    text.length > 2000 ||
                    email.length > 254 ||
                    !validEmail ||
                    !consent) {
                  setDialogState(
                    () => validationError =
                        'Проверьте вопрос (5–2000 символов), email и согласие.',
                  );
                  return;
                }
                Navigator.of(dialogContext).pop((text: text, email: email));
              },
              child: const Text('Передать'),
            ),
          ],
        ),
      ),
    );
    // Dispose after the dialog's exit animation completes.
    Future<void>.delayed(const Duration(milliseconds: 400), () {
      issueController.dispose();
      emailController.dispose();
    });
    if (!mounted || submitted == null) return;
    if (!SocketService.instance.isAuthenticated) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Для обращения войдите в аккаунт и подключитесь к серверу.',
          ),
        ),
      );
      return;
    }
    final requestId =
        'ticket_${DateTime.now().microsecondsSinceEpoch}_'
        '${Random.secure().nextInt(1 << 30)}';
    final sent = SocketService.instance.sendSupportTicketRequest(
      requestId: requestId,
      text: submitted.text,
      email: submitted.email,
      consent: true,
    );
    if (!sent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось отправить запрос. Проверьте соединение.'),
        ),
      );
      return;
    }
    setState(() {
      _pendingTicketId = requestId;
      _ticketWaiting = true;
      _messages.add(
        const _SupportMessage(
          text: 'Запрос передан серверу. Ожидаем подтверждения…',
          fromUser: false,
        ),
      );
    });
    _scrollToEnd();
    Future<void>.delayed(const Duration(seconds: 30), () {
      if (!mounted || _pendingTicketId != requestId) return;
      setState(() {
        _pendingTicketId = null;
        _ticketWaiting = false;
        _messages.add(
          const _SupportMessage(
            text:
                'Подтверждение не получено. Результат неизвестен. '
                'Не отправляйте повторно до проверки в поддержке.',
            fromUser: false,
          ),
        );
      });
      _scrollToEnd();
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _emailSupport() => launchUrl(
    Uri.parse('mailto:support@fenyvo.com?subject=Fenyvo%20Support'),
    mode: LaunchMode.externalApplication,
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Помощник поддержки'),
        actions: [
          IconButton(
            tooltip: 'Написать владельцу',
            onPressed: _emailSupport,
            icon: const Icon(Icons.mail_outline_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: FenyvoPalette.surface.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: FenyvoPalette.ink.withValues(alpha: 0.22),
                ),
              ),
              child: const Text(
                'Отвечает ИИ, а не человек. Вопрос отправляется только после нажатия кнопки. Личные чаты автоматически не читаются.',
                style: TextStyle(color: FenyvoPalette.secondary, fontSize: 12),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _ticketWaiting ? null : _openTicketDialog,
                  icon: const Icon(Icons.support_agent_outlined),
                  label: Text(
                    _ticketWaiting
                        ? 'Ожидаем подтверждения обращения…'
                        : 'Передать вопрос специалисту',
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.all(14),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return Align(
                    alignment: message.fromUser
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 560),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 11,
                      ),
                      decoration: BoxDecoration(
                        color: message.fromUser
                            ? FenyvoPalette.blue
                            : FenyvoPalette.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: FenyvoPalette.ink.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        message.text,
                        style: const TextStyle(color: FenyvoPalette.ink),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_waiting)
              const LinearProgressIndicator(
                minHeight: 2,
                color: FenyvoPalette.ink,
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      enabled: !_waiting,
                      maxLength: 2000,
                      minLines: 1,
                      maxLines: 4,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: const InputDecoration(
                        hintText: 'Опишите вопрос без секретных данных',
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: 'Отправить',
                    onPressed: _waiting ? null : _send,
                    icon: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportMessage {
  const _SupportMessage({required this.text, required this.fromUser});

  final String text;
  final bool fromUser;
}
