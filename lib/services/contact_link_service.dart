import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

class ContactLinkService extends ChangeNotifier {
  ContactLinkService._();

  static final ContactLinkService instance = ContactLinkService._();

  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;
  String? _pendingUsername;
  bool _initialized = false;

  String? get pendingUsername => _pendingUsername;

  static String? usernameFromUri(Uri uri) {
    if (uri.scheme.toLowerCase() != 'https' ||
        uri.host.toLowerCase() != 'fenyvo.com' ||
        uri.pathSegments.length != 2 ||
        uri.pathSegments.first.toLowerCase() != 'u') {
      return null;
    }

    final username = uri.pathSegments[1].trim();
    final validUsername = RegExp(r'^[a-zA-Zа-яА-ЯёЁ0-9_]{3,30}$')
        .hasMatch(username);
    return validUsername ? username : null;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) _handleUri(initialUri);
    } catch (error) {
      debugPrint('Contact link initial error: $error');
    }

    _subscription = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (Object error) {
        debugPrint('Contact link stream error: $error');
      },
    );
  }

  void _handleUri(Uri uri) {
    final username = usernameFromUri(uri);
    if (username == null) return;
    _pendingUsername = username;
    notifyListeners();
  }

  String? takePendingUsername() {
    final username = _pendingUsername;
    _pendingUsername = null;
    return username;
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    super.dispose();
  }
}
