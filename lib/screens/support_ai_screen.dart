import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/socket_service.dart';
import '../theme/spartan_theme.dart';

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
    final requestId = data['requestId']?.toString() ?? '';
    if (requestId.isEmpty || requestId != _pendingRequestId) return;

    if (type == 'support_ai_result') {
      final result = data['result']?.toString().trim() ?? '';
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
      final reason = data['reason']?.toString().trim() ?? '';
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

  void _send() {
    if (_waiting) return;
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final requestId =
        'support_${DateTime.now().microsecondsSinceEpoch.toString()}';

    setState(() {
      _messages.add(_SupportMessage(text: text, fromUser: true));
      _pendingRequestId = requestId;
      _waiting = true;
      _controller.clear();
    });
    SocketService.instance.sendSupportAiRequest(
      requestId: requestId,
      text: text,
    );
    _scrollToEnd();
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
                color: SpartanPalette.surface.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: SpartanPalette.ink.withValues(alpha: 0.22),
                ),
              ),
              child: const Text(
                'Отвечает ИИ, а не человек. Вопрос отправляется только после нажатия кнопки. Личные чаты автоматически не читаются.',
                style: TextStyle(color: SpartanPalette.secondary, fontSize: 12),
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
                            ? SpartanPalette.blue
                            : SpartanPalette.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: SpartanPalette.ink.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Text(
                        message.text,
                        style: const TextStyle(color: SpartanPalette.ink),
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_waiting)
              const LinearProgressIndicator(
                minHeight: 2,
                color: SpartanPalette.ink,
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
