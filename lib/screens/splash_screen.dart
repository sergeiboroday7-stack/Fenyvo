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

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _orbitController;
  String _statusText = 'Подготовка приложения...';

  bool _isLoading = true;

  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();

    SocketService.instance.addMessageHandler(_handleSocketMessage);

    _initialize();
  }

  @override
  void dispose() {
    _orbitController.dispose();
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
      backgroundColor: const Color(0xFF091827),
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -.35),
                  radius: 1.2,
                  colors: [
                    Color(0xFF1D3852),
                    Color(0xFF102238),
                    Color(0xFF091827),
                  ],
                ),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 25),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 190,
                      height: 190,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          RotationTransition(
                            turns: _orbitController,
                            child: SizedBox(
                              width: 170,
                              height: 170,
                              child: CustomPaint(
                                painter: const _SplashRingPainter(),
                              ),
                            ),
                          ),
                          Container(
                            width: 122,
                            height: 122,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFFE6BE69)
                                      .withValues(alpha: .16),
                                  blurRadius: 36,
                                ),
                              ],
                            ),
                            child: Image.asset(
                              'assets/images/spartan_brand.png',
                              semanticLabel: 'FENYVO',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'FENYVO',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        letterSpacing: 3,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'SPARTA • FENIX',
                      style: TextStyle(
                        color: Color(0xFFE6BE69),
                        fontSize: 11,
                        letterSpacing: 3,
                      ),
                    ),
                    const SizedBox(height: 44),
                    if (_isLoading)
                      const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.7,
                          color: Color(0xFFE6BE69),
                        ),
                      ),
                    const SizedBox(height: 20),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Text(
                        _statusText,
                        key: ValueKey<String>(_statusText),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFFA6B6C8),
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SplashRingPainter extends CustomPainter {
  const _SplashRingPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * .47;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = const Color(0xFF7B96AE).withValues(alpha: .29)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -.25,
      1.3,
      false,
      Paint()
        ..color = const Color(0xFFE6BE69)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(
      Offset(center.dx + radius, center.dy),
      3.5,
      Paint()..color = const Color(0xFFFFDF97),
    );
  }

  @override
  bool shouldRepaint(covariant _SplashRingPainter oldDelegate) => false;
}
