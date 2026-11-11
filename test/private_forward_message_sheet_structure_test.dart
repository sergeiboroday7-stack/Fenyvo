import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final chat = File('lib/screens/chat_screen.dart').readAsStringSync();
  final module = File('lib/widgets/private_forward_message_sheet.dart')
      .readAsStringSync();

  test('forwarding UI is extracted into a Dart part', () {
    expect(
      chat.contains("part '../widgets/private_forward_message_sheet.dart';"),
      isTrue,
    );
    expect(module.contains("part of '../screens/chat_screen.dart';"), isTrue);
    expect(
      module.contains(
        'Future<void> _forwardMessage(Map<String, dynamic> message) async',
      ),
      isTrue,
    );
    expect(
      chat.contains(
        'Future<void> _forwardMessage(Map<String, dynamic> message) async',
      ),
      isFalse,
    );
  });

  test('recipient selection and preview survive', () {
    for (final symbol in [
      'StorageService.getChatUsers',
      'StorageService.getAvatar',
      'StatefulBuilder(',
      'showModalBottomSheet<void>(',
      'selectedUsers',
      'commentController.dispose()',
      'searchController.dispose()',
      '_sendForwardedMessage(',
    ]) {
      expect(module.contains(symbol), isTrue, reason: symbol);
    }
  });

  test('sender remains in ChatScreen and not in UI module', () {
    expect(chat.contains('Future<void> _sendForwardedMessage({'), isTrue);
    expect(
      chat.substring(
        chat.indexOf('Future<void> _sendForwardedMessage({'),
        chat.indexOf('bool _canOfferLegacyMediaAccess('),
      ).contains(
        'encryptForE2ee: true',
      ),
      isTrue,
    );
    expect(module.contains('MediaTransferService.uploadFile('), isFalse);
    expect(module.contains('SocketService.instance.sendMessage('), isFalse);
    expect(RegExp(r'_ChatScreenState\._gold\b').allMatches(module).length, 9);
  });
}
