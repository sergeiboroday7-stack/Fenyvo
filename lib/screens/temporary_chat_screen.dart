import 'package:flutter/material.dart';

import '../services/socket_service.dart';

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
  final _messageController = TextEditingController();
  final List<_TemporaryChatMessage> _messages = [];

  bool _sending = false;
  String _status = 'Защищённое соединение активно';

  @override
  void initState() {
    super.initState();
    SocketService.instance.addMessageHandler(_handleMessage);
  }

  @override
  void dispose() {
    SocketService.instance.removeMessageHandler(_handleMessage);
    _messageController.dispose();
    super.dispose();
  }

  void _handleMessage(Map<String, dynamic> msg) {
    if (!mounted) return;

    final type = msg['type']?.toString() ?? '';
    final rawData = msg['data'];

    if (rawData is! Map) return;

    final data = Map<String, dynamic>.from(rawData);
    final sessionId = data['sessionId']?.toString() ?? '';

    if (sessionId != widget.sessionId) return;

    if (type == 'temporary_message') {
      final text = data['text']?.toString() ?? '';
      if (text.isEmpty) return;

      setState(() {
        _messages.add(_TemporaryChatMessage(text: text, outgoing: false));
        _status = 'Получено защищённое сообщение';
      });
      return;
    }

    if (type == 'temporary_message_error') {
      setState(() {
        _sending = false;
        _status =
            data['reason']?.toString() ?? 'Не удалось расшифровать сообщение';
      });
    }
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();

    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _status = 'Шифрование и отправка...';
    });

    final sent = await SocketService.instance.sendTemporaryEncryptedMessage(
      sessionId: widget.sessionId,
      role: widget.role,
      text: text,
      messageId: DateTime.now().microsecondsSinceEpoch.toString(),
    );

    if (!mounted) return;

    setState(() {
      _sending = false;
      _status = sent
          ? 'Зашифрованное сообщение отправлено'
          : 'Не удалось отправить сообщение';

      if (sent) {
        _messages.add(_TemporaryChatMessage(text: text, outgoing: true));
        _messageController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Временный защищённый чат')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Row(
              children: [
                Icon(Icons.lock_rounded),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'E2EE • постоянное имя скрыто',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          Text(_status),
          const SizedBox(height: 8),
          Expanded(
            child: _messages.isEmpty
                ? const Center(child: Text('Сообщений пока нет'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[index];

                      return Align(
                        alignment: message.outgoing
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(message.text),
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
                    child: TextField(
                      controller: _messageController,
                      decoration: const InputDecoration(
                        hintText: 'Сообщение',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _sending ? null : _send,
                    icon: const Icon(Icons.send_rounded),
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

class _TemporaryChatMessage {
  const _TemporaryChatMessage({required this.text, required this.outgoing});

  final String text;
  final bool outgoing;
}
