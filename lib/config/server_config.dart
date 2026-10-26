/// The server address is chosen while building the app and is not user-editable.
///
/// Local build default:
///   ws://192.168.0.117:8080
/// Public build example:
///   --dart-define=FENYVO_SERVER_URL=wss://chat.example.com/ws
abstract final class ServerConfig {
  static const String _legacyUrl = String.fromEnvironment(
    'SPARTAN_SERVER_URL',
    defaultValue: 'wss://fenyvo.com/ws',
  );

  static const String url = String.fromEnvironment(
    'FENYVO_SERVER_URL',
    defaultValue: _legacyUrl,
  );

  static Uri get websocketUri {
    final uri = Uri.parse(url);
    if ((uri.scheme != 'ws' && uri.scheme != 'wss') || uri.host.isEmpty) {
      throw const FormatException(
        'FENYVO_SERVER_URL должен быть корректным адресом ws:// или wss://',
      );
    }
    return uri;
  }
}
