import '../widgets/fenyvo_brand_mark.dart';
import 'account_recovery_screen.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/socket_service.dart';
import '../services/app_language_service.dart';
import '../services/credential_storage_service.dart';
import '../config/server_config.dart';
import 'chat_list_screen.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _usernameController = TextEditingController();

  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();
  bool _passwordVisible = false;
  bool _confirmPasswordVisible = false;

  bool _isLoading = false;
  bool _isRegisterMode = false;
  bool _termsAccepted = false;
  bool _ageConfirmed = false;
  bool _isAutoLogin = false;
  bool _showWelcome = false;

  String _error = '';

  Timer? _loginTimeout;

  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();

    SocketService.instance.addMessageHandler(_handleMessage);
    AppLanguageService.instance.code.addListener(_onLanguageChanged);

    _loadSavedUser();
  }

  @override
  void dispose() {
    _loginTimeout?.cancel();

    SocketService.instance.removeMessageHandler(_handleMessage);
    AppLanguageService.instance.code.removeListener(_onLanguageChanged);

    _usernameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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

    final password =
        await CredentialStorageService.instance.readPassword(prefs) ?? '';

    final loggedIn = prefs.getBool('logged_in') ?? false;

    _usernameController.text = username;
    _passwordController.text = password;
    if (loggedIn && username.isNotEmpty && password.isNotEmpty) {
      setState(() {
        _isAutoLogin = true;
        _isLoading = true;
        _error = '';
      });

      await _connectAndLogin();
    } else {
      // A first-time or signed-out user chooses registration or sign-in.
      setState(() => _showWelcome = true);
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
        return AppLanguageService.instance.text('authLoginFailed');

      case 'register_error':
        return AppLanguageService.instance.text('authRegistrationFailed');

      case 'disconnected':
        return AppLanguageService.instance.text('authDisconnected');

      default:
        return AppLanguageService.instance.text('authGeneralError');
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
        _error = AppLanguageService.instance.text('authServerTimeout');
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

      await CredentialStorageService.instance.savePassword(
        _passwordController.text,
        prefs,
      );

      // Old builds stored the private local server address. It is no longer
      // user-configurable and should not remain in application preferences.
      await prefs.remove('ip');
      await prefs.remove('port');

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

    if (username.isEmpty || password.isEmpty) {
      _stopLoadingWithError(
        AppLanguageService.instance.text('authEnterCredentials'),
      );

      return;
    }

    final url = ServerConfig.websocketUri.toString();

    try {
      print('🔌 Подключение к: $url');

      final connected = await SocketService.instance.connect(url);

      if (!mounted) {
        return;
      }

      if (!connected) {
        _stopLoadingWithError(
          AppLanguageService.instance.text('authConnectionFailed'),
        );

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

      _stopLoadingWithError(
        AppLanguageService.instance.text('authConnectionFailed'),
      );
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

    if (username.length < 3) {
      setState(() {
        _error = AppLanguageService.instance.text('authUsernameTooShort');
      });

      return;
    }

    if (password.length < 8) {
      setState(() {
        _error = AppLanguageService.instance.text('authPasswordTooShort');
      });

      return;
    }

    if (password.length > 128) {
      setState(() {
        _error = AppLanguageService.instance.text('authPasswordTooLong');
      });

      return;
    }

    if (password != _confirmPasswordController.text) {
      setState(() {
        _error = AppLanguageService.instance.text('authPasswordMismatch');
      });
      return;
    }

    if (!_termsAccepted) {
      setState(
        () => _error = AppLanguageService.instance.text('authAcceptTermsError'),
      );
      return;
    }

    if (!_ageConfirmed) {
      setState(
        () => _error = AppLanguageService.instance.text('authConfirmAgeError'),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _isAutoLogin = false;
      _error = '';
    });

    final url = ServerConfig.websocketUri.toString();

    try {
      print('🆕 Подключение для регистрации: $url');

      final connected = await SocketService.instance.connect(url);

      if (!mounted) {
        return;
      }

      if (!connected) {
        _stopLoadingWithError(
          AppLanguageService.instance.text('authConnectionFailed'),
        );

        return;
      }

      _startLoginTimeout();

      SocketService.instance.register(
        username,
        password,
        termsAccepted: _termsAccepted,
        ageConfirmed: _ageConfirmed,
      );
    } catch (e) {
      print('❌ Ошибка регистрации: $e');

      _loginTimeout?.cancel();

      _stopLoadingWithError(
        AppLanguageService.instance.text('authConnectionFailed'),
      );
    }
  }

  // ========================================
  // ПОЛЕ ВВОДА
  // ========================================

  static const _navy = Color(0xFF091827);
  static const _gold = Color(0xFFE6BE69);
  static const _muted = Color(0xFFA6B6C8);
  static const _field = Color(0xFF192C43);

  void _goWelcome() => setState(() {
    _showWelcome = true;
    _isRegisterMode = false;
    _error = '';
    _passwordVisible = false;
    _confirmPasswordVisible = false;
    _termsAccepted = false;
    _ageConfirmed = false;
  });

  void _openMode(bool register) => setState(() {
    _showWelcome = false;
    _isRegisterMode = register;
    _error = '';
    _passwordVisible = false;
    _confirmPasswordVisible = false;
    _termsAccepted = false;
    _ageConfirmed = false;
  });

  Widget _panel({required Widget child, bool compact = false}) => Container(
    padding: EdgeInsets.all(compact ? 18 : 22),
    decoration: BoxDecoration(
      color: const Color(0xFF14263A).withValues(alpha: .92),
      borderRadius: BorderRadius.circular(28),
      border: Border.all(color: _gold.withValues(alpha: .27)),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: .26),
          blurRadius: 34,
          offset: const Offset(0, 16),
        ),
        BoxShadow(color: _gold.withValues(alpha: .035), blurRadius: 27),
      ],
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );

  InputDecoration _premiumInput(String hint, IconData icon, {Widget? suffix}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: _muted),
        prefixIcon: Icon(icon, color: _gold, size: 21),
        suffixIcon: suffix,
        filled: true,
        fillColor: _field,
        contentPadding: const EdgeInsets.symmetric(
          vertical: 18,
          horizontal: 16,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: const Color(0xFF69809A).withValues(alpha: .36),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: _gold, width: 1.6),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFF3A4A5B)),
        ),
      );

  Widget _primaryAction(
    String label,
    VoidCallback onTap, {
    IconData icon = Icons.arrow_forward_rounded,
  }) => SizedBox(
    height: 56,
    width: double.infinity,
    child: ElevatedButton(
      onPressed: _isLoading ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: _gold,
        foregroundColor: _navy,
        disabledBackgroundColor: _gold.withValues(alpha: .42),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
        elevation: 4,
        shadowColor: _gold.withValues(alpha: .36),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Icon(icon, size: 21),
        ],
      ),
    ),
  );

  Widget _welcomeBody() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        AppLanguageService.instance.text('authTagline'),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: _gold,
          fontSize: 11,
          letterSpacing: 2.1,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 15),
      Text(
        AppLanguageService.instance.text('authHero'),
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 27,
          height: 1.22,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 14),
      Text(
        AppLanguageService.instance.text('authDescription'),
        textAlign: TextAlign.center,
        style: TextStyle(color: _muted, fontSize: 13, height: 1.5),
      ),
      const SizedBox(height: 32),
      _primaryAction(
        AppLanguageService.instance.text('authCreateAccount'),
        () => _openMode(true),
      ),
      const SizedBox(height: 12),
      SizedBox(
        height: 54,
        child: OutlinedButton.icon(
          onPressed: () => _openMode(false),
          icon: const Icon(Icons.login_rounded, size: 20),
          label: Text(
            AppLanguageService.instance.text('authHaveAccount'),
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(color: _gold.withValues(alpha: .5)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
    ],
  );

  void _onLanguageChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Widget _formBody() {
    final language = AppLanguageService.instance;
    final registration = _isRegisterMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: _isLoading ? null : _goWelcome,
              tooltip: language.text('authBack'),
              icon: const Icon(Icons.arrow_back_rounded, color: _gold),
            ),
            Expanded(
              child: Text(
                registration
                    ? language.text('create')
                    : language.text('login').toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: _gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          registration
              ? AppLanguageService.instance.text('authStartConversation')
              : AppLanguageService.instance.text('authWelcomeBack'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 25,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          registration
              ? AppLanguageService.instance.text('authRegisterHint')
              : AppLanguageService.instance.text('authLoginHint'),
          textAlign: TextAlign.center,
          style: const TextStyle(color: _muted, fontSize: 13),
        ),
        const SizedBox(height: 19),
        if (!registration) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _isLoading
                  ? null
                  : () async {
                      final recoveredUser = await Navigator.of(context)
                          .push<String>(
                            MaterialPageRoute<String>(
                              builder: (_) => const AccountRecoveryScreen(),
                            ),
                          );
                      if (!context.mounted || recoveredUser == null) return;
                      setState(() {
                        _usernameController.text = recoveredUser;
                        _passwordController.clear();
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          backgroundColor: const Color(0xFF166534),
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          duration: const Duration(seconds: 5),
                          content: Row(
                            children: [
                              Icon(
                                Icons.check_circle_outline,
                                color: Colors.white,
                              ),
                              SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  AppLanguageService.instance.text(
                                    'authRecoverySuccess',
                                  ),
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
              child: Text(
                AppLanguageService.instance.text('authForgotPassword'),
              ),
            ),
          ),
        ],

        if (registration) ...[
          DropdownButtonFormField<String>(
            initialValue: language.code.value,
            isExpanded: true,
            decoration: _premiumInput(
              language.text('language'),
              Icons.language_rounded,
            ),
            dropdownColor: const Color(0xFF14263A),
            style: const TextStyle(color: Colors.white),
            items: AppLanguageService.languages
                .map(
                  (item) => DropdownMenuItem<String>(
                    value: item.code,
                    child: Text(
                      '${item.flag}  ${item.label}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: _isLoading
                ? null
                : (value) {
                    if (value != null) unawaited(language.select(value));
                  },
          ),
          const SizedBox(height: 13),
        ],
        TextField(
          controller: _usernameController,
          enabled: !_isLoading,
          autocorrect: false,
          style: const TextStyle(color: Colors.white),
          textInputAction: TextInputAction.next,
          decoration: _premiumInput(
            language.text('authUsername'),
            Icons.alternate_email_rounded,
          ),
        ),
        const SizedBox(height: 13),
        TextField(
          controller: _passwordController,
          enabled: !_isLoading,
          obscureText: !_passwordVisible,
          style: const TextStyle(color: Colors.white),
          onChanged: registration ? (_) => setState(() {}) : null,
          textInputAction: registration
              ? TextInputAction.next
              : TextInputAction.done,
          onSubmitted: (_) {
            if (!registration && !_isLoading) _login();
          },
          decoration: _premiumInput(
            language.text('authPassword'),
            Icons.lock_outline_rounded,
            suffix: IconButton(
              tooltip: _passwordVisible
                  ? language.text('authHidePassword')
                  : language.text('authShowPassword'),
              onPressed: () =>
                  setState(() => _passwordVisible = !_passwordVisible),
              icon: Icon(
                _passwordVisible
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: _muted,
              ),
            ),
          ),
        ),
        if (registration) ...[
          const SizedBox(height: 12),
          Text(
            language.text('authPasswordHint'),
            style: TextStyle(color: _muted, fontSize: 12, height: 1.4),
          ),
          AnimatedSize(
            duration: MediaQuery.of(context).disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 300),
            curve: Curves.easeInOutCubic,
            alignment: Alignment.topCenter,
            child: _passwordController.text.length >= 8
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 14),
                      TextField(
                        controller: _confirmPasswordController,
                        enabled: !_isLoading,
                        obscureText: !_confirmPasswordVisible,
                        style: const TextStyle(color: Colors.white),
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() {}),
                        onSubmitted: (_) {
                          if (!_isLoading) _register();
                        },
                        decoration: _premiumInput(
                          language.text('authConfirmPassword'),
                          Icons.verified_user_outlined,
                          suffix: IconButton(
                            tooltip: _confirmPasswordVisible
                                ? language.text('authHidePassword')
                                : language.text('authShowPassword'),
                            onPressed: () => setState(
                              () => _confirmPasswordVisible =
                                  !_confirmPasswordVisible,
                            ),
                            icon: Icon(
                              _confirmPasswordVisible
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: _muted,
                            ),
                          ),
                        ),
                      ),
                      if (_confirmPasswordController.text.isNotEmpty) ...[
                        const SizedBox(height: 9),
                        Row(
                          children: [
                            Icon(
                              _confirmPasswordController.text ==
                                      _passwordController.text
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.info_outline_rounded,
                              color:
                                  _confirmPasswordController.text ==
                                      _passwordController.text
                                  ? const Color(0xFF8CDBAF)
                                  : _gold,
                              size: 17,
                            ),
                            const SizedBox(width: 7),
                            Expanded(
                              child: Text(
                                _confirmPasswordController.text ==
                                        _passwordController.text
                                    ? language.text('authPasswordsMatch')
                                    : language.text('authPasswordsDiffer'),
                                style: TextStyle(
                                  color:
                                      _confirmPasswordController.text ==
                                          _passwordController.text
                                      ? const Color(0xFF8CDBAF)
                                      : _muted,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
        if (registration) ...[
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _termsAccepted,
            onChanged: _isLoading
                ? null
                : (v) => setState(() => _termsAccepted = v ?? false),
            title: Text(
              AppLanguageService.instance.text('authTermsConsent'),
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeColor: _gold,
          ),
          CheckboxListTile(
            value: _ageConfirmed,
            onChanged: _isLoading
                ? null
                : (v) => setState(() => _ageConfirmed = v ?? false),
            title: Text(
              AppLanguageService.instance.text('authAgeConsent'),
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
            activeColor: _gold,
          ),
        ],
        if (registration)
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () async {
                        await launchUrl(
                          Uri.parse('https://fenyvo.com/terms.html'),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                child: Text(AppLanguageService.instance.text('authTermsLink')),
              ),
              TextButton(
                onPressed: _isLoading
                    ? null
                    : () async {
                        await launchUrl(
                          Uri.parse('https://fenyvo.com/privacy.html'),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                child: Text(
                  AppLanguageService.instance.text('authPrivacyLink'),
                ),
              ),
            ],
          ),
        if (_error.isNotEmpty) ...[
          const SizedBox(height: 15),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF682B36).withValues(alpha: .55),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFFFB7BF), fontSize: 12),
            ),
          ),
        ],
        const SizedBox(height: 18),
        if (_isLoading)
          Column(
            children: [
              const CircularProgressIndicator(color: _gold),
              const SizedBox(height: 12),
              Text(
                _isAutoLogin
                    ? AppLanguageService.instance.text('authAutoLogin')
                    : registration
                    ? AppLanguageService.instance.text('authRegistering')
                    : AppLanguageService.instance.text('authConnecting'),
                style: const TextStyle(color: _muted),
              ),
            ],
          )
        else
          _primaryAction(
            registration
                ? language.text('registerButton')
                : language.text('loginButton'),
            registration ? _register : _login,
            icon: registration
                ? Icons.person_add_alt_1_rounded
                : Icons.login_rounded,
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final view = MediaQuery.of(context);
    final reducedMotion = view.disableAnimations || view.accessibleNavigation;
    final welcome = _showWelcome && !_isLoading;
    final usableHeight =
        view.size.height -
        view.padding.top -
        view.padding.bottom -
        view.viewInsets.bottom;
    final compact = usableHeight < 770;
    final veryCompact = usableHeight < 635;
    final logoSize = welcome
        ? (veryCompact
              ? 116.0
              : compact
              ? 140.0
              : 164.0)
        : (veryCompact
              ? 64.0
              : compact
              ? 82.0
              : 104.0);
    return Scaffold(
      backgroundColor: _navy,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -.68),
                  radius: 1.26,
                  colors: [Color(0xFF1F3953), Color(0xFF0C1E30), _navy],
                ),
              ),
            ),
          ),
          Positioned(
            top: -135,
            right: -125,
            child: IgnorePointer(
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [_gold.withValues(alpha: .085), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(20, veryCompact ? 8 : 16, 20, 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: 460,
                      minHeight:
                          (constraints.maxHeight - (veryCompact ? 28 : 36))
                              .clamp(0.0, double.infinity),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedSize(
                          duration: reducedMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 250),
                          curve: Curves.easeOutCubic,
                          child: FenyvoBrandMark(size: logoSize),
                        ),
                        SizedBox(height: veryCompact ? 5 : 9),
                        Text(
                          'FENYVO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: welcome ? 30 : (veryCompact ? 22 : 26),
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3,
                          ),
                        ),
                        SizedBox(height: veryCompact ? 3 : 5),
                        Text(
                          'SPARTA • FENIX',
                          style: TextStyle(
                            color: _gold,
                            fontSize: veryCompact ? 9 : 10,
                            letterSpacing: 2.7,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(
                          height: welcome
                              ? (compact ? 16 : 26)
                              : (veryCompact
                                    ? 10
                                    : compact
                                    ? 14
                                    : 20),
                        ),
                        AnimatedSwitcher(
                          duration: reducedMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 330),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, .035),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: KeyedSubtree(
                            key: ValueKey<String>(
                              welcome
                                  ? 'welcome'
                                  : _isRegisterMode
                                  ? 'register'
                                  : 'login',
                            ),
                            child: _panel(
                              compact: !welcome && compact,
                              child: welcome ? _welcomeBody() : _formBody(),
                            ),
                          ),
                        ),
                        SizedBox(height: veryCompact ? 12 : 19),
                        Text(
                          AppLanguageService.instance.text(
                            'authRecoveryFooter',
                          ),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _muted,
                            fontSize: 11,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'SPARTA • FENIX • SECURE CHAT',
                          style: TextStyle(
                            color: _gold.withValues(alpha: .62),
                            fontSize: 10,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ],
                    ),
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
