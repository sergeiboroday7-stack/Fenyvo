import 'package:flutter/material.dart';

import '../services/socket_service.dart';

class TemporaryContactScreen extends StatefulWidget {
  const TemporaryContactScreen({super.key});

  @override
  State<TemporaryContactScreen> createState() => _TemporaryContactScreenState();
}

class _TemporaryContactScreenState extends State<TemporaryContactScreen> {
  final _tokenController = TextEditingController();
  final _messageController = TextEditingController();

  String? _sessionId;
  String? _role;
  String _status = '';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    SocketService.instance.addMessageHandler(_handleMessage);
  }

  @override
  void dispose() {
    SocketService.instance.removeMessageHandler(_handleMessage);
    _tokenController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _handleMessage(Map<String, dynamic> msg) {
    if (!mounted) return;

    final type = msg['type']?.toString() ?? '';
    final rawData = msg['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};

    if (type == 'temporary_contact_joined') {
      if (data['success'] == false) {
        setState(() {
          _busy = false;
          _status = data['reason']?.toString() ?? 'Ошибка подключения';
        });
        return;
      }

      final sessionId = data['sessionId']?.toString().trim() ?? '';
      final role = data['role']?.toString().trim() ?? '';

      if (sessionId.isEmpty || role.isEmpty) return;

      setState(() {
        _sessionId = sessionId;
        _role = role;
        _busy = false;
        _status = 'Временный контакт подключён';
      });
      return;
    }

    if (type == 'temporary_message') {
      final text = data['text']?.toString() ?? '';

      setState(() {
        _status = 'Получено: $text';
      });
      return;
    }

    if (type == 'temporary_message_error') {
      setState(() {
        _busy = false;
        _status = data['reason']?.toString() ?? 'Ошибка временного сообщения';
      });
    }
  }

  Future<void> _create() async {
    setState(() {
      _busy = true;
      _status = '';
    });

    final result = await SocketService.instance.createTemporaryContact(
      durationMinutes: 60,
      allowMessages: true,
      allowCalls: false,
      allowFiles: false,
    );

    if (!mounted) return;

    if (result == null || result.isEmpty || result['success'] != true) {
      setState(() {
        _busy = false;
        _status =
            result?['reason']?.toString() ??
            'Не удалось создать временный контакт';
      });
      return;
    }

    final link = result['link']?.toString().trim() ?? '';
    final token = result['token']?.toString().trim() ?? '';

    setState(() {
      _busy = false;
      _tokenController.text = link.isNotEmpty ? link : token;
      _status = 'Временный контакт создан';
    });
  }

  void _join() {
    var value = _tokenController.text.trim();

    if (value.contains('/t/')) {
      value = value.split('/t/').last.split(RegExp(r'[?#]')).first.trim();
    }

    value = value.toLowerCase();

    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
      setState(() {
        _status = 'Некорректная временная ссылка или токен';
      });
      return;
    }

    setState(() {
      _busy = true;
      _status = 'Подключение...';
    });

    if (!SocketService.instance.joinTemporaryContact(value)) {
      setState(() {
        _busy = false;
        _status = 'Не удалось отправить запрос подключения';
      });
    }
  }

  Future<void> _send() async {
    final sessionId = _sessionId;
    final role = _role;
    final text = _messageController.text.trim();

    if (sessionId == null || role == null || text.isEmpty) return;

    setState(() {
      _busy = true;
      _status = 'Шифрование и отправка...';
    });

    final sent = await SocketService.instance.sendTemporaryEncryptedMessage(
      sessionId: sessionId,
      role: role,
      text: text,
      messageId: DateTime.now().microsecondsSinceEpoch.toString(),
    );

    if (!mounted) return;

    setState(() {
      _busy = false;
      _status = sent ? 'Зашифрованное сообщение отправлено' : 'Ошибка отправки';
    });

    if (sent) {
      _messageController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Временный контакт')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('Общение без раскрытия постоянного имени пользователя.'),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _create,
            icon: const Icon(Icons.link_rounded),
            label: const Text('Создать временный контакт'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tokenController,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Ссылка или токен',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _join,
            icon: const Icon(Icons.login_rounded),
            label: const Text('Подключиться'),
          ),
          if (_status.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(_status),
          ],
          if (_sessionId != null) ...[
            const SizedBox(height: 24),
            TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                labelText: 'Сообщение',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _send,
              icon: const Icon(Icons.lock_rounded),
              label: const Text('Отправить зашифрованно'),
            ),
          ],
        ],
      ),
    );
  }
}
