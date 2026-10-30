import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_visibility.dart';
import 'socket_service.dart';
import 'notification_service.dart';
import 'native_call_notification_language.dart';

@pragma('vm:entry-point')
Future<void> spartanBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp();
  await SystemCallService.handlePush(message.data);
}

/// OS incoming UI is separate from the authenticated WebRTC session.
/// Push carries a short-lived call capability, never SDP, passwords or API keys.
class SystemCallService {
  SystemCallService._();
  static final instance = SystemCallService._();
  static final _preferences = SharedPreferencesAsync();
  final Set<String> _ending = {};
  String? acceptedId;
  String? nativeId;
  void Function(String id)? onAccept;
  void Function(String id)? onEnd;
  void Function(String id)? onTimeout;
  void Function(String id)? onRemoteCancel;

  Future<void> initialize() async {
    if (!Platform.isAndroid) return;
    FirebaseMessaging.onBackgroundMessage(spartanBackgroundMessage);
    FlutterCallkitIncoming.onEvent.listen((event) async {
      if (event is CallEventActionCallAccept) {
        acceptedId = event.callKitParams.id;
        nativeId = acceptedId;
        onAccept?.call(acceptedId!);
      } else if (event is CallEventActionCallDecline) {
        if (!_ending.contains(event.callKitParams.id))
          onEnd?.call(event.callKitParams.id);
      } else if (event is CallEventActionCallEnded) {
        final id = event.callKitParams.id;
        if (!_ending.contains(id)) {
          final cancelled =
              await _preferences.getStringList('cancelled_calls') ?? <String>[];
          if (cancelled.contains(id)) {
            onRemoteCancel?.call(id);
          } else {
            onEnd?.call(id);
          }
        }
      } else if (event is CallEventActionCallTimeout) {
        onTimeout?.call(event.id);
      }
    }, onError: (_) => debugPrint('System call event unavailable'));
  }

  static Future<void> configure(String url, String user, int mediaPort) async {
    if (!Platform.isAndroid) return;
    final uri = Uri.parse(url);
    final isSecure = uri.scheme.toLowerCase() == 'wss';
    final endpoint = Uri(
      scheme: isSecure ? 'https' : 'http',
      host: uri.host,
      port: isSecure ? null : mediaPort,
    ).toString();
    await _preferences.setString('call_server', endpoint);
    await _preferences.setString('call_user', user);
  }

  static Future<void> clearAccount() async {
    if (!Platform.isAndroid) return;
    await _preferences.remove('call_user');
    await FlutterCallkitIncoming.endAllCalls();
  }

  static bool validInvite(Map<String, dynamic> data, int now) {
    final id = data['callId']?.toString() ?? '';
    final expires = int.tryParse('${data['expiresAt']}') ?? 0;
    return id.isNotEmpty &&
        id.length <= 100 &&
        expires > now &&
        expires <= now + 80000 &&
        (data['sender']?.toString().isNotEmpty ?? false);
  }

  static Future<void> handlePush(Map<String, dynamic> data) async {
    if (!Platform.isAndroid) return;
    final type = data['type'];
    if (type != 'call_invite' && type != 'call_cancel') return;
    final user = await _preferences.getString('call_user');
    if (user == null || user != data['to']) return;
    final id = data['callId']?.toString() ?? '';
    if (id.isEmpty || id.length > 100) return;
    if (type == 'call_cancel') {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      final unanswered = activeCalls
          .where((call) => call.id == id && !call.isAccepted)
          .toList();
      final cancelled =
          await _preferences.getStringList('cancelled_calls') ?? <String>[];
      cancelled.add(id);
      await _preferences.setStringList(
        'cancelled_calls',
        cancelled.reversed.take(32).toList().reversed.toList(),
      );
      // A delayed invite is also checked against live server state below.
      await FlutterCallkitIncoming.endCall(id);
      if (unanswered.isNotEmpty) {
        final call = unanswered.first;
        await showMissedCall(
          id: id,
          from:
              call.nameCaller ??
              '\u0421\u043e\u0431\u0435\u0441\u0435\u0434\u043d\u0438\u043a',
          video: call.type == 1,
        );
      }
      return;
    }
    await showIncoming(data);
  }

