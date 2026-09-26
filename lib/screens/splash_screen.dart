import '../theme/spartan_theme.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/socket_service.dart';
import '../services/credential_storage_service.dart';
import '../config/server_config.dart';
import 'auth_screen.dart';
import 'chat_list_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _statusText = 'Подготовка приложения...';

  bool _isLoading = true;

  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();

    SocketService.instance.addMessageHandler(_handleSocketMessage);

    _initialize();
  }

  @override
  void dispose() {
    SocketService.instance.removeMessageHandler(_handleSocketMessage);

    super.dispose();
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();

    final username = prefs.getString('username');

    final password = await CredentialStorageService.instance.readPassword(
      prefs,
    );

    final loggedIn = prefs.getBool('logged_in') ?? false;

    if (!loggedIn ||
        username == null ||
        username.isEmpty ||
        password == null ||
        password.isEmpty) {
      await _goToAuth();

      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _statusText = 'Подключение к серверу...';
    });

    final url = ServerConfig.websocketUri.toString();

    final connected = await SocketService.instance.connect(url);

    if (!mounted) {
      return;
    }

    if (!connected) {
      await _showErrorAndGoToAuth('Не удалось подключиться к серверу');

      return;
    }

    setState(() {
      _statusText = 'Автоматический вход...';
    });

    SocketService.instance.login(username, password);
  }

  void _handleSocketMessage(Map<String, dynamic> message) {
    final type = message['type']?.toString() ?? '';

    final rawData = message['data'];

    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};

    if (type == 'login_success') {
      final username = data['username']?.toString() ?? '';

      if (username.isNotEmpty) {
        SocketService.instance.currentUser = username;
      }

      _goToChatList();

      return;
    }

    if (type == 'login_error') {
      final reason = data['reason']?.toString() ?? 'Ошибка входа';

      _showErrorAndGoToAuth(reason);

      return;
    }

    if (type == 'disconnected') {
      final reason =
          data['reason']?.toString() ?? 'Соединение с сервером потеряно';

      _showErrorAndGoToAuth(reason);
    }
  }

  Future<void> _showErrorAndGoToAuth(String message) async {
    if (!mounted || _hasNavigated) {
      return;
    }

    setState(() {
      _statusText = message;
      _isLoading = false;
    });

    await Future.delayed(const Duration(seconds: 2));

    await _goToAuth();
  }

  Future<void> _goToAuth() async {
    if (!mounted || _hasNavigated) {
      return;
    }

    _hasNavigated = true;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const AuthScreen()),
    );
  }

  void _goToChatList() {
    if (!mounted || _hasNavigated) {
      return;
    }

    _hasNavigated = true;

    setState(() {
      _statusText = 'Вход выполнен!';
    });

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ChatListScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpartanPalette.canvas,

      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.shield, size: 80, color: SpartanPalette.ink),

            const SizedBox(height: 20),

            const Text(
              'FENYVO',
              style: TextStyle(
                color: SpartanPalette.ink,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),

            const SizedBox(height: 40),

            if (_isLoading)
              const CircularProgressIndicator(color: SpartanPalette.ink),

            const SizedBox(height: 20),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Text(
                _statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: SpartanPalette.secondary,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
