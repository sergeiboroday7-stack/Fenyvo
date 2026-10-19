class TurnCredentialService {
  TurnCredentialService._();

  static Map<String, dynamic>? _turn;

  static bool get hasTurn => _turn != null;

  static void configure(Map<String, dynamic>? turn) {
    if (turn == null) {
      _turn = null;
      return;
    }

    final urls = turn['urls'];
    final username = turn['username']?.toString().trim() ?? '';
    final credential = turn['credential']?.toString().trim() ?? '';
    if (urls is! List ||
        urls.isEmpty ||
        username.isEmpty ||
        credential.isEmpty) {
      _turn = null;
      return;
    }

    _turn = {
      'urls': urls.map((value) => value.toString()).toList(),
      'username': username,
      'credential': credential,
    };
  }

  static List<Map<String, dynamic>> get iceServers {
    final result = <Map<String, dynamic>>[
      {
        'urls': [
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
    ];
    final turn = _turn;
    if (turn != null) result.add(Map<String, dynamic>.from(turn));
    return result;
  }
}