  static Future<void> showMissedCall({
    required String id,
    required String from,
    required bool video,
  }) async {
    try {
      if (Platform.isAndroid) {
        // The same call ID is used for push and socket delivery: no duplicate cards.
        final languageCode = await NativeCallNotificationLanguage.savedCode();
        await FlutterCallkitIncoming.showMissCallNotification(
          CallKitParams(
            id: id,
            nameCaller: from,
            appName: 'FENYVO',
            type: video ? 1 : 0,
            handle: NativeCallNotificationLanguage.forCode(
              video ? 'missedVideo' : 'missedAudio',
              languageCode,
            ),
            missedCallNotification: NotificationParams(
              showNotification: true,
              isShowCallback: false,
              subtitle: NativeCallNotificationLanguage.forCode(
                video ? 'missedVideo' : 'missedAudio',
                languageCode,
              ),
            ),
            android: AndroidParams(
              missedCallNotificationChannelName:
                  NativeCallNotificationLanguage.forCode(
                    'missedCallsChannel',
                    languageCode,
                  ),
            ),
          ),
        );
      } else if (Platform.isWindows) {
        await NotificationService.instance.showMissedCall(
          id: id,
          from: from,
          video: video,
        );
      }
    } catch (_) {
      debugPrint('Missed call notification unavailable');
    }
  }

