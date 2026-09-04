import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'dart:convert';

class SocketService {
  static final SocketService _instance = SocketService._internal();
  static SocketService get instance => _instance;
  
  SocketService._internal();
  
  WebSocketChannel? _channel;
  final List<Function(Map<String, dynamic>)> _listeners = [];
  bool _isConnected = false;
  String? _currentUser;
  
  void addListener(Function(Map<String, dynamic>) listener) {
    _listeners.add(listener);
  }
  
  void removeListener(Function(Map<String, dynamic>) listener) {
    _listeners.remove(listener);
  }
  
  void _notifyListeners(Map<String, dynamic> data) {
    for (var listener in _listeners) {
      listener(data);
    }
  }
  
  Future<bool> connect(String ip, String port) async {
    final url = 'ws://$ip:$port';
    print("🟢 Connecting to $url");
    
    try {
      _channel = IOWebSocketChannel.connect(Uri.parse(url));
      
      _channel!.stream.listen(
        (message) {
          try {
            final data = jsonDecode(message);
            print("📨 RECV: $data");
            _notifyListeners(data);
          } catch (e) {}
        },
        onDone: () {
          print("⚫ Connection closed");
          _isConnected = false;
          _notifyListeners({'action': 'disconnected'});
        },
        onError: (error) {
          print("🔴 Error: $error");
          _isConnected = false;
          _notifyListeners({'action': 'error', 'message': error.toString()});
        },
      );
      
      _isConnected = true;
      return true;
    } catch (e) {
      print("❌ Connection failed: $e");
      _isConnected = false;
      return false;
    }
  }
  
  void send(Map<String, dynamic> data) {
    if (_channel != null && _isConnected) {
      final json = jsonEncode(data);
      print("📤 SEND: $json");
      _channel!.sink.add(json);
    } else {
      print("⚠️ Not connected, can't send: $data");
    }
  }
  
  void login(String username) {
    _currentUser = username;
    send({'action': 'login', 'username': username});
  }
  
  void sendMessage(String to, String text) {
    send({'action': 'message', 'to': to, 'text': text});
  }
  
  void sendTyping(String to) {
    send({'action': 'typing', 'to': to});
  }
  
  void getUsers() {
    send({'action': 'get_users'});
  }
  
  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
  }
  
  bool get isConnected => _isConnected;
  String? get currentUser => _currentUser;
}