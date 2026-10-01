import 'package:flutter/material.dart';

import '../services/socket_service.dart';

class ContactAddScreen extends StatefulWidget {
  const ContactAddScreen({super.key, this.initialUsername});

  final String? initialUsername;

  @override
  State<ContactAddScreen> createState() => _ContactAddScreenState();
}

class _ContactAddScreenState extends State<ContactAddScreen> {
  final _usernameController = TextEditingController();
  final _messageController = TextEditingController(
    text: 'Хочу добавить вас в контакты.',
  );

  String? _foundUsername;
  String _about = '';
  String _region = '';
  String _statusText = '';
  String _communicationStatus = 'none';
  String? _error;

  bool _searching = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    SocketService.instance.addMessageHandler(_handleMessage);

    final initialUsername = widget.initialUsername?.trim() ?? '';

    if (initialUsername.isNotEmpty) {
      _usernameController.text = initialUsername;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _searchContact();
        }
      });
    }
  }

  @override
  void dispose() {
    SocketService.instance.removeMessageHandler(_handleMessage);
    _usernameController.dispose();
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

    if (type == 'user_profile') {
      final requested = _usernameController.text.trim();
      final username = data['username']?.toString().trim() ?? '';

      if (username.isNotEmpty &&
          requested.isNotEmpty &&
          username.toLowerCase() != requested.toLowerCase()) {
        return;
      }

      final reason = data['reason']?.toString().trim();

      if (reason != null && reason.isNotEmpty) {
        setState(() {
          _searching = false;
          _foundUsername = null;
          _communicationStatus = 'none';
          _error = reason;
        });
        return;
      }

      if (username.isEmpty) return;

      setState(() {
        _searching = false;
        _foundUsername = username;
        _about = data['about']?.toString().trim() ?? '';
        _region = data['region']?.toString().trim() ?? '';
        _statusText = data['statusText']?.toString().trim() ?? '';
        _error = null;
      });

      SocketService.instance.getCommunicationState(username);
      return;
    }

    if (type == 'communication_state') {
      final contact = data['contact']?.toString().trim() ?? '';

      if (_foundUsername == null ||
          contact.toLowerCase() != _foundUsername!.toLowerCase()) {
        return;
      }

      setState(() {
        _communicationStatus = data['status']?.toString().trim() ?? 'none';
      });
      return;
    }

    if (type == 'communication_request_status') {
      final to = data['to']?.toString().trim() ?? '';

      if (_foundUsername == null ||
          to.toLowerCase() != _foundUsername!.toLowerCase()) {
        return;
      }

      final reason = data['reason']?.toString().trim() ?? '';
      final sent = data['sent'] == true;
      final pending = data['pending'] == true;
      final accepted = data['accepted'] == true;

      setState(() {
        _sending = false;

        if (accepted) {
          _communicationStatus = 'accepted';
        } else if (sent && pending) {
          _communicationStatus = 'pending';
        }

        if (!sent && reason.isNotEmpty && !accepted) {
          _error = reason;
        } else {
          _error = null;
        }
      });

      if (sent && pending) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Запрос на добавление отправлен')),
        );
      }

      return;
    }

    if (type == 'communication_request_response') {
      final from = data['from']?.toString().trim() ?? '';
      final to = data['to']?.toString().trim() ?? '';
      final currentUser = SocketService.instance.currentUser?.trim() ?? '';

      String peer = '';
      if (from.toLowerCase() == currentUser.toLowerCase()) {
        peer = to;
      } else if (to.toLowerCase() == currentUser.toLowerCase()) {
        peer = from;
      }

      if (_foundUsername == null ||
          peer.toLowerCase() != _foundUsername!.toLowerCase()) {
        return;
      }

      setState(() {
        _sending = false;
        _communicationStatus = data['status']?.toString().trim() ?? 'none';
      });
    }
  }

  void _searchContact() {
    final username = _usernameController.text.trim();

    if (username.isEmpty) {
      setState(() {
        _error = 'Введите точное имя пользователя';
      });
      return;
    }

    final currentUser = SocketService.instance.currentUser?.trim() ?? '';

    if (currentUser.isNotEmpty &&
        username.toLowerCase() == currentUser.toLowerCase()) {
      setState(() {
        _error = 'Нельзя добавить самого себя';
      });
      return;
    }

    setState(() {
      _searching = true;
      _foundUsername = null;
      _communicationStatus = 'none';
      _error = null;
    });

    SocketService.instance.getUserProfile(username);
  }

  void _sendRequest() {
    final username = _foundUsername;
    if (username == null || username.isEmpty) return;

    final message = _messageController.text.trim();

    if (message.isEmpty) {
      setState(() {
        _error = 'Напишите короткое сообщение';
      });
      return;
    }

    if (message.length > 300) {
      setState(() {
        _error = 'Сообщение не должно быть длиннее 300 символов';
      });
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    SocketService.instance.requestCommunication(username, message: message);
  }

  String _statusLabel() {
    switch (_communicationStatus) {
      case 'accepted':
        return 'Контакт подтверждён';
      case 'pending':
        return 'Запрос ожидает ответа';
      case 'declined':
        return 'Предыдущий запрос был отклонён';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final found = _foundUsername;

    return Scaffold(
      appBar: AppBar(title: const Text('Добавить контакт')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Введите точное имя пользователя. '
            'Список зарегистрированных пользователей не показывается.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _usernameController,
            textInputAction: TextInputAction.search,
            autocorrect: false,
            enableSuggestions: false,
            onSubmitted: (_) => _searchContact(),
            decoration: InputDecoration(
              labelText: 'Имя пользователя',
              hintText: 'Например: Alla',
              prefixIcon: const Icon(Icons.person_search_rounded),
              suffixIcon: IconButton(
                tooltip: 'Найти',
                onPressed: _searching ? null : _searchContact,
                icon: _searching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search_rounded),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          if (found != null) ...[
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(child: Icon(Icons.person_rounded)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            found,
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                      ],
                    ),
                    if (_statusText.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(_statusText),
                    ],
                    if (_about.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(_about),
                    ],
                    if (_region.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.location_on_outlined, size: 18),
                          const SizedBox(width: 6),
                          Expanded(child: Text(_region)),
                        ],
                      ),
                    ],
                    if (_statusLabel().isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        _statusLabel(),
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (_communicationStatus != 'accepted' &&
                _communicationStatus != 'pending') ...[
              const SizedBox(height: 16),
              TextField(
                controller: _messageController,
                maxLength: 300,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Сообщение к запросу',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _sending ? null : _sendRequest,
                icon: _sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Отправить запрос'),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
