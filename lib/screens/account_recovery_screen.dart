import '../widgets/fenyvo_brand_mark.dart';
import '../config/server_config.dart';

import 'dart:async';

import '../services/crypto/account_recovery_service.dart';
import '../services/crypto/recovery_signature_service.dart';
import '../services/socket_service.dart';
import '../services/app_language_service.dart';

import 'package:flutter/material.dart';

class AccountRecoveryScreen extends StatefulWidget {
  const AccountRecoveryScreen({super.key});

  @override
  State<AccountRecoveryScreen> createState() => _AccountRecoveryScreenState();
}

class _AccountRecoveryScreenState extends State<AccountRecoveryScreen> {
  final _username = TextEditingController();
  final _words = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  // RECOVERY_CLIENT_FLOW_V1
  final SocketService _socket = SocketService.instance;
  bool _busy = false;
  String? _status;
  Timer? _timeout;
  Timer? _brandTimer;
  Timer? _noticeTimer;
  bool _brandExpanded = false;

  @override
  void initState() {
    super.initState();
    _socket.addMessageHandler(_onRecoveryMessage);
    AppLanguageService.instance.code.addListener(_onLanguageChanged);
    _brandTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted && !MediaQuery.disableAnimationsOf(context)) {
        setState(() => _brandExpanded = !_brandExpanded);
      }
    });
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  void _finish(String message) {
    _timeout?.cancel();
    _noticeTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = message;
    });
    _noticeTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && !_busy) setState(() => _status = null);
    });
  }

  void _onRecoveryMessage(Map<String, dynamic> message) {
    if (!_busy) return;
    final type = message['type'];
    final data = message['data'];
    if (type == 'recovery_challenge') {
      if (data is! Map) {
        _finish(
          AppLanguageService.instance.text('recoveryErrorInvalidResponse'),
        );
        return;
      }
      final id = data['challengeId'];
      if (id is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(id)) {
        _finish(
          AppLanguageService.instance.text('recoveryErrorInvalidChallenge'),
        );
        return;
      }
      _submitSignedChallenge(id);
    } else if (type == 'recovery_password_success') {
      _password.clear();
      _confirm.clear();
      _words.clear();
      _timeout?.cancel();
      if (mounted) Navigator.of(context).pop(_username.text.trim());
    } else if (type == 'recovery_error') {
      final reason = data is Map ? data['reason'] : null;
      _finish(
        reason is String
            ? reason
            : AppLanguageService.instance.text('recoveryErrorGeneric'),
      );
    }
  }

  Future<void> _submitSignedChallenge(String id) async {
    try {
      final username = _username.text.trim();
      final signedText = 'FENYVO/account-password-recovery/v1:$username:$id';
      final signature = await const RecoverySignatureService().signChallenge(
        _words.text,
        signedText,
      );
      if (!mounted || !_busy) return;
      final hex = signature.bytes
          .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
          .join();
      if (!_socket.submitRecoveryPassword(
        username: username,
        challengeId: id,
        signatureHex: hex,
        newPassword: _password.text,
      )) {
        _finish(AppLanguageService.instance.text('recoveryErrorDisconnected'));
      }
    } catch (_) {
      _finish(AppLanguageService.instance.text('recoveryErrorSigningFailed'));
    }
  }

  Future<void> _startRecovery() async {
    if (_busy || !_validInput) return;
    setState(() {
      _busy = true;
      _status = AppLanguageService.instance.text('recoveryStatusRequesting');
    });
    _timeout?.cancel();
    _timeout = Timer(
      const Duration(seconds: 45),
      () => _finish(AppLanguageService.instance.text('recoveryErrorTimeout')),
    );
    // RECOVERY_AUTO_CONNECT_V1
    try {
      final connected = await _socket.connect(
        ServerConfig.websocketUri.toString(),
      );
      if (!mounted || !_busy) return;
      if (!connected) {
        _finish(
          AppLanguageService.instance.text('recoveryErrorConnectionFailed'),
        );
        return;
      }
    } catch (_) {
      _finish(
        AppLanguageService.instance.text('recoveryErrorConnectionFailed'),
      );
      return;
    }

    if (!_socket.requestRecoveryChallenge(_username.text.trim())) {
      _finish(AppLanguageService.instance.text('recoveryErrorDisconnected'));
    }
  }

  @override
  void dispose() {
    _timeout?.cancel();
    _brandTimer?.cancel();
    _noticeTimer?.cancel();
    _socket.removeMessageHandler(_onRecoveryMessage);
    AppLanguageService.instance.code.removeListener(_onLanguageChanged);
    _username.dispose();
    _words.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  bool get _validInput {
    final username = _username.text.trim();
    final password = _password.text;
    return username.isNotEmpty &&
        const AccountRecoveryService().validateRecoveryPhrase(_words.text) &&
        password.length >= 8 &&
        password.length <= 128 &&
        password == _confirm.text;
  }

  @override
  Widget build(BuildContext context) {
    final isValid = _validInput;
    final t = AppLanguageService.instance.text;
    return Scaffold(
      appBar: AppBar(title: Text(t('recoveryScreenTitle'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Center(child: FenyvoBrandMark(size: 100)),
            const SizedBox(height: 12),
            const Center(
              child: Text(
                'FENYVO',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 3,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 5),
            const Center(
              child: Text(
                'SPARTA • FENIX',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 2.5,
                  color: Color(0xFFE6BE69),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(t('recoveryScreenDescription')),
            const SizedBox(height: 20),
            TextField(
              controller: _username,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: t('recoveryScreenUsername'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _words,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              maxLines: 3,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(labelText: t('recoveryScreenWords')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              obscureText: true,
              decoration: InputDecoration(
                labelText: t('recoveryScreenNewPassword'),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _confirm,
              enabled: !_busy,
              onChanged: (_) => setState(() {}),
              obscureText: true,
              decoration: InputDecoration(
                labelText: t('recoveryScreenConfirmPassword'),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: isValid && !_busy ? _startRecovery : null,
              child: Text(
                _busy ? t('recoveryScreenBusy') : t('recoveryScreenSubmit'),
              ),
            ),
            const SizedBox(height: 12),
            const SizedBox(height: 30),
            Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 650),
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: Text(
                  _brandExpanded ? t('recoveryScreenSecurityService') : 'СБF',
                  key: ValueKey(_brandExpanded),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFE6BE69),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_status != null)
              Card(
                color: const Color(0xFF7F1D1D),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _status!,
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
