import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/socket_service.dart';
import '../services/app_language_service.dart';
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
    const _SupportMessage(text: 'supportAiWelcome', fromUser: false),
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
                  ? AppLanguageService.instance
                        .text('supportTicketAccepted')
                        .replaceAll('{ticketId}', ticketId)
                  : (reason.isNotEmpty ? reason : 'supportTicketUnconfirmed'),
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
            text: result.isEmpty ? 'supportAiEmptyResponse' : result,
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
            text: reason.isEmpty ? 'supportAiUnavailable' : reason,
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
          const _SupportMessage(text: 'supportAiTimeout', fromUser: false),
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
          const _SupportMessage(text: 'supportAiDisconnected', fromUser: false),
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
          title: Text(AppLanguageService.instance.text('supportAiTicketTitle')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppLanguageService.instance.text('supportAiTicketNotice')),
                const SizedBox(height: 12),
                TextField(
                  controller: issueController,
                  maxLength: 2000,
                  maxLines: 5,
                  minLines: 3,
                  decoration: InputDecoration(
                    labelText: AppLanguageService.instance.text(
                      'supportAiTicketText',
                    ),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  maxLength: 254,
                  decoration: InputDecoration(
                    labelText: AppLanguageService.instance.text(
                      'supportAiTicketEmail',
                    ),
                    border: OutlineInputBorder(),
                  ),
                ),
                CheckboxListTile(
                  value: consent,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    AppLanguageService.instance.text('supportAiTicketConsent'),
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
              child: Text(AppLanguageService.instance.text('cancel')),
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
                    () => validationError = AppLanguageService.instance.text(
                      'supportAiTicketValidation',
                    ),
                  );
                  return;
                }
                Navigator.of(dialogContext).pop((text: text, email: email));
              },
              child: Text(
                AppLanguageService.instance.text('supportAiTicketSubmit'),
              ),
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
        SnackBar(
          content: Text(
            AppLanguageService.instance.text('supportTicketLoginRequired'),
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
        SnackBar(
          content: Text(
            AppLanguageService.instance.text('supportTicketSendFailed'),
          ),
        ),
      );
      return;
    }
    setState(() {
      _pendingTicketId = requestId;
      _ticketWaiting = true;
      _messages.add(
        const _SupportMessage(text: 'supportTicketPending', fromUser: false),
      );
    });
    _scrollToEnd();
    Future<void>.delayed(const Duration(seconds: 30), () {
      if (!mounted || _pendingTicketId != requestId) return;
      setState(() {
        _pendingTicketId = null;
        _ticketWaiting = false;
        _messages.add(
          const _SupportMessage(text: 'supportTicketUnknown', fromUser: false),
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
    final t = AppLanguageService.instance.text;
    return Scaffold(
      appBar: AppBar(
        title: Text(t('supportAiTitle')),
        actions: [
          IconButton(
            tooltip: t('supportAiEmailTooltip'),
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
              child: Text(
                t('supportAiDisclosure'),
                style: const TextStyle(
                  color: FenyvoPalette.secondary,
                  fontSize: 12,
                ),
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
                        ? t('supportAiWaiting')
                        : t('supportAiEscalate'),
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
                        message.fromUser ||
                                !const {
                                  'supportAiWelcome',
                                  'supportAiTimeout',
                                  'supportAiDisconnected',
                                  'supportAiEmptyResponse',
                                  'supportAiUnavailable',
                                  'supportTicketPending',
                                  'supportTicketUnconfirmed',
                                  'supportTicketUnknown',
                                }.contains(message.text)
                            ? message.text
                            : AppLanguageService.instance.text(message.text),
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
                      decoration: InputDecoration(
                        hintText: t('supportAiQuestionHint'),
                        counterText: '',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    tooltip: t('supportAiSendTooltip'),
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
