import 'dart:async';

import 'package:flutter/material.dart';

import '../services/crypto/account_recovery_service.dart';
import '../services/crypto/recovery_signature_service.dart';
import '../services/socket_service.dart';

class RecoverySetupScreen extends StatefulWidget {
  const RecoverySetupScreen({super.key});

  @override
  State<RecoverySetupScreen> createState() => _RecoverySetupScreenState();
}

class _RecoverySetupScreenState extends State<RecoverySetupScreen> {
  final _password = TextEditingController();
  final _socket = SocketService.instance;
  String? _phrase;
  String? _status;
  bool _confirmed = false;
  bool _busy = false;
  bool _registered = false;
  Timer? _timeout;

  @override
  void initState() {
    super.initState();
    _registered = _socket.recoveryConfigured == true;
    if (_registered) {
      _status =
          'Слова восстановления уже привязаны к этому аккаунту. '
          'Сохранённые слова повторно не показываются.';
    }
    _socket.addMessageHandler(_onMessage);
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _socket.removeMessageHandler(_onMessage);
    _password.dispose();
    _phrase = null;
    super.dispose();
  }

  void _generate() {
    if (_busy || _registered) return;
    final phrase = const AccountRecoveryService().generateRecoveryPhrase();
    setState(() {
      _phrase = phrase;
      _confirmed = false;
      _status = null;
      _password.clear();
    });
  }

  void _finish(String message, {bool registered = false}) {
    _timeout?.cancel();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _registered = registered;
      _status = message;
      _password.clear();
    });
  }

  void _onMessage(Map<String, dynamic> message) {
    if (!_busy || !mounted) return;
    final type = message['type'];
    if (type == 'recovery_key_registered') {
      _socket.recoveryConfigured = true;
      _finish(
        'Ключ привязан к аккаунту. Сохраните все 12 слов: после выхода '
        'с этого экрана они больше не будут показаны.',
        registered: true,
      );
    } else if (type == 'recovery_key_error') {
      final data = message['data'];
      final reason = data is Map ? data['reason'] : null;
      _finish(reason is String ? reason : 'Не удалось привязать ключ.');
    }
  }

  Future<void> _register() async {
    if (_busy ||
        _registered ||
        !_confirmed ||
        _phrase == null ||
        _password.text.isEmpty) {
      return;
    }
    if (!_socket.isAuthenticated) {
      setState(
        () => _status = 'Сначала войдите в аккаунт и подключитесь к серверу.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Подготавливаем публичный ключ...';
    });
    try {
      final phrase = _phrase!;
      final password = _password.text;
      final pair = await const RecoverySignatureService().keyPairFromPhrase(
        phrase,
      );
      final publicKey = await pair.extractPublicKey();
      final hex = publicKey.bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      if (!mounted || !_busy) return;
      if (!_socket.registerRecoveryKey(publicKeyHex: hex, password: password)) {
        _finish('Не удалось отправить запрос. Проверьте соединение.');
        return;
      }
      setState(() => _status = 'Ожидаем подтверждение сервера...');
      _timeout?.cancel();
      _timeout = Timer(const Duration(seconds: 45), () {
        _finish(
          'Сервер не ответил. Проверьте состояние привязки перед повторной попыткой.',
        );
      });
    } catch (_) {
      _finish('Не удалось подготовить ключ восстановления.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Слова восстановления')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Создайте 12 секретных слов и сохраните их в безопасном месте. '
              'Они понадобятся, если вы забудете пароль. '
              'Никому не сообщайте эти слова: они не передаются серверу.',
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _busy || _registered ? null : _generate,
              child: Text(
                _registered
                    ? 'Слова уже привязаны'
                    : 'Создать 12 секретных слов',
              ),
            ),
            if (_phrase != null) ...[
              const SizedBox(height: 20),
              SelectableText(
                _phrase!,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 16),
              CheckboxListTile(
                value: _confirmed,
                onChanged: _busy || _registered
                    ? null
                    : (value) => setState(() => _confirmed = value ?? false),
                title: const Text('Я сохранил(а) все 12 слов'),
                subtitle: const Text(
                  'Без этих слов восстановить забытый пароль будет невозможно.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _password,
                enabled: !_busy && !_registered,
                onChanged: (_) => setState(() {}),
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Действующий пароль аккаунта',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed:
                    _confirmed &&
                        !_busy &&
                        !_registered &&
                        _password.text.isNotEmpty
                    ? _register
                    : null,
                child: Text(
                  _registered
                      ? 'Ключ зарегистрирован'
                      : _busy
                      ? 'Привязка...'
                      : 'Привязать слова к аккаунту',
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (_status != null) ...[
              const SizedBox(height: 12),
              Text(_status!),
            ],
          ],
        ),
      ),
    );
  }
}
