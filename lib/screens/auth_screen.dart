import '../theme/spartan_theme.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/socket_service.dart';
import '../services/app_language_service.dart';
import 'chat_list_screen.dart';

const String serverIp = '192.168.0.117';
const String serverPort = '8080';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _usernameController = TextEditingController();

  final TextEditingController _passwordController = TextEditingController();

  final TextEditingController _ipController = TextEditingController(
    text: serverIp,
  );

  final TextEditingController _portController = TextEditingController(
    text: serverPort,
  );

  bool _isLoading = false;
  bool _isRegisterMode = false;
  bool _isAutoLogin = false;

  String _error = '';

  Timer? _loginTimeout;

  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();

    SocketService.instance.addMessageHandler(_handleMessage);

    _loadSavedUser();
  }

  @override
  void dispose() {
    _loginTimeout?.cancel();

    SocketService.instance.removeMessageHandler(_handleMessage);

    _usernameController.dispose();
    _passwordController.dispose();
    _ipController.dispose();
    _portController.dispose();

    super.dispose();
  }

  // ========================================
  // ЗАГРУЗКА СОХРАНЁННОГО ПОЛЬЗОВАТЕЛЯ
  // ========================================

  Future<void> _loadSavedUser() async {
    final prefs = await SharedPreferences.getInstance();

    if (!mounted) {
      return;
    }

    final username = prefs.getString('username') ?? '';

    final password = prefs.getString('password') ?? '';

    final ip = prefs.getString('ip') ?? serverIp;

    final port = prefs.getString('port') ?? serverPort;

    final loggedIn = prefs.getBool('logged_in') ?? false;

    _usernameController.text = username;
    _passwordController.text = password;
    _ipController.text = ip;
    _portController.text = port;

    if (loggedIn && username.isNotEmpty && password.isNotEmpty) {
      setState(() {
        _isAutoLogin = true;
        _isLoading = true;
        _error = '';
      });

      await _connectAndLogin();
    }
  }

  // ========================================
  // СООБЩЕНИЯ ОТ СЕРВЕРА
  // ========================================

  void _handleMessage(Map<String, dynamic> message) {
    if (!mounted || _isNavigating) {
      return;
    }

    final type = message['type']?.toString() ?? '';

    final rawData = message['data'];

    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};

    print('📩 AuthScreen получил: $type');

    if (type == 'connected') {
      print('🟢 Сервер подтвердил подключение');

      return;
    }

    if (type == 'login_success') {
      _loginTimeout?.cancel();

      _isNavigating = true;

      setState(() {
        _isLoading = false;
        _isAutoLogin = false;
        _error = '';
      });

      _saveUserAndOpenChat();

      return;
    }

    if (type == 'register_success') {
      _loginTimeout?.cancel();

      if (!mounted) {
        return;
      }

      setState(() {
        _isLoading = true;
        _isAutoLogin = false;
        _error = '';
      });

      _startLoginTimeout();

      SocketService.instance.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );

      return;
    }

    if (type == 'login_error' ||
        type == 'register_error' ||
        type == 'error' ||
        type == 'disconnected') {
      _loginTimeout?.cancel();

      final reason = data['reason']?.toString() ?? _getErrorText(type);

      setState(() {
        _isLoading = false;
        _isAutoLogin = false;
        _error = reason;
      });

      return;
    }
  }

  String _getErrorText(String type) {
    switch (type) {
      case 'login_error':
        return 'Не удалось выполнить вход';

      case 'register_error':
        return 'Ошибка регистрации';

      case 'disconnected':
        return 'Соединение с сервером потеряно';

      default:
        return 'Произошла ошибка';
    }
  }

  // ========================================
  // ТАЙМАУТ
  // ========================================

  void _startLoginTimeout() {
    _loginTimeout?.cancel();

    _loginTimeout = Timer(const Duration(seconds: 10), () {
      if (!mounted || _isNavigating) {
        return;
      }

      setState(() {
        _isLoading = false;
        _isAutoLogin = false;
        _error = 'Сервер не ответил. Проверьте подключение.';
      });
    });
  }

  // ========================================
  // СОХРАНЕНИЕ И ПЕРЕХОД
  // ========================================

  Future<void> _saveUserAndOpenChat() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('username', _usernameController.text.trim());

      await prefs.setString('password', _passwordController.text);

      await prefs.setString('ip', _ipController.text.trim());

      await prefs.setString('port', _portController.text.trim());

      await prefs.setBool('logged_in', true);

      print('💾 Пользователь сохранён');
    } catch (e) {
      print('⚠️ Ошибка сохранения пользователя: $e');
    }

    if (!mounted) {
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ChatListScreen()),
    );
  }

  // ========================================
  // ПОДКЛЮЧЕНИЕ И ВХОД
  // ========================================

  Future<void> _connectAndLogin() async {
    final username = _usernameController.text.trim();

    final password = _passwordController.text;

    final ip = _ipController.text.trim();

    final port = _portController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _stopLoadingWithError('Введите логин и пароль');

      return;
    }

    if (ip.isEmpty || port.isEmpty) {
      _stopLoadingWithError('Введите IP и порт сервера');

      return;
    }

    final url = 'ws://$ip:$port';

    try {
      print('🔌 Подключение к: $url');

      final connected = await SocketService.instance.connect(url);

      if (!mounted) {
        return;
      }

      if (!connected) {
        _stopLoadingWithError('Не удалось подключиться к серверу');

        return;
      }

      print('🔐 Отправляем логин: $username');

      _startLoginTimeout();

      SocketService.instance.login(username, password);
    } catch (e) {
      print('❌ Ошибка подключения: $e');

      _loginTimeout?.cancel();

      if (!mounted) {
        return;
      }

      _stopLoadingWithError('Не удалось подключиться к серверу');
    }
  }

  void _stopLoadingWithError(String error) {
    if (!mounted) {
      return;
    }

    setState(() {
      _isLoading = false;
      _isAutoLogin = false;
      _error = error;
    });
  }

  void _login() {
    if (_isLoading) {
      return;
    }

    setState(() {
      _isLoading = true;
      _isAutoLogin = false;
      _error = '';
    });

    _connectAndLogin();
  }

  // ========================================
  // РЕГИСТРАЦИЯ
  // ========================================

  Future<void> _register() async {
    if (_isLoading) {
      return;
    }

    final username = _usernameController.text.trim();

    final password = _passwordController.text;

    final ip = _ipController.text.trim();

    final port = _portController.text.trim();

    if (username.length < 3) {
      setState(() {
        _error = 'Логин должен содержать минимум 3 символа';
      });

      return;
    }

    if (password.length < 4) {
      setState(() {
        _error = 'Пароль должен содержать минимум 4 символа';
      });

      return;
    }

    if (ip.isEmpty || port.isEmpty) {
      setState(() {
        _error = 'Введите IP и порт сервера';
      });

      return;
    }

    setState(() {
      _isLoading = true;
      _isAutoLogin = false;
      _error = '';
    });

    final url = 'ws://$ip:$port';

    try {
      print('🆕 Подключение для регистрации: $url');

      final connected = await SocketService.instance.connect(url);

      if (!mounted) {
        return;
      }

      if (!connected) {
        _stopLoadingWithError('Не удалось подключиться к серверу');

        return;
      }

      _startLoginTimeout();

      SocketService.instance.register(username, password);
    } catch (e) {
      print('❌ Ошибка регистрации: $e');

      _loginTimeout?.cancel();

      _stopLoadingWithError('Не удалось подключиться к серверу');
    }
  }

  // ========================================
  // ПОЛЕ ВВОДА
  // ========================================

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: SpartanPalette.secondary),
      prefixIcon: Icon(icon, color: SpartanPalette.ink),
      filled: true,
      fillColor: SpartanPalette.surface.withValues(alpha: 0.62),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: SpartanPalette.ink.withValues(alpha: 0.35),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SpartanPalette.ink, width: 1.5),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: SpartanPalette.line),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  // ========================================
  // ЭКРАН
  // ========================================

  @override
  Widget build(BuildContext context) {
    final language = AppLanguageService.instance;
    return Scaffold(
      backgroundColor: SpartanPalette.canvas,
      resizeToAvoidBottomInset: true,

      body: Stack(
        fit: StackFit.expand,
        children: [
          // ==================================
          // ФОН SPARTA / FENIX
          // ==================================

          const ColoredBox(color: SpartanPalette.canvas),

          // ==================================
          // ЗАТЕМНЕНИЕ ДЛЯ ЧИТАЕМОСТИ
          // ==================================
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  SpartanPalette.canvas.withValues(alpha: 0.20),
                  SpartanPalette.canvas.withValues(alpha: 0.48),
                  SpartanPalette.canvas.withValues(alpha: 0.76),
                  SpartanPalette.canvas.withValues(alpha: 0.92),
                ],
                stops: const [0.0, 0.38, 0.72, 1.0],
              ),
            ),
          ),

          // ==================================
          // СОДЕРЖИМОЕ
          // ==================================
          SafeArea(
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 30),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      MediaQuery.of(context).size.height -
                      MediaQuery.of(context).padding.top -
                      MediaQuery.of(context).padding.bottom -
                      54,
                ),
                child: IntrinsicHeight(
                  child: Column(
                    children: [
                      // ========================
                      // ЛОГОТИП
                      // ========================

                      const SizedBox(height: 20),

                      Image.asset(
                        'assets/images/spartan_brand.png',
                        width: 80,
                        height: 80,
                        semanticLabel: 'SPARTAN',
                      ),

                      const SizedBox(height: 14),

                      const Text(
                        'SPARTAN CHAT',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: SpartanPalette.ink,
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 2.0,
                        ),
                      ),

                      const SizedBox(height: 5),

                      Text(
                        _isRegisterMode
                            ? language.text('create')
                            : language.text('welcome'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: SpartanPalette.secondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.4,
                        ),
                      ),

                      const SizedBox(height: 28),

                      // ========================
                      // ПАНЕЛЬ ВХОДА
                      // ========================
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: SpartanPalette.surface.withValues(alpha: 0.58),
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: SpartanPalette.ink.withValues(alpha: 0.30),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 24,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Text(
                              _isRegisterMode
                                  ? language.text('register')
                                  : language.text('login'),
                              style: const TextStyle(
                                color: SpartanPalette.ink,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),

                            const SizedBox(height: 20),

                            if (_isRegisterMode) ...[
                              DropdownButtonFormField<String>(
                                initialValue: language.code.value,
                                decoration: _inputDecoration(
                                  hint: language.text('language'),
                                  icon: Icons.language_rounded,
                                ),
                                dropdownColor: SpartanPalette.surface,
                                style: const TextStyle(
                                  color: SpartanPalette.ink,
                                ),
                                items: AppLanguageService.languages
                                    .map(
                                      (item) => DropdownMenuItem<String>(
                                        value: item.code,
                                        child: Text(
                                          '${item.flag}  ${item.label}',
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _isLoading
                                    ? null
                                    : (value) {
                                        if (value != null) {
                                          unawaited(language.select(value));
                                        }
                                      },
                              ),
                              const SizedBox(height: 13),
                            ],

                            TextField(
                              controller: _usernameController,
                              enabled: !_isLoading,
                              style: const TextStyle(color: SpartanPalette.ink),
                              textInputAction: TextInputAction.next,
                              decoration: _inputDecoration(
                                hint: 'Username',
                                icon: Icons.person_outline,
                              ),
                            ),

                            const SizedBox(height: 13),

                            TextField(
                              controller: _passwordController,
                              enabled: !_isLoading,
                              style: const TextStyle(color: SpartanPalette.ink),
                              obscureText: true,
                              textInputAction: TextInputAction.next,
                              decoration: _inputDecoration(
                                hint: 'Password',
                                icon: Icons.lock_outline,
                              ),
                            ),

                            const SizedBox(height: 13),

                            Row(
                              children: [
                                Expanded(
                                  flex: 3,
                                  child: TextField(
                                    controller: _ipController,
                                    enabled: !_isLoading,
                                    style: const TextStyle(
                                      color: SpartanPalette.ink,
                                      fontSize: 14,
                                    ),
                                    keyboardType: TextInputType.number,
                                    textInputAction: TextInputAction.next,
                                    decoration: _inputDecoration(
                                      hint: language.text('server'),
                                      icon: Icons.dns_outlined,
                                    ),
                                  ),
                                ),

                                const SizedBox(width: 10),

                                Expanded(
                                  flex: 2,
                                  child: TextField(
                                    controller: _portController,
                                    enabled: !_isLoading,
                                    style: const TextStyle(
                                      color: SpartanPalette.ink,
                                      fontSize: 14,
                                    ),
                                    keyboardType: TextInputType.number,
                                    textInputAction: TextInputAction.done,
                                    decoration: _inputDecoration(
                                      hint: language.text('port'),
                                      icon: Icons.settings_ethernet,
                                    ),
                                    onSubmitted: (_) {
                                      if (!_isLoading) {
                                        if (_isRegisterMode) {
                                          _register();
                                        } else {
                                          _login();
                                        }
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 18),

                            if (_error.isNotEmpty)
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 14),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.14),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.red.withValues(alpha: 0.45),
                                  ),
                                ),
                                child: Text(
                                  _error,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 13,
                                  ),
                                ),
                              ),

                            if (_isLoading)
                              Column(
                                children: [
                                  const CircularProgressIndicator(
                                    color: SpartanPalette.ink,
                                  ),

                                  const SizedBox(height: 15),

                                  Text(
                                    _isAutoLogin
                                        ? 'Автоматический вход...'
                                        : _isRegisterMode
                                        ? 'Регистрация...'
                                        : 'Подключение...',
                                    style: const TextStyle(
                                      color: SpartanPalette.secondary,
                                    ),
                                  ),
                                ],
                              )
                            else
                              Column(
                                children: [
                                  SizedBox(
                                    width: double.infinity,
                                    height: 54,
                                    child: ElevatedButton(
                                      onPressed: _isRegisterMode
                                          ? _register
                                          : _login,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: SpartanPalette.blue,
                                        foregroundColor: SpartanPalette.ink,
                                        elevation: 0,
                                        shadowColor: Colors.transparent,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                      ),
                                      child: Text(
                                        _isRegisterMode
                                            ? language.text('registerButton')
                                            : language.text('loginButton'),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                    ),
                                  ),

                                  const SizedBox(height: 8),

                                  TextButton(
                                    onPressed: () {
                                      setState(() {
                                        _isRegisterMode = !_isRegisterMode;

                                        _error = '';
                                      });
                                    },
                                    child: Text(
                                      _isRegisterMode
                                          ? 'Уже есть аккаунт? Войти'
                                          : 'Нет аккаунта? Регистрация',
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        color: SpartanPalette.ink,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),

                      const Spacer(),

                      const SizedBox(height: 20),

                      Text(
                        _isRegisterMode
                            ? 'SPARTA • FENIX • REGISTRATION'
                            : 'SPARTA • FENIX • SECURE CHAT',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: SpartanPalette.ink.withValues(alpha: 0.40),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),

                      const SizedBox(height: 6),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
