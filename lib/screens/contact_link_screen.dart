import 'package:flutter/material.dart';

import '../services/socket_service.dart';
import 'chat_screen.dart';

class ContactLinkScreen extends StatefulWidget {
  const ContactLinkScreen({super.key, required this.username});

  final String username;

  @override
  State<ContactLinkScreen> createState() => _ContactLinkScreenState();
}

class _ContactLinkScreenState extends State<ContactLinkScreen> {
  final TextEditingController _messageController = TextEditingController(
    text: 'Хочу добавить вас в контакты.',
  );

  Map<String, dynamic>? _profile;
  String _communicationStatus = 'loading';
  String? _error;
  bool _sending = false;

  String get _username => widget.username.trim();

  @override
  void initState() {
    super.initState();
    SocketService.instance.addMessageHandler(_handleMessage);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadContact());
  }

  @override
  void dispose() {
    SocketService.instance.removeMessageHandler(_handleMessage);
    _messageController.dispose();
    super.dispose();
  }

  void _loadContact() {
    if (!mounted || _username.isEmpty) return;
    final currentUser = SocketService.instance.currentUser?.trim() ?? '';
    if (currentUser.toLowerCase() == _username.toLowerCase()) {
      setState(() => _communicationStatus = 'self');
    } else {
      SocketService.instance.getCommunicationState(_username);
    }
    SocketService.instance.getUserProfile(_username);
  }

  void _handleMessage(Map<String, dynamic> message) {
    if (!mounted) return;
    final type = message['type']?.toString() ?? '';
    final rawData = message['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};

    if (type == 'user_profile') {
      final username = data['username']?.toString().trim() ?? '';
      final reason = data['reason']?.toString().trim() ?? '';
      if (reason.isNotEmpty) {
        setState(() => _error = reason);
      } else if (username.toLowerCase() == _username.toLowerCase()) {
        setState(() {
          _profile = data;
          _error = null;
        });
      }
      return;
    }

    if (type == 'communication_state') {
      final contact = data['contact']?.toString().trim() ?? '';
      if (contact.toLowerCase() == _username.toLowerCase()) {
        setState(() {
          _communicationStatus = data['status']?.toString() ?? 'none';
        });
      }
      return;
    }

    if (type == 'communication_request_status') {
      final to = data['to']?.toString().trim() ?? '';
      if (to.toLowerCase() != _username.toLowerCase()) return;
      final sent = data['sent'] == true;
      final accepted = data['accepted'] == true;
      setState(() {
        _sending = false;
        if (accepted) {
          _communicationStatus = 'accepted';
        } else if (sent && data['pending'] == true) {
          _communicationStatus = 'pending';
        }
        _error = sent || accepted ? null : data['reason']?.toString().trim();
      });
    }
  }

  void _sendRequest() {
    final text = _messageController.text.trim();
    if (text.isEmpty || text.length > 300) {
      setState(() => _error = 'Введите сообщение длиной до 300 символов');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    SocketService.instance.requestCommunication(_username, message: text);
  }

  void _openChat() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(targetUser: _username),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final about = _profile?['about']?.toString().trim() ?? '';
    final region = _profile?['region']?.toString().trim() ?? '';
    final statusText = _profile?['statusText']?.toString().trim() ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Контакт Fenyvo')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 20),
          CircleAvatar(
            radius: 48,
            child: Text(
              _username.isEmpty ? '?' : _username[0].toUpperCase(),
              style: const TextStyle(fontSize: 34),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '@$_username',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          if (statusText.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(statusText, textAlign: TextAlign.center),
          ],
          if (about.isNotEmpty) ...[
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(about),
              ),
            ),
          ],
          if (region.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_on_outlined, size: 18),
                const SizedBox(width: 6),
                Flexible(child: Text(region)),
              ],
            ),
          ],
          if (_error != null && _error!.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: 28),
          if (_communicationStatus == 'accepted')
            FilledButton.icon(
              onPressed: _openChat,
              icon: const Icon(Icons.chat_bubble_rounded),
              label: const Text('Открыть чат'),
            )
          else if (_communicationStatus == 'pending')
            const ListTile(
              leading: Icon(Icons.hourglass_top_rounded),
              title: Text('Запрос отправлен'),
              subtitle: Text('Ожидаем подтверждения пользователя'),
            )
          else if (_communicationStatus == 'self')
            const ListTile(
              leading: Icon(Icons.person_rounded),
              title: Text('Это ваш контакт'),
            )
          else ...[
            TextField(
              controller: _messageController,
              maxLength: 300,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Сообщение к запросу',
                border: OutlineInputBorder(),
              ),
            ),
            FilledButton.icon(
              onPressed: _sending ? null : _sendRequest,
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Добавить в контакты'),
            ),
          ],
        ],
      ),
    );
  }
}
