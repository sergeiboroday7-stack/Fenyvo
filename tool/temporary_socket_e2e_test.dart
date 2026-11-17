import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:spartan_chat_final/services/socket_service.dart';

const serverUrl = 'ws://127.0.0.1:8080';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final role = Platform.environment['FENYVO_TEST_ROLE']?.trim() ?? '';
  final username = Platform.environment['FENYVO_TEST_USER']?.trim() ?? '';
  final password = Platform.environment['FENYVO_TEST_PASSWORD'] ?? '';

  if (role != 'owner' && role != 'guest') {
    stderr.writeln('FAIL: invalid FENYVO_TEST_ROLE');
    exit(2);
  }

  if (username.isEmpty || password.isEmpty) {
    stderr.writeln('FAIL: missing credentials');
    exit(2);
  }

  runApp(
    MaterialApp(
      home: TemporarySocketE2ePage(
        role: role,
        username: username,
        password: password,
      ),
    ),
  );
}

class TemporarySocketE2ePage extends StatefulWidget {
  const TemporarySocketE2ePage({
    super.key,
    required this.role,
    required this.username,
    required this.password,
  });

  final String role;
  final String username;
  final String password;

  @override
  State<TemporarySocketE2ePage> createState() => _TemporarySocketE2ePageState();
}

class _TemporarySocketE2ePageState extends State<TemporarySocketE2ePage> {
  final SocketService socket = SocketService.instance;

  final Completer<void> loginDone = Completer<void>();
  final Completer<Map<String, dynamic>> joined =
      Completer<Map<String, dynamic>>();
  final Completer<Map<String, dynamic>> received =
      Completer<Map<String, dynamic>>();

  final tokenFile = File('tool/temporary_socket_e2e_token.txt');

  @override
  void initState() {
    super.initState();
    socket.addMessageHandler(_onMessage);
    unawaited(_run());
  }

  void _onMessage(Map<String, dynamic> message) {
    final type = message['type']?.toString() ?? '';
    final rawData = message['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};

    if (type == 'login_success' && !loginDone.isCompleted) {
      print('PASS: ${widget.role} login');
      loginDone.complete();
      return;
    }

    if (type == 'temporary_contact_joined' && !joined.isCompleted) {
      print(
        'PASS: ${widget.role} joined session '
        '${data['sessionId']} role=${data['role']}',
      );
      joined.complete(data);
      return;
    }

    if (type == 'temporary_message' && !received.isCompleted) {
      print(
        'PASS: ${widget.role} decrypted temporary message: '
        '${data['text']}',
      );
      received.complete(data);
      return;
    }

    if (type == 'temporary_message_error') {
      print('FAIL: temporary_message_error $data');
    }
  }

  Future<void> _run() async {
    try {
      final connected = await socket.connect(serverUrl);
      if (!connected) {
        throw StateError('WebSocket connection failed');
      }

      socket.login(widget.username, widget.password);

      await loginDone.future.timeout(const Duration(seconds: 10));

      if (widget.role == 'owner') {
        await _runOwner();
      } else {
        await _runGuest();
      }
    } catch (error, stack) {
      print('FAIL: ${widget.role}: $error');
      print(stack);
      exitCode = 1;
    }
  }

  Future<void> _runOwner() async {
    if (await tokenFile.exists()) {
      await tokenFile.delete();
    }

    final created = await socket.createTemporaryContact(
      durationMinutes: 60,
      allowMessages: true,
      allowCalls: false,
      allowFiles: false,
    );

    if (created == null || created.isEmpty) {
      throw StateError('temporary contact create failed');
    }

    if (created['success'] != true) {
      throw StateError('temporary contact rejected: ${created['reason']}');
    }

    final token = created['token']?.toString() ?? '';
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(token)) {
      throw StateError('invalid temporary token');
    }

    await tokenFile.writeAsString(token, flush: true);

    print('PASS: owner created fresh temporary contact');
    print('PASS: token saved without printing it');

    final joinedData = await joined.future.timeout(const Duration(seconds: 30));

    final sessionId = joinedData['sessionId']?.toString() ?? '';
    final role = joinedData['role']?.toString() ?? '';

    await Future<void>.delayed(const Duration(seconds: 2));

    final sent = await socket.sendTemporaryEncryptedMessage(
      sessionId: sessionId,
      role: role,
      text: 'FENYVO_TEMP_E2E_OK',
      messageId: 'temporary-e2e-test-1',
    );

    if (!sent) {
      throw StateError('encrypted temporary message was not sent');
    }

    print('PASS: owner sent encrypted temporary message');
    print('OWNER TEST: PASSED');
  }

  Future<void> _runGuest() async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));

    while (!await tokenFile.exists()) {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('token file was not created');
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    final token = (await tokenFile.readAsString()).trim();

    if (!socket.joinTemporaryContact(token)) {
      throw StateError('temporary contact join was not sent');
    }

    await joined.future.timeout(const Duration(seconds: 20));

    final message = await received.future.timeout(const Duration(seconds: 30));

    if (message['text'] != 'FENYVO_TEMP_E2E_OK') {
      throw StateError('decrypted plaintext mismatch');
    }

    if (message['e2ee'] != true ||
        message['e2eeVersion'] != 2 ||
        message['e2eeProtocol'] != 'signal') {
      throw StateError('temporary E2EE metadata mismatch');
    }

    print('GUEST TEST: PASSED');
  }

  @override
  void dispose() {
    socket.removeMessageHandler(_onMessage);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text('Temporary Socket E2E: ${widget.role}')),
    );
  }
}