  static Future<void> showIncoming(Map<String, dynamic> data) async {
    if (!Platform.isAndroid ||
        !validInvite(data, DateTime.now().millisecondsSinceEpoch))
      return;
    final id = data['callId'].toString();
    final token = data['callToken']?.toString() ?? '';
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(token)) return;
    final base = await _preferences.getString('call_server');
    final user = await _preferences.getString('call_user');
    if (base == null || user != data['to']) return;
    final endpoint = Uri.parse(base)
        .replace(path: '/calls/${Uri.encodeComponent(id)}');
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final request = await http
          .getUrl(endpoint)
          .timeout(const Duration(seconds: 4));
      request.headers.set('Authorization', 'Bearer $token');
      final response = await request.close().timeout(
        const Duration(seconds: 4),
      );
      if (response.statusCode != 200) return;
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 4));
      if (jsonDecode(body)['ringing'] != true) return;
    } catch (_) {
      debugPrint('Cannot validate incoming call with server');
      return;
    } finally {
      http.close(force: true);
    }
    final expires = int.parse('${data['expiresAt']}');
    final remaining = expires - DateTime.now().millisecondsSinceEpoch;
    if (remaining <= 0) return;
    final cancelled =
        await _preferences.getStringList('cancelled_calls') ?? <String>[];
    if (cancelled.contains(id)) return;
    final active = await FlutterCallkitIncoming.activeCalls();
    if (active.any((call) => call.id == id)) return;
    // Never cover an existing active call with a second native invitation.
    if (active.isNotEmpty) return;
    final avatar = endpoint
        .replace(path: '${endpoint.path}/avatar', queryParameters: {'t': token})
        .toString();
    final languageCode = await NativeCallNotificationLanguage.savedCode();

    await FlutterCallkitIncoming.showCallkitIncoming(
      CallKitParams(
        id: id,
        nameCaller: data['sender'].toString(),
        appName: 'FENYVO',
        handle: NativeCallNotificationLanguage.forCode(
          data['video'].toString() == 'true'
              ? 'incomingVideo'
              : 'incomingAudio',
          languageCode,
        ),
        avatar: avatar,
        type: data['video'].toString() == 'true' ? 1 : 0,
        duration: remaining,
        extra: {
          'endpoint': endpoint.toString(),
          'callToken': token,
          'expiresAt': expires,
          'to': user,
        },
        missedCallNotification: NotificationParams(
          showNotification: true,
          isShowCallback: false,
          subtitle: NativeCallNotificationLanguage.forCode(
            data['video'].toString() == 'true' ? 'missedVideo' : 'missedAudio',
            languageCode,
          ),
        ),
        callingNotification: NotificationParams(
          showNotification: true,
          isShowCallback: true,
          callbackText: NativeCallNotificationLanguage.forCode(
            'endCall',
            languageCode,
          ),
          subtitle: NativeCallNotificationLanguage.forCode(
            'callFenyvo',
            languageCode,
          ),
        ),
        android: AndroidParams(
          isCustomNotification: true,
          isShowLogo: false,
          isShowCallID: true,
          ringtonePath: 'spartan_phoenix_call',
          backgroundColor: '#0A0A0A',
          backgroundUrl: avatar,
          actionColor: '#D4AF37',
          textColor: '#FFFFFF',
          incomingCallNotificationChannelName:
              NativeCallNotificationLanguage.forCode(
                'callsChannel',
                languageCode,
              ),
          missedCallNotificationChannelName:
              NativeCallNotificationLanguage.forCode(
                'missedCallsChannel',
                languageCode,
              ),
          textAccept: NativeCallNotificationLanguage.forCode(
            'accept',
            languageCode,
          ),
          textDecline: NativeCallNotificationLanguage.forCode(
            'decline',
            languageCode,
          ),
          isShowFullLockedScreen: true,
        ),
      ),
    );
  }

  Future<void> restorePending() async {
    if (!Platform.isAndroid) return;
    try {
      final active = await FlutterCallkitIncoming.activeCalls();
      for (final call in active) {
        final expires = int.tryParse('${call.extra?['expiresAt']}') ?? 0;
        if (call.extra?['to'] != SocketService.instance.currentUser ||
            (expires <= DateTime.now().millisecondsSinceEpoch &&
                call.id != nativeId)) {
          await end(call.id);
          continue;
        }
        nativeId = call.id;
        if (call.isAccepted) {
          acceptedId = call.id;
          onAccept?.call(call.id);
        }
      }
    } catch (_) {
      debugPrint('Cannot restore system incoming call');
    }
  }

  Future<bool> isNative(String id) async {
    if (!Platform.isAndroid) return false;
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      if (calls.any((call) => call.id == id)) {
        nativeId = id;
        return true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> silence(String id) async {
    if (!Platform.isAndroid) return;
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      for (final call in calls.where((c) => c.id == id)) {
        nativeId = id;
        if (!call.isAccepted) {
          await const MethodChannel('spartan_chat/call_window')
              .invokeMethod<void>('accept', {'callId': id});
        }
        await FlutterCallkitIncoming.hideCallkitIncoming(call);
      }
    } catch (_) {}
  }

  Future<void> connected(String id) async {
    if (!Platform.isAndroid || nativeId != id) return;
    try {
      await FlutterCallkitIncoming.setCallConnected(id);
    } catch (_) {}
  }

  Future<void> end(String? id) async {
    if (!Platform.isAndroid || id == null) return;
    _ending.add(id);
    if (acceptedId == id) acceptedId = null;
    if (nativeId == id) nativeId = null;
    try {
      await FlutterCallkitIncoming.endCall(id);
    } catch (_) {}
    Timer(const Duration(seconds: 3), () => _ending.remove(id));
  }

  Future<void> requestPermissions(BuildContext context) async {
    if (!Platform.isAndroid) return;
    try {
      if ((await FlutterCallkitIncoming.activeCalls()).isNotEmpty) return;
      final allowed = await FlutterCallkitIncoming.canUseFullScreenIntent();
      if (allowed == true || !context.mounted) return;
      final asked =
          await _preferences.getBool('call_fullscreen_explained') ?? false;
      if (asked || !context.mounted) return;
      await _preferences.setBool('call_fullscreen_explained', true);
      final open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Полноэкранные звонки'),
          content: const Text(
            'Разрешите FENYVO показывать входящий звонок поверх заблокированного экрана. Без этого Android может показывать только уведомление.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Позже'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Настроить'),
            ),
          ],
        ),
      );
      if (open == true)
        await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (_) {
      debugPrint('Full-screen call permission unavailable');
    }
  }

  Future<void> foregroundPush(Map<String, dynamic> data) async {
    if (!AppVisibility.instance.foreground || data['type'] == 'call_cancel') {
      await handlePush(data);
    } else if (data['type'] == 'call_invite') {
      SocketService.instance.requestPendingCall();
    }
  }
}
