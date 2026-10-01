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

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final initialUri = await _appLinks.getInitialLink();

      if (initialUri != null) {
        _handleUri(initialUri);
      }
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
    if (uri.scheme != 'https') return;
    if (uri.host.toLowerCase() != 'fenyvo.com') return;

    final segments = uri.pathSegments;

    if (segments.length < 2 || segments.first != 'u') {
      return;
    }

    final username = segments[1].trim();

    if (username.isEmpty) return;

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
