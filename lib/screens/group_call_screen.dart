import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/call_service.dart';
import '../services/group_call_service.dart';
import '../services/group_call_state.dart';
import '../services/media_transfer_service.dart';
import '../services/socket_service.dart';
import '../services/storage_service.dart';
import '../theme/spartan_theme.dart';
import 'chat_screen.dart';
import 'group_chat_screen.dart';

final Map<String, ImageProvider?> _stableCallAvatars =
    <String, ImageProvider?>{};

ImageProvider? _stableCallAvatar(String username) {
  if (_stableCallAvatars.containsKey(username)) {
    return _stableCallAvatars[username];
  }
  ImageProvider? avatar;
  try {
    final raw = StorageService.getAvatar(username);
    if (raw != null && raw.isNotEmpty) {
      avatar = MemoryImage(
        base64Decode(raw.contains(',') ? raw.split(',').last : raw),
      );
    }
  } catch (_) {}
  _stableCallAvatars[username] = avatar;
  return avatar;
}

class GroupCallScreen extends StatefulWidget {
  const GroupCallScreen({super.key, this.service});

  final GroupCallService? service;

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  final TextEditingController _chatController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  AudioRecorder? _audioRecorder;

  AudioRecorder get _recorder => _audioRecorder ??= AudioRecorder();
  bool _recordingVoice = false;
  DateTime? _voiceStartedAt;
  bool? _callMicWasEnabledBeforeVoice;
  final FocusNode _chatFocusNode = FocusNode();
  bool _chatOpen = false;
  bool _emojiPanelOpen = false;

  String? _activeCommunicationUser;
  Map<String, dynamic>? _activeCommunicationState;
  final ValueNotifier<Map<String, dynamic>?> _communicationStateNotifier =
      ValueNotifier<Map<String, dynamic>?>(null);
  final ValueNotifier<Map<String, dynamic>?> _profileNotifier =
      ValueNotifier<Map<String, dynamic>?>(null);
  final Map<String, ImageProvider?> _callAvatarCache =
      <String, ImageProvider?>{};
  final Set<String> _visibleJoinRequests = <String>{};
  bool _enteredCall = false;
  bool _closingScreen = false;

  void _handleCallLifecycle() {
    if (!mounted || _closingScreen) return;
    final call = widget.service ?? GroupCallService.instance;
    if (call.phase != GroupCallPhase.idle) {
      _enteredCall = true;
      return;
    }
    if (!_enteredCall) return;
    _closingScreen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final navigator = Navigator.of(context);
      if (navigator.canPop()) navigator.pop();
    });
  }

  Future<void> _leaveToGroupChat(GroupCallService call) async {
    if (_closingScreen) return;

    final targetGroupId = call.groupId?.trim() ?? '';
    final targetGroupName = call.groupName;
    final endForAll = call.isOwner;

    _closingScreen = true;

    unawaited(call.leave(endForAll: endForAll));

    if (!mounted) return;

    final navigator = Navigator.of(context);

    // Обычно экран звонка открыт поверх уже существующего группового чата.
    if (navigator.canPop()) {
      navigator.pop();
      return;
    }

    // Запасной вариант, если экран звонка оказался корневым.
    if (targetGroupId.isNotEmpty) {
      await navigator.pushReplacement(
        MaterialPageRoute(
          builder: (_) => GroupChatScreen(
            group: <String, dynamic>{
              'id': targetGroupId,
              'name': targetGroupName,
            },
          ),
        ),
      );
    }
  }

  ImageProvider? _callAvatarFor(String username) {
    final user = username.trim();
    if (user.isEmpty) return null;

    final key = user.toLowerCase();
    if (_callAvatarCache.containsKey(key)) {
      return _callAvatarCache[key];
    }

    ImageProvider? image;
    final raw = StorageService.getAvatar(user);
    if (raw != null && raw.isNotEmpty) {
      try {
        image = MemoryImage(
          base64Decode(raw.contains(',') ? raw.split(',').last : raw),
        );
      } catch (_) {}
    }

    _callAvatarCache[key] = image;
    return image;
  }

  final List<Map<String, dynamic>> _callChatMessages = <Map<String, dynamic>>[];
  String? _loadedCallChatGroupId;
  final Map<String, Timer> _callChatMessageTimers = <String, Timer>{};

  Future<void> _sendCommunicationRequest(
    BuildContext sheetContext,
    String username,
  ) async {
    final controller = TextEditingController();
    final message = await showDialog<String>(
      context: sheetContext,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Запрос на общение'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 300,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Напишите одно короткое сообщение…',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(dialogContext, text);
            },
            child: const Text('Отправить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || message == null || message.trim().isEmpty) return;
    SocketService.instance.requestCommunication(username, message: message);
  }

  Future<void> _showCallUserCard(String username) async {
    final user = username.trim();
    if (user.isEmpty) return;

    final currentUser = SocketService.instance.currentUser?.trim() ?? '';
    final isSelf = user.toLowerCase() == currentUser.toLowerCase();
    final call = widget.service ?? GroupCallService.instance;
    GroupCallMember? selectedMember;
    for (final member in call.current?.members ?? const <GroupCallMember>[]) {
      if (member.user.toLowerCase() == user.toLowerCase()) {
        selectedMember = member;
        break;
      }
    }
    final roleLabel = selectedMember?.isHost == true
        ? 'Ведущий'
        : selectedMember?.isModerator == true
        ? 'Модератор'
        : 'Участник звонка';
    final participantCount = call.current?.members.length ?? 0;

    _activeCommunicationUser = user;
    _activeCommunicationState = isSelf
        ? <String, dynamic>{'contact': user, 'status': 'self'}
        : SocketService.instance.communicationState(user);
    _communicationStateNotifier.value = _activeCommunicationState;

    if (!isSelf) {
      SocketService.instance.getCommunicationState(user);
    }
    _profileNotifier.value = SocketService.instance.userProfile(user);
    SocketService.instance.getUserProfile(user);

    SocketService.instance.requestAvatar(user);
    final rawAvatar = StorageService.getAvatar(user);
    ImageProvider? avatar;
    if (rawAvatar != null && rawAvatar.isNotEmpty) {
      try {
        avatar = MemoryImage(base64Decode(rawAvatar));
      } catch (_) {}
    }

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (sheetContext) => SafeArea(
        child: Container(
          width: double.infinity,
          margin: EdgeInsets.only(
            left: 8,
            right: 8,
            top: MediaQuery.sizeOf(sheetContext).height * 0.28,
            bottom: 8,
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          decoration: BoxDecoration(
            color: const Color(0xF5181C23),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white12),
            boxShadow: const [
              BoxShadow(
                color: Colors.black54,
                blurRadius: 28,
                offset: Offset(0, -8),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Spacer(),
                    Container(
                      width: 52,
                      height: 5,
                      decoration: BoxDecoration(
                        color: Colors.white30,
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                    const Spacer(),
                    IconButton.filledTonal(
                      tooltip: 'Закрыть карточку',
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: SpartanPalette.surface,
                      backgroundImage: avatar,
                      child: avatar == null
                          ? Text(
                              user[0].toUpperCase(),
                              style: const TextStyle(
                                color: SpartanPalette.gold,
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            user,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          const Row(
                            children: [
                              Icon(
                                Icons.circle,
                                size: 13,
                                color: Color(0xFF20E867),
                              ),
                              SizedBox(width: 7),
                              Text(
                                'В сети',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 15,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 7),
                          Text(
                            roleLabel,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: const Row(
                    children: [
                      Expanded(
                        child: _ProfileTab(label: 'Информация', active: true),
                      ),
                      Expanded(child: _ProfileTab(label: 'Медиа')),
                      Expanded(child: _ProfileTab(label: 'Общие группы')),
                      Expanded(child: _ProfileTab(label: 'В звонке')),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                if (selectedMember?.isViewer == true &&
                    (call.isHost || call.isModerator)) ...[
                  _CallUserAction(
                    icon: Icons.video_call_rounded,
                    label: 'Пригласить в видеочат',
                    subtitle: 'Отправить приглашение на сцену',
                    accent: const Color(0xFF8B68FF),
                    onTap: () => Navigator.pop(sheetContext, 'stage-invite'),
                  ),
                  const SizedBox(height: 10),
                ],
                ValueListenableBuilder<Map<String, dynamic>?>(
                  valueListenable: _profileNotifier,
                  builder: (context, profile, _) => Column(
                    children: [
                      _ProfileInfoRow(
                        icon: Icons.badge_rounded,
                        label: 'Имя в чате',
                        value: user,
                      ),
                      _ProfileInfoRow(
                        icon: Icons.info_outline_rounded,
                        label: 'О себе',
                        value:
                            profile?['about']?.toString().trim().isNotEmpty ==
                                true
                            ? profile!['about'].toString()
                            : 'Не указано',
                      ),
                      _ProfileInfoRow(
                        icon: Icons.location_on_rounded,
                        label: 'Регион',
                        value:
                            profile?['region']?.toString().trim().isNotEmpty ==
                                true
                            ? profile!['region'].toString()
                            : 'Не указано',
                      ),
                      _ProfileInfoRow(
                        icon: Icons.groups_rounded,
                        label: 'Участников в звонке',
                        value: '$participantCount',
                      ),
                      _ProfileInfoRow(
                        icon: Icons.verified_user_rounded,
                        label: 'Роль',
                        value: roleLabel,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                ValueListenableBuilder<Map<String, dynamic>?>(
                  valueListenable: _communicationStateNotifier,
                  builder: (context, state, _) {
                    final status = state?['status']?.toString() ?? 'loading';
                    final incoming = state?['incoming'] == true;
                    final outgoing = state?['outgoing'] == true;

                    if (isSelf || status == 'self') {
                      return const SizedBox.shrink();
                    }

                    if (status == 'accepted') {
                      return LayoutBuilder(
                        builder: (context, constraints) {
                          final width = (constraints.maxWidth - 10) / 2;
                          return Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: [
                              SizedBox(
                                width: width,
                                child: _CallUserAction(
                                  icon: Icons.chat_bubble_rounded,
                                  label: 'Написать',
                                  subtitle: 'Личное сообщение',
                                  accent: const Color(0xFF4A91FF),
                                  onTap: () =>
                                      Navigator.pop(sheetContext, 'chat'),
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: _CallUserAction(
                                  icon: Icons.call_rounded,
                                  label: 'Аудиозвонок',
                                  subtitle: 'Позвонить сейчас',
                                  accent: const Color(0xFF20C768),
                                  onTap: () =>
                                      Navigator.pop(sheetContext, 'audio'),
                                ),
                              ),
                              SizedBox(
                                width: width,
                                child: _CallUserAction(
                                  icon: Icons.videocam_rounded,
                                  label: 'Видеозвонок',
                                  subtitle: 'Начать звонок',
                                  accent: const Color(0xFF8B68FF),
                                  onTap: () =>
                                      Navigator.pop(sheetContext, 'video'),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    }

                    if (status == 'pending' && incoming) {
                      final requestMessage =
                          state?['message']?.toString().trim() ?? '';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (requestMessage.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Text(
                                'Причина обращения:\n$requestMessage',
                                style: const TextStyle(color: Colors.white70),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          Row(
                            children: [
                              Expanded(
                                child: _CallUserAction(
                                  icon: Icons.close_rounded,
                                  label: 'Отклонить',
                                  onTap: () {
                                    SocketService.instance
                                        .respondCommunicationRequest(
                                          user,
                                          accepted: false,
                                        );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _CallUserAction(
                                  icon: Icons.check_rounded,
                                  label: 'Принять',
                                  onTap: () {
                                    SocketService.instance
                                        .respondCommunicationRequest(
                                          user,
                                          accepted: true,
                                        );
                                  },
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    }

                    if (status == 'pending' && outgoing) {
                      return const _CallUserAction(
                        icon: Icons.hourglass_top_rounded,
                        label: 'Запрос отправлен',
                        onTap: null,
                      );
                    }

                    if (status == 'loading') {
                      return const _CallUserAction(
                        icon: Icons.sync_rounded,
                        label: 'Проверяем связь...',
                        onTap: null,
                      );
                    }

                    return _CallUserAction(
                      icon: Icons.person_add_alt_1_rounded,
                      label: 'Запросить связь',
                      subtitle: 'Отправить одно сообщение',
                      accent: const Color(0xFF4A91FF),
                      onTap: () =>
                          _sendCommunicationRequest(sheetContext, user),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (!mounted || action == null) return;

    if (action == 'stage-invite') {
      call.inviteViewer(user);
      return;
    }

    if (action == 'chat') {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => ChatScreen(targetUser: user)));
      return;
    }

    if (action == 'audio' || action == 'video') {
      await CallService.instance.startCall(
        peer: user,
        video: action == 'video',
      );
    }
  }

  void _toggleChat() {
    setState(() {
      _chatOpen = !_chatOpen;
    });

    if (_chatOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _chatFocusNode.requestFocus();
        }
      });
    } else {
      _chatFocusNode.unfocus();
    }
  }

  void _pinCallMessage(GroupCallService call, Map<String, dynamic> message) {
    call.pinMessage(Map<String, dynamic>.from(message));
  }

  void _unpinCallMessage(GroupCallService call) {
    call.pinMessage(null);
  }

  void _sendChatMessage(GroupCallService call) {
    final text = _chatController.text.trim();
    final groupId = call.groupId?.trim() ?? '';

    if (text.isEmpty || groupId.isEmpty) return;

    SocketService.instance.sendGroupMessage(
      groupId,
      text,
      callId: call.current?.id,
    );
    _chatController.clear();
    _chatFocusNode.requestFocus();
  }

  Future<void> _startVoiceRecording(GroupCallService call) async {
    if (_recordingVoice) return;

    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Нет разрешения на микрофон')),
          );
        }
        return;
      }

      final micWasEnabled = call.microphoneEnabled;
      _callMicWasEnabledBeforeVoice = micWasEnabled;

      if (micWasEnabled) {
        call.setMicrophoneEnabled(false);
      }

      try {
        final temp = await getTemporaryDirectory();
        final path =
            '${temp.path}${Platform.pathSeparator}spartan_group_call_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';

        await _recorder.start(
          const RecordConfig(
            encoder: AudioEncoder.aacLc,
            bitRate: 96000,
            sampleRate: 44100,
          ),
          path: path,
        );
      } catch (_) {
        if (micWasEnabled) {
          call.setMicrophoneEnabled(true);
        }
        _callMicWasEnabledBeforeVoice = null;
        rethrow;
      }

      if (!mounted) return;

      setState(() {
        _recordingVoice = true;
        _voiceStartedAt = DateTime.now();
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Не удалось начать запись: $error')),
      );
    }
  }

  Future<void> _finishVoiceRecording(GroupCallService call) async {
    if (!_recordingVoice) return;

    final started = _voiceStartedAt;
    final restoreMic = _callMicWasEnabledBeforeVoice == true;

    String? path;

    try {
      path = await _recorder.stop();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось остановить запись: $error')),
        );
      }
    } finally {
      if (restoreMic) {
        call.setMicrophoneEnabled(true);
      }

      _callMicWasEnabledBeforeVoice = null;

      if (mounted) {
        setState(() {
          _recordingVoice = false;
          _voiceStartedAt = null;
        });
      } else {
        _recordingVoice = false;
        _voiceStartedAt = null;
      }
    }

    final durationMs = started == null
        ? 0
        : DateTime.now().difference(started).inMilliseconds;

    if (path == null || path.trim().isEmpty || durationMs < 300) {
      return;
    }

    final groupId = call.groupId?.trim() ?? '';
    if (groupId.isEmpty) return;

    final file = File(path);
    if (!await file.exists()) return;

    try {
      if (!SocketService.instance.isConnected) {
        throw Exception('Нет соединения с сервером');
      }

      if (!MediaTransferService.isReady) {
        throw Exception('Медиа-сервер не готов. Перезайдите в аккаунт.');
      }

      final fileName = path.split(Platform.pathSeparator).last;

      final upload = await MediaTransferService.uploadFile(
        path: path,
        fileName: fileName,
        mimeType: 'audio/mp4',
        messageType: 'voice',
        maxBytes: 20 * 1024 * 1024,
      );

      SocketService.instance.sendGroupMediaMessage(
        groupId,
        messageType: 'voice',
        mediaId: upload.mediaId,
        fileName: upload.fileName,
        fileSize: upload.fileSize,
        mimeType: upload.mimeType,
        text: '🎙️ Голосовое сообщение',
        voiceDurationMs: durationMs,
        callId: call.current?.id,
      );
      if (mounted) {
        _chatFocusNode.requestFocus();
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось отправить голосовое: $error')),
        );
      }
    } finally {
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  String _callBasename(String path) {
    final parts = path.replaceAll('\\', '/').split('/');
    return parts.isEmpty ? path : parts.last;
  }

  String _callSafeFileName(String name) {
    final clean = name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();

    return clean.isEmpty
        ? 'spartan_${DateTime.now().millisecondsSinceEpoch}.bin'
        : clean;
  }

  String _callMimeFromName(String name, String fallback) {
    final lower = name.toLowerCase();

    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.txt')) return 'text/plain';

    return fallback;
  }

  void _callMediaSnack(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<bool> _sendCallMediaFile(
    GroupCallService call, {
    required String messageType,
    required String path,
    required String fileName,
    required String mimeType,
    required String text,
    required int maxBytes,
  }) async {
    final groupId = call.groupId?.trim() ?? '';

    if (groupId.isEmpty) {
      _callMediaSnack('Группа звонка не найдена');
      return false;
    }

    if (!SocketService.instance.isConnected) {
      _callMediaSnack('Нет соединения с сервером');
      return false;
    }

    if (!MediaTransferService.isReady) {
      _callMediaSnack('Медиа-сервер не готов. Перезайдите в аккаунт.');
      return false;
    }

    try {
      final upload = await MediaTransferService.uploadFile(
        path: path,
        fileName: _callSafeFileName(fileName),
        mimeType: mimeType,
        messageType: messageType,
        maxBytes: maxBytes,
      );

      SocketService.instance.sendGroupMediaMessage(
        groupId,
        messageType: messageType,
        mediaId: upload.mediaId,
        fileName: upload.fileName,
        fileSize: upload.fileSize,
        mimeType: upload.mimeType,
        text: text,
        callId: call.current?.id,
      );

      if (mounted) {
        _chatFocusNode.requestFocus();
      }

      return true;
    } catch (error) {
      _callMediaSnack('Не удалось отправить файл: $error');
      return false;
    }
  }

  Future<void> _pickCallImage(GroupCallService call) async {
    try {
      final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 82,
      );

      if (picked == null) return;

      await _sendCallMediaFile(
        call,
        messageType: 'image',
        path: picked.path,
        fileName: _callBasename(picked.path),
        mimeType: _callMimeFromName(picked.path, 'image/jpeg'),
        text: '📷 Фото',
        maxBytes: 100 * 1024 * 1024,
      );
    } catch (error) {
      _callMediaSnack('Не удалось выбрать фото: $error');
    }
  }

  Future<void> _pickCallVideo(GroupCallService call) async {
    try {
      final picked = await _imagePicker.pickVideo(source: ImageSource.gallery);

      if (picked == null) return;

      await _sendCallMediaFile(
        call,
        messageType: 'video',
        path: picked.path,
        fileName: _callBasename(picked.path),
        mimeType: _callMimeFromName(picked.path, 'video/mp4'),
        text: '🎬 Видео',
        maxBytes: 1024 * 1024 * 1024,
      );
    } catch (error) {
      _callMediaSnack('Не удалось выбрать видео: $error');
    }
  }

  Future<void> _pickCallFile(GroupCallService call) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: false,
        withData: false,
      );

      if (result == null || result.files.isEmpty) return;

      final picked = result.files.single;
      final path = picked.path?.trim() ?? '';

      if (path.isEmpty) {
        _callMediaSnack('Не удалось получить путь к файлу');
        return;
      }

      final name = picked.name.trim().isEmpty ? 'file.bin' : picked.name.trim();

      final mime = _callMimeFromName(name, 'application/octet-stream');

      final isVideo = mime.startsWith('video/');

      await _sendCallMediaFile(
        call,
        messageType: isVideo ? 'video' : 'file',
        path: path,
        fileName: name,
        mimeType: mime,
        text: isVideo ? '🎬 Видео' : '📎 $name',
        maxBytes: isVideo ? 1024 * 1024 * 1024 : 512 * 1024 * 1024,
      );
    } catch (error) {
      _callMediaSnack('Не удалось выбрать файл: $error');
    }
  }

  void _handleCommunicationMessage(Map<String, dynamic> msg) {
    if (!mounted) return;

    final type = msg['type']?.toString() ?? '';
    if (type != 'communication_state' &&
        type != 'communication_request' &&
        type != 'communication_request_status' &&
        type != 'communication_request_response') {
      return;
    }

    final rawData = msg['data'];
    if (rawData is! Map) return;
    final data = Map<String, dynamic>.from(rawData);

    final activeUser = _activeCommunicationUser?.trim() ?? '';
    if (activeUser.isEmpty) return;

    final me = SocketService.instance.currentUser?.trim().toLowerCase() ?? '';
    final contact = data['contact']?.toString().trim() ?? '';
    final from = data['from']?.toString().trim() ?? '';
    final to = data['to']?.toString().trim() ?? '';

    String peer = contact;
    if (peer.isEmpty && type == 'communication_request_status') {
      peer = to;
    }
    if (peer.isEmpty) {
      peer = from.toLowerCase() == me ? to : from;
    }

    if (peer.toLowerCase() != activeUser.toLowerCase()) return;

    setState(() {
      _activeCommunicationState =
          SocketService.instance.communicationState(activeUser) ??
          Map<String, dynamic>.from(data);
      _communicationStateNotifier.value = _activeCommunicationState;
    });
  }

  void _handleProfileMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    final type = msg['type']?.toString() ?? '';
    if (type != 'user_profile' && type != 'user_profile_updated') return;
    final rawData = msg['data'];
    if (rawData is! Map) return;
    final data = Map<String, dynamic>.from(rawData);
    final activeUser = _activeCommunicationUser?.trim() ?? '';
    if ((data['username']?.toString().trim() ?? '').toLowerCase() !=
        activeUser.toLowerCase()) {
      return;
    }
    _profileNotifier.value = data;
  }

  void _handleCallChatMessage(Map<String, dynamic> msg) {
    if (!mounted) return;

    final type = msg['type']?.toString() ?? '';
    if (type != 'group_message' && type != 'group_messages') return;

    final rawData = msg['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : Map<String, dynamic>.from(msg);

    final call = widget.service ?? GroupCallService.instance;
    final activeGroupId = call.groupId?.trim() ?? '';
    final incomingGroupId = data['groupId']?.toString().trim() ?? '';

    if (activeGroupId.isEmpty || incomingGroupId != activeGroupId) return;
    if (type == 'group_message' && data['scope'] != 'group_call') return;

    if (type == 'group_messages') {
      final rawMessages = data['messages'];
      if (rawMessages is! List) return;
      final byId = <String, Map<String, dynamic>>{
        for (final message in _callChatMessages)
          message['id'].toString(): message,
      };
      for (final rawMessage in rawMessages.whereType<Map>()) {
        final message = Map<String, dynamic>.from(rawMessage);
        final messageId = message['id']?.toString().trim() ?? '';
        if (messageId.isNotEmpty) byId[messageId] = message;
      }
      final merged = byId.values.toList()
        ..sort(
          (a, b) => (a['time']?.toString() ?? '').compareTo(
            b['time']?.toString() ?? '',
          ),
        );
      setState(() {
        _callChatMessages
          ..clear()
          ..addAll(
            merged.length > 50 ? merged.sublist(merged.length - 50) : merged,
          );
      });
      return;
    }

    final id = data['id']?.toString().trim() ?? '';
    if (id.isEmpty) return;

    final alreadyExists = _callChatMessages.any(
      (message) => message['id']?.toString().trim() == id,
    );

    if (!alreadyExists) {
      setState(() {
        _callChatMessages.add(data);

        if (_callChatMessages.length > 50) {
          final removed = _callChatMessages.removeAt(0);
          final removedId = removed['id']?.toString().trim() ?? '';
          _callChatMessageTimers.remove(removedId)?.cancel();
        }
      });
    }
  }

  void _handleJoinRequestMessage(Map<String, dynamic> msg) {
    if (!mounted) return;
    final type = msg['type']?.toString() ?? '';
    if (type != 'group_call_join_request' &&
        type != 'group_call_stage_invite') {
      return;
    }
    final rawData = msg['data'];
    if (rawData is! Map) return;
    final data = Map<String, dynamic>.from(rawData);
    if (type == 'group_call_stage_invite') {
      final by = data['by']?.toString().trim() ?? 'Ведущий';
      final call = widget.service ?? GroupCallService.instance;
      if (!call.isViewer || data['callId'] != call.current?.id) return;
      final key = '${data['callId']}::stage-invite';
      if (!_visibleJoinRequests.add(key)) return;
      unawaited(() async {
        final withVideo = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Приглашение в видеочат'),
            content: Text('$by приглашает вас выйти на сцену.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Отклонить'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(dialogContext, false),
                icon: const Icon(Icons.mic_rounded),
                label: const Text('Без камеры'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(dialogContext, true),
                icon: const Icon(Icons.videocam_rounded),
                label: const Text('С камерой'),
              ),
            ],
          ),
        );
        _visibleJoinRequests.remove(key);
        if (mounted && withVideo != null) {
          await call.acceptStageInvite(withVideo: withVideo);
        } else {
          call.declineStageInvite();
        }
      }());
      return;
    }
    final user = data['user']?.toString().trim() ?? '';
    final callId = data['callId']?.toString().trim() ?? '';
    final call = widget.service ?? GroupCallService.instance;
    if (user.isEmpty ||
        callId != call.current?.id ||
        (!call.isHost && !call.isModerator)) {
      return;
    }
    final key = '$callId::$user';
    if (!_visibleJoinRequests.add(key)) return;
    unawaited(() async {
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Запрос на подключение'),
          content: Text('$user хочет войти в групповой звонок'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отклонить'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.login_rounded),
              label: const Text('Разрешить'),
            ),
          ],
        ),
      );
      _visibleJoinRequests.remove(key);
      if (mounted) {
        call.respondToJoinRequest(user, accepted: accepted == true);
      }
    }());
  }

  void _ensureCallChatHistory(GroupCallService call) {
    final groupId = call.groupId?.trim() ?? '';
    if (groupId.isEmpty || groupId == _loadedCallChatGroupId) return;
    _loadedCallChatGroupId = groupId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        SocketService.instance.getGroupMessages(
          groupId,
          limit: 50,
          callId: call.current?.id,
        );
      }
    });
  }

  Future<void> _showParticipants(
    BuildContext context,
    GroupCallService call,
    List<GroupCallMember> members,
  ) async {
    final stage = members.where((member) => !member.isViewer).toList();
    final viewers = members.where((member) => member.isViewer).toList();
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            ListTile(
              title: Text(
                'На сцене · ${stage.length}/4',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            for (final member in stage)
              ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                title: Text(member.user),
                subtitle: Text(
                  member.isHost
                      ? 'Ведущий'
                      : member.isModerator
                      ? 'Модератор'
                      : 'Участник',
                ),
                trailing: Icon(
                  member.videoEnabled
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_showCallUserCard(member.user));
                },
              ),
            ListTile(
              title: Text(
                'Смотрят · ${viewers.length}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            if (viewers.isEmpty)
              const ListTile(
                leading: Icon(Icons.visibility_outlined),
                title: Text('Пока нет зрителей'),
              ),
            for (final member in viewers)
              ListTile(
                leading: const CircleAvatar(
                  child: Icon(Icons.visibility_rounded),
                ),
                title: Text(member.user),
                subtitle: const Text('Смотрит и пишет в чате'),
                trailing: call.isHost || call.isModerator
                    ? IconButton(
                        tooltip: 'Пригласить в видеочат',
                        icon: const Icon(Icons.video_call_rounded),
                        onPressed: () {
                          call.inviteViewer(member.user);
                          Navigator.pop(sheetContext);
                        },
                      )
                    : null,
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(_showCallUserCard(member.user));
                },
              ),
          ],
        ),
      ),
    );
  }

  bool _handleWindowsTypeToCallChat(KeyEvent event) {
    if (!Platform.isWindows ||
        !mounted ||
        event is! KeyDownEvent ||
        _recordingVoice) {
      return false;
    }

    final keyboard = HardwareKeyboard.instance;

    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return false;
    }

    if (_chatFocusNode.hasFocus) {
      return false;
    }

    final focusedWidget = FocusManager.instance.primaryFocus?.context?.widget;

    if (focusedWidget is EditableText) {
      return false;
    }

    final character = event.character;

    if (character == null || character.isEmpty) {
      return false;
    }

    if (character.runes.any((rune) => rune < 0x20 || rune == 0x7F)) {
      return false;
    }

    final value = _chatController.value;
    final selection = value.selection.isValid
        ? value.selection
        : TextSelection.collapsed(offset: value.text.length);

    final start = selection.start < 0
        ? value.text.length
        : selection.start > value.text.length
        ? value.text.length
        : selection.start;

    final end = selection.end < 0
        ? start
        : selection.end > value.text.length
        ? value.text.length
        : selection.end;

    final newText = value.text.replaceRange(start, end, character);
    final newOffset = start + character.length;

    _chatController.value = value.copyWith(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
      composing: TextRange.empty,
    );

    setState(() {
      _chatOpen = true;
      _emojiPanelOpen = false;
    });

    _chatFocusNode.requestFocus();
    return true;
  }

  Future<void> _setWakelock(bool enabled) async {
    try {
      if (enabled) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {
      // Wakelock is optional; the call must continue if the platform
      // implementation is unavailable.
    }
  }

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) {
      HardwareKeyboard.instance.addHandler(_handleWindowsTypeToCallChat);
    }
    final call = widget.service ?? GroupCallService.instance;
    _enteredCall = call.phase != GroupCallPhase.idle;
    call.addListener(_handleCallLifecycle);
    SocketService.instance.addMessageHandler(_handleCallChatMessage);
    SocketService.instance.addMessageHandler(_handleCommunicationMessage);
    SocketService.instance.addMessageHandler(_handleProfileMessage);
    SocketService.instance.addMessageHandler(_handleJoinRequestMessage);
    unawaited(_setWakelock(true));
  }

  @override
  void dispose() {
    if (Platform.isWindows) {
      HardwareKeyboard.instance.removeHandler(_handleWindowsTypeToCallChat);
    }
    (widget.service ?? GroupCallService.instance).removeListener(
      _handleCallLifecycle,
    );
    SocketService.instance.removeMessageHandler(_handleCallChatMessage);
    SocketService.instance.removeMessageHandler(_handleCommunicationMessage);
    SocketService.instance.removeMessageHandler(_handleProfileMessage);
    SocketService.instance.removeMessageHandler(_handleJoinRequestMessage);

    for (final timer in _callChatMessageTimers.values) {
      timer.cancel();
    }
    _callChatMessageTimers.clear();

    _communicationStateNotifier.dispose();
    _profileNotifier.dispose();
    _chatController.dispose();
    _chatFocusNode.dispose();
    final recorder = _audioRecorder;
    if (recorder != null) {
      unawaited(recorder.dispose());
    }
    unawaited(_setWakelock(false));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.service ?? GroupCallService.instance;
    _ensureCallChatHistory(call);

    return AnimatedBuilder(
      animation: call,
      builder: (context, _) {
        final invited = call.phase == GroupCallPhase.invited;
        final active = call.phase == GroupCallPhase.active;
        final leaving = call.phase == GroupCallPhase.leaving;
        final allMembers = call.current?.members ?? <GroupCallMember>[];
        final members = allMembers.where((member) => !member.isViewer).toList();
        final duration =
            '${call.elapsed.inMinutes.toString().padLeft(2, '0')}:'
            '${(call.elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop || leaving) return;
            if (!active) {
              await _leaveToGroupChat(call);
              return;
            }
            final leave = await _confirmLeave(context, endForAll: call.isOwner);
            if (leave) await _leaveToGroupChat(call);
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            body: SafeArea(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: active ? call.revealControls : null,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: _CallStage(
                        call: call,
                        members: members,
                        active: active,
                        onUserCard: (username) =>
                            unawaited(_showCallUserCard(username)),
                      ),
                    ),
                    if (call.controlsVisible || !active)
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: false,
                          child: _TopAndBottomChrome(
                            call: call,
                            members: allMembers,
                            invited: invited,
                            active: active,
                            leaving: leaving,
                            duration: duration,
                            onLeave: () async {
                              if (!active) {
                                await _leaveToGroupChat(call);
                                return;
                              }
                              final ok = await _confirmLeave(
                                context,
                                endForAll: call.isOwner,
                              );
                              if (ok) {
                                await _leaveToGroupChat(call);
                              }
                            },
                            onJoin: () => _chooseJoinMode(context, call),
                            onChat: _toggleChat,
                            onParticipants: () =>
                                _showParticipants(context, call, allMembers),
                          ),
                        ),
                      ),
                    if (active && _emojiPanelOpen)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 70,
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 4,
                              runSpacing: 2,
                              children:
                                  [
                                    '😂',
                                    '❤️',
                                    '👍',
                                    '😍',
                                    '😭',
                                    '🔥',
                                    '🎉',
                                    '👏',
                                    '🙏',
                                    '😎',
                                    '🤣',
                                    '😘',
                                    '💯',
                                  ].map((emoji) {
                                    return InkWell(
                                      borderRadius: BorderRadius.circular(18),
                                      onTap: () {
                                        final text = _chatController.text;
                                        final selection =
                                            _chatController.selection;
                                        final offset = selection.isValid
                                            ? selection.start
                                            : text.length;
                                        _chatController.text = text
                                            .replaceRange(
                                              offset,
                                              offset,
                                              emoji,
                                            );
                                        _chatController.selection =
                                            TextSelection.collapsed(
                                              offset: offset + emoji.length,
                                            );
                                        setState(() {
                                          _emojiPanelOpen = false;
                                        });
                                        _chatFocusNode.requestFocus();
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.all(6),
                                        child: Text(
                                          emoji,
                                          style: const TextStyle(fontSize: 22),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                            ),
                          ),
                        ),
                      ),
                    if (active)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 8,
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.48),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  tooltip: 'Смайлик',
                                  onPressed: () {
                                    _chatFocusNode.unfocus();
                                    setState(() {
                                      _emojiPanelOpen = !_emojiPanelOpen;
                                      _chatOpen = true;
                                    });
                                  },
                                  icon: const Text(
                                    '🙂',
                                    style: TextStyle(fontSize: 22),
                                  ),
                                ),
                                Expanded(
                                  child: TextField(
                                    controller: _chatController,
                                    focusNode: _chatFocusNode,
                                    onTap: () {
                                      if (!_chatOpen) {
                                        setState(() {
                                          _chatOpen = true;
                                        });
                                      }
                                    },
                                    autofocus: false,
                                    minLines: 1,
                                    maxLines: 3,
                                    textInputAction: TextInputAction.send,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                    ),
                                    decoration: const InputDecoration(
                                      hintText: 'Сообщение группе...',
                                      hintStyle: TextStyle(
                                        color: Colors.white54,
                                      ),
                                      border: InputBorder.none,
                                      isDense: true,
                                    ),
                                    onChanged: (_) => setState(() {}),
                                    onSubmitted: (_) => _sendChatMessage(call),
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Вложения',
                                  onPressed: () async {
                                    _chatFocusNode.unfocus();

                                    final action =
                                        await showModalBottomSheet<String>(
                                          context: context,
                                          backgroundColor: const Color(
                                            0xFF171717,
                                          ),
                                          builder: (sheetContext) {
                                            return SafeArea(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  ListTile(
                                                    leading: const Icon(
                                                      Icons
                                                          .photo_library_outlined,
                                                      color: Colors.white,
                                                    ),
                                                    title: const Text(
                                                      'Фото',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                    onTap: () => Navigator.pop(
                                                      sheetContext,
                                                      'photo',
                                                    ),
                                                  ),
                                                  ListTile(
                                                    leading: const Icon(
                                                      Icons
                                                          .video_library_outlined,
                                                      color: Colors.white,
                                                    ),
                                                    title: const Text(
                                                      'Видео',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                    onTap: () => Navigator.pop(
                                                      sheetContext,
                                                      'video',
                                                    ),
                                                  ),
                                                  ListTile(
                                                    leading: const Icon(
                                                      Icons.attach_file_rounded,
                                                      color: Colors.white,
                                                    ),
                                                    title: const Text(
                                                      'Файл',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                      ),
                                                    ),
                                                    onTap: () => Navigator.pop(
                                                      sheetContext,
                                                      'file',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        );

                                    if (!mounted || action == null) return;

                                    switch (action) {
                                      case 'photo':
                                        await _pickCallImage(call);
                                        break;
                                      case 'video':
                                        await _pickCallVideo(call);
                                        break;
                                      case 'file':
                                        await _pickCallFile(call);
                                        break;
                                    }
                                  },
                                  icon: const Icon(
                                    Icons.attach_file_rounded,
                                    color: Colors.white70,
                                  ),
                                ),
                                if (_chatController.text.trim().isNotEmpty)
                                  IconButton(
                                    tooltip: 'Отправить сообщение',
                                    onPressed: () => _sendChatMessage(call),
                                    icon: const Icon(
                                      Icons.send_rounded,
                                      color: Colors.white,
                                    ),
                                  ),
                                IconButton(
                                  tooltip: _recordingVoice
                                      ? 'Остановить запись'
                                      : 'Голосовое сообщение',
                                  onPressed: () => unawaited(
                                    _recordingVoice
                                        ? _finishVoiceRecording(call)
                                        : _startVoiceRecording(call),
                                  ),
                                  icon: Icon(
                                    _recordingVoice
                                        ? Icons.stop_circle_rounded
                                        : Icons.mic_rounded,
                                    color: _recordingVoice
                                        ? Colors.redAccent
                                        : Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (active &&
                        call.isViewer &&
                        call.current?.isWaitingForHost != true)
                      Positioned(
                        top: 72,
                        right: 12,
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: call.isJoinPending(call.groupId ?? '')
                              ? null
                              : () {
                                  final room = call.current;
                                  if (room == null) return;
                                  call.requestJoin(
                                    room.groupId,
                                    room.name,
                                    room.id,
                                    withVideo: true,
                                  );
                                },
                          icon: const Icon(Icons.video_call_rounded, size: 18),
                          label: Text(
                            call.isJoinPending(call.groupId ?? '')
                                ? 'Запрос отправлен'
                                : 'Запросить место',
                          ),
                        ),
                      ),
                    if (active && call.current?.pinnedMessage != null)
                      Positioned(
                        left: 12,
                        right: 72,
                        bottom: _emojiPanelOpen ? 377 : 266,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.48),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.push_pin_rounded,
                                color: SpartanPalette.gold,
                                size: 17,
                              ),
                              const SizedBox(width: 7),
                              Expanded(
                                child: Text(
                                  '${call.current!.pinnedMessage!['from']?.toString().trim() ?? ''}: ${call.current!.pinnedMessage!['text']?.toString().trim() ?? 'Сообщение'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              if (call.canManageBroadcast)
                                GestureDetector(
                                  onTap: () => _unpinCallMessage(call),
                                  child: const Icon(
                                    Icons.close_rounded,
                                    color: Colors.white70,
                                    size: 18,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (active && _callChatMessages.isNotEmpty)
                      Positioned(
                        key: const ValueKey('call-message-overlay'),
                        left: 12,
                        right: 72,
                        bottom: _emojiPanelOpen ? 181 : 70,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            final groupId = call.groupId?.trim() ?? '';
                            if (groupId.isEmpty) return;
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => GroupChatScreen(
                                  group: <String, dynamic>{
                                    'id': groupId,
                                    'name': call.groupName,
                                  },
                                ),
                              ),
                            );
                          },
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 190),
                            child: SingleChildScrollView(
                              reverse: true,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: _callChatMessages.reversed.toList().reversed.map((
                                  message,
                                ) {
                                  final from =
                                      message['from']?.toString().trim() ?? '';
                                  final messageType =
                                      message['messageType']
                                          ?.toString()
                                          .trim() ??
                                      message['type']?.toString().trim() ??
                                      'text';
                                  final text =
                                      message['text']?.toString().trim() ?? '';

                                  String body;

                                  switch (messageType) {
                                    case 'voice':
                                      body = '🎙️ Голосовое сообщение';
                                      break;
                                    case 'image':
                                    case 'photo':
                                      body = text.isNotEmpty ? text : '📷 Фото';
                                      break;
                                    case 'video':
                                      body = text.isNotEmpty
                                          ? text
                                          : '🎬 Видео';
                                      break;
                                    case 'file':
                                      final fileName =
                                          message['fileName']
                                              ?.toString()
                                              .trim() ??
                                          '';
                                      body = fileName.isNotEmpty
                                          ? '📎 $fileName'
                                          : '📎 Файл';
                                      break;
                                    default:
                                      body = text.isNotEmpty
                                          ? text
                                          : 'Сообщение';
                                  }

                                  return GestureDetector(
                                    onLongPress: () async {
                                      if (!call.canManageBroadcast) return;
                                      final action =
                                          await showModalBottomSheet<String>(
                                            context: context,
                                            builder: (sheetContext) => SafeArea(
                                              child: ListTile(
                                                leading: const Icon(
                                                  Icons.push_pin_rounded,
                                                ),
                                                title: const Text(
                                                  'Закрепить сообщение',
                                                ),
                                                onTap: () => Navigator.pop(
                                                  sheetContext,
                                                  'pin',
                                                ),
                                              ),
                                            ),
                                          );
                                      if (action == 'pin' && mounted) {
                                        _pinCallMessage(call, message);
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 6),
                                      child: Container(
                                        constraints: const BoxConstraints(
                                          maxWidth: 360,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 2,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Row(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Builder(
                                              builder: (context) {
                                                final image = _callAvatarFor(
                                                  from,
                                                );
                                                return GestureDetector(
                                                  behavior:
                                                      HitTestBehavior.opaque,
                                                  onTap: from.isEmpty
                                                      ? null
                                                      : () => _showCallUserCard(
                                                          from,
                                                        ),
                                                  child: CircleAvatar(
                                                    radius: 16,
                                                    backgroundColor:
                                                        SpartanPalette.surface,
                                                    backgroundImage: image,
                                                    child: image == null
                                                        ? Text(
                                                            from.isEmpty
                                                                ? '?'
                                                                : from[0]
                                                                      .toUpperCase(),
                                                            style: const TextStyle(
                                                              color:
                                                                  SpartanPalette
                                                                      .gold,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                            ),
                                                          )
                                                        : null,
                                                  ),
                                                );
                                              },
                                            ),
                                            const SizedBox(width: 9),
                                            Expanded(
                                              child: RichText(
                                                maxLines: 3,
                                                overflow: TextOverflow.ellipsis,
                                                text: TextSpan(
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 15,
                                                    height: 1.2,
                                                  ),
                                                  children: [
                                                    if (from.isNotEmpty)
                                                      TextSpan(
                                                        text: '$from: ',
                                                        style: const TextStyle(
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: SpartanPalette
                                                              .gold,
                                                        ),
                                                      ),
                                                    TextSpan(text: body),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (invited)
                      Positioned.fill(
                        child: _InviteOverlay(
                          call: call,
                          onJoin: () => _chooseJoinMode(context, call),
                          onDecline: () => unawaited(call.leave()),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CallStage extends StatelessWidget {
  const _CallStage({
    required this.call,
    required this.members,
    required this.active,
    required this.onUserCard,
  });

  final GroupCallService call;
  final List<GroupCallMember> members;
  final bool active;
  final ValueChanged<String> onUserCard;

  @override
  Widget build(BuildContext context) {
    final room = call.current;
    if (room?.isWaitingForHost == true) {
      final owner = room!.owner.isNotEmpty ? room.owner : room.startedBy;
      return _HostGraceStage(
        owner: owner,
        hostGraceUntil: room.hostGraceUntil,
        avatar: _avatarFor(owner),
        onUserCard: () => onUserCard(owner),
        canTakeOver: call.isOwner || call.isModerator,
        onTakeOver: () {
          if (call.isModerator && !call.isViewer) {
            call.takeHostRole();
          } else {
            unawaited(call.returnToStage());
          }
        },
      );
    }

    if (members.isEmpty) {
      return const Center(
        child: Text(
          'Ожидание участников...',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      );
    }

    final featured = _featuredMember();
    final others = members
        .where((member) => member.user != featured?.user)
        .toList();

    if (call.layout == GroupCallLayout.grid || featured == null) {
      return _GridStage(call: call, members: members, active: active);
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        _VideoTile(
          call: call,
          member: featured,
          featured: true,
          active: active,
        ),
        Positioned(
          left: 14,
          top: 58,
          child: _FeaturedUserChip(
            member: featured,
            avatar: _avatarFor(featured.user),
            onTap: () => onUserCard(featured.user),
          ),
        ),
        if (others.isNotEmpty)
          Positioned(
            right: 12,
            top: 86,
            bottom: 100,
            width: 112,
            child: ListView.separated(
              itemCount: others.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) => SizedBox(
                height: 92,
                child: _VideoTile(
                  call: call,
                  member: others[index],
                  featured: false,
                  active: active,
                ),
              ),
            ),
          ),
      ],
    );
  }

  GroupCallMember? _featuredMember() {
    if (members.isEmpty) return null;

    String? wanted;
    if (call.layout == GroupCallLayout.spotlight) {
      wanted = call.featuredUser;
    } else {
      wanted = call.current?.startedBy;
    }

    for (final member in members) {
      if (member.user == wanted) return member;
    }
    return members.first;
  }

  ImageProvider? _avatarFor(String username) {
    return _stableCallAvatar(username);
  }
}

class _HostGraceStage extends StatefulWidget {
  const _HostGraceStage({
    required this.owner,
    required this.hostGraceUntil,
    required this.avatar,
    required this.onUserCard,
    required this.canTakeOver,
    required this.onTakeOver,
  });

  final String owner;
  final int? hostGraceUntil;
  final ImageProvider? avatar;
  final VoidCallback onUserCard;
  final bool canTakeOver;
  final VoidCallback onTakeOver;

  @override
  State<_HostGraceStage> createState() => _HostGraceStageState();
}

class _HostGraceStageState extends State<_HostGraceStage> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String get _countdown {
    final until = widget.hostGraceUntil;
    if (until == null) return '--:--';
    final remaining = until - DateTime.now().millisecondsSinceEpoch;
    final seconds = remaining <= 0 ? 0 : (remaining + 999) ~/ 1000;
    return '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  String get _initial {
    final value = widget.owner.trim();
    return value.isEmpty ? '?' : value.characters.first.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (widget.avatar != null)
          Image(image: widget.avatar!, fit: BoxFit.cover, gaplessPlayback: true)
        else
          Container(
            color: const Color(0xFF101010),
            alignment: Alignment.center,
            child: Text(
              _initial,
              style: const TextStyle(
                color: Colors.white24,
                fontSize: 150,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x66000000), Color(0x99000000), Color(0xDD000000)],
            ),
          ),
        ),

        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.owner,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Ведущий временно отсутствует',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: SpartanPalette.gold.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Text(
                    _countdown,
                    style: const TextStyle(
                      color: SpartanPalette.gold,
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Если автор не вернётся и модератор не подтвердит продолжение, эфир завершится',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                if (widget.canTakeOver) ...[
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: widget.onTakeOver,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Вернуться в эфир'),
                  ),
                ],
              ],
            ),
          ),
        ),

        Positioned(
          left: 14,
          top: 58,
          child: Material(
            color: Colors.black.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(24),
            child: InkWell(
              onTap: widget.onUserCard,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.white12,
                      backgroundImage: widget.avatar,
                      child: widget.avatar == null
                          ? Text(
                              _initial,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.owner,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const Text(
                          'Ведущий',
                          style: TextStyle(
                            color: SpartanPalette.gold,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FeaturedUserChip extends StatelessWidget {
  const _FeaturedUserChip({
    required this.member,
    required this.avatar,
    required this.onTap,
  });

  final GroupCallMember member;
  final ImageProvider? avatar;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final role = member.isHost
        ? 'Ведущий'
        : member.isModerator
        ? 'Модератор'
        : 'Участник';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(28),
        child: Container(
          padding: const EdgeInsets.fromLTRB(5, 5, 12, 5),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 21,
                backgroundColor: SpartanPalette.surface,
                backgroundImage: avatar,
                child: avatar == null
                    ? Text(
                        member.user.isEmpty
                            ? '?'
                            : member.user[0].toUpperCase(),
                        style: const TextStyle(
                          color: SpartanPalette.gold,
                          fontWeight: FontWeight.w800,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 9),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.user,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    role,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GridStage extends StatelessWidget {
  const _GridStage({
    required this.call,
    required this.members,
    required this.active,
  });

  final GroupCallService call;
  final List<GroupCallMember> members;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final count = members.length;
    final columns = count <= 1
        ? 1
        : count <= 4
        ? 2
        : 3;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 76, 8, 92),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        itemCount: count,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.78,
        ),
        itemBuilder: (context, index) => _VideoTile(
          call: call,
          member: members[index],
          featured: false,
          active: active,
        ),
      ),
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({
    required this.call,
    required this.member,
    required this.featured,
    required this.active,
  });

  final GroupCallService call;
  final GroupCallMember member;
  final bool featured;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final me = member.user == call.user;
    final host = member.user == call.current?.startedBy;
    final renderer = me ? call.localVideo : call.remoteVideos[member.user];

    final avatar = _stableCallAvatar(member.user);

    final hasVideo =
        !member.away && member.videoEnabled && renderer?.srcObject != null;

    final speaking =
        active &&
        !member.away &&
        !member.muted &&
        call.speakingUser == member.user;

    return GestureDetector(
      onTap: active ? call.revealControls : null,
      onDoubleTap: active && call.canManageBroadcast
          ? () => call.feature(member.user)
          : null,
      onLongPress: active && call.canModerate(member)
          ? () => _showModeration(context)
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(featured ? 0 : 18),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF171717),
            border: Border.all(
              color: speaking ? SpartanPalette.gold : Colors.white12,
              width: speaking ? 2.8 : 1,
            ),
            boxShadow: speaking
                ? [
                    BoxShadow(
                      color: SpartanPalette.gold.withValues(alpha: 0.50),
                      blurRadius: 14,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (hasVideo)
                RTCVideoView(
                  renderer!,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              else
                _AvatarView(
                  avatar: avatar,
                  name: member.user,
                  featured: featured,
                ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.02),
                        Colors.black.withValues(alpha: 0.72),
                      ],
                    ),
                  ),
                ),
              ),
              if (!featured)
                Positioned(
                  left: 10,
                  right: 10,
                  bottom: 70,
                  child: Row(
                    children: [
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.52),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.12),
                            ),
                          ),
                          child: Text(
                            me ? '${member.user} · Вы' : member.user,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      if (member.muted)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.mic_off_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      if (!member.videoEnabled)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.videocam_off_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                      if (member.away)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(
                            Icons.phone_paused_rounded,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                    ],
                  ),
                ),
              if (!featured && (member.isModerator || host))
                Positioned(
                  left: 10,
                  top: 10,
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.58),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: SpartanPalette.gold.withValues(alpha: 0.55),
                      ),
                    ),
                    child: Icon(
                      host
                          ? Icons.workspace_premium_rounded
                          : Icons.shield_rounded,
                      color: SpartanPalette.gold,
                      size: 17,
                    ),
                  ),
                ),
              if (active &&
                  call.controlsVisible &&
                  !me &&
                  call.canManageBroadcast)
                Positioned(
                  right: 8,
                  top: 8,
                  child: _TileMenu(
                    canModerate: call.canModerate(member),
                    canAssignModerator:
                        call.isOwner && !host && member.user != call.user,
                    member: member,
                    onFeature: () => call.feature(member.user),
                    onModerate: (action) =>
                        unawaited(_runModerationAction(context, action)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showModeration(BuildContext context) {
    final parentContext = context;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _ModerationSheet(
        member: member,
        canModerate: call.canModerate(member),
        canAssignModerator:
            call.isOwner && !member.isHost && member.user != call.user,
        onFeature: () {
          Navigator.pop(context);
          call.feature(member.user);
        },
        onModerate: (action) {
          Navigator.pop(context);
          unawaited(_runModerationAction(parentContext, action));
        },
      ),
    );
  }

  Future<void> _runModerationAction(BuildContext context, String action) async {
    if (action == 'promote') {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('Назначить ${member.user} модератором?'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Модератор сможет:'),
              SizedBox(height: 10),
              Text('• принимать запросы на участие в видеосвязи;'),
              Text('• приглашать зрителей в видеочат;'),
              Text('• выключать микрофон и камеру участников;'),
              Text('• удалять участников из звонка;'),
              Text('• подтвердить продолжение эфира после выхода автора.'),
              SizedBox(height: 10),
              Text(
                'Назначать других модераторов может только создатель звонка.',
                style: TextStyle(color: Colors.white60),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Назначить'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
    }
    call.moderate(member.user, action);
  }
}

class _TopAndBottomChrome extends StatelessWidget {
  const _TopAndBottomChrome({
    required this.call,
    required this.members,
    required this.invited,
    required this.active,
    required this.leaving,
    required this.duration,
    required this.onLeave,
    required this.onJoin,
    required this.onChat,
    required this.onParticipants,
  });

  final GroupCallService call;
  final List<GroupCallMember> members;
  final bool invited;
  final bool active;
  final bool leaving;
  final String duration;
  final Future<void> Function() onLeave;
  final VoidCallback onJoin;
  final VoidCallback onChat;
  final VoidCallback onParticipants;

  @override
  Widget build(BuildContext context) {
    final stageCount = members.where((member) => !member.isViewer).length;
    final viewerCount = members.length - stageCount;
    return Stack(
      children: [
        Positioned(
          left: 12,
          right: 12,
          top: 8,
          child: Row(
            children: [
              _CircleButton(
                icon: Icons.keyboard_arrow_down_rounded,
                tooltip: active ? 'Завершить звонок' : 'Выйти',
                onTap: () => unawaited(onLeave()),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      call.groupName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 17,
                        shadows: [Shadow(blurRadius: 6, color: Colors.black)],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      active
                          ? '$stageCount/4 · смотрят $viewerCount · $duration'
                          : invited
                          ? 'Входящий групповой звонок'
                          : leaving
                          ? 'Выход из звонка...'
                          : 'Подключение...',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _CircleButton(
                icon: Icons.groups_rounded,
                tooltip: 'Участники',
                onTap: active ? onParticipants : null,
              ),
              const SizedBox(width: 8),
              _CircleButton(
                icon: Icons.grid_view_rounded,
                tooltip: 'Раскладка',
                onTap: active ? () => _showLayoutSheet(context) : null,
              ),
              const SizedBox(width: 8),
              _CircleButton(
                icon: Icons.more_horiz_rounded,
                tooltip: 'Ещё',
                onTap: active ? () => _showActions(context) : null,
              ),
            ],
          ),
        ),
        if (invited)
          Positioned(
            left: 20,
            right: 20,
            bottom: 18,
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => unawaited(call.leave()),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Отклонить'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onJoin,
                    icon: const Icon(Icons.call_rounded),
                    label: const Text('Присоединиться'),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _showLayoutSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Раскладка участников',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            _LayoutOption(
              title: 'Сцена',
              icon: Icons.person_rounded,
              selected: call.layout == GroupCallLayout.stage,
              onTap: () {
                Navigator.pop(context);
                call.setLayout(GroupCallLayout.stage);
              },
            ),
            _LayoutOption(
              title: 'Сетка',
              icon: Icons.grid_view_rounded,
              selected: call.layout == GroupCallLayout.grid,
              onTap: () {
                Navigator.pop(context);
                call.setLayout(GroupCallLayout.grid);
              },
            ),
            _LayoutOption(
              title: 'В центре',
              icon: Icons.center_focus_strong_rounded,
              selected: call.layout == GroupCallLayout.spotlight,
              onTap: () {
                Navigator.pop(context);
                call.setLayout(GroupCallLayout.spotlight);
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showActions(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                title: Text(
                  'Действия звонка',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              ListTile(
                leading: Icon(
                  call.microphoneEnabled
                      ? Icons.mic_rounded
                      : Icons.mic_off_rounded,
                ),
                title: Text(
                  call.microphoneEnabled
                      ? 'Выключить микрофон'
                      : 'Включить микрофон',
                ),
                onTap: () {
                  Navigator.pop(context);
                  call.toggleMicrophone();
                },
              ),
              ListTile(
                leading: Icon(
                  call.videoEnabled
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                ),
                title: Text(
                  call.videoEnabled ? 'Выключить камеру' : 'Включить камеру',
                ),
                onTap: () {
                  Navigator.pop(context);
                  call.toggleVideo();
                },
              ),
              if ((Platform.isAndroid || Platform.isIOS) && call.videoEnabled)
                ListTile(
                  leading: const Icon(Icons.cameraswitch_rounded),
                  title: const Text('Переключить камеру'),
                  onTap: () {
                    Navigator.pop(context);
                    unawaited(call.switchCamera());
                  },
                ),
              ListTile(
                leading: const Icon(Icons.grid_view_rounded),
                title: const Text('Раскладка участников'),
                onTap: () {
                  Navigator.pop(context);
                  _showLayoutSheet(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.call_end_rounded),
                title: const Text('Выйти из звонка'),
                onTap: () async {
                  Navigator.pop(context);
                  await onLeave();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _InviteOverlay extends StatelessWidget {
  const _InviteOverlay({
    required this.call,
    required this.onJoin,
    required this.onDecline,
  });

  final GroupCallService call;
  final VoidCallback onJoin;
  final VoidCallback onDecline;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      ignoring: false,
      child: Container(
        color: Colors.black.withValues(alpha: 0.35),
        alignment: Alignment.center,
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: SpartanPalette.surface,
            borderRadius: BorderRadius.circular(26),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.groups_rounded,
                size: 54,
                color: SpartanPalette.blue,
              ),
              const SizedBox(height: 14),
              Text(
                call.groupName,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Вас приглашают в групповой звонок.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: onDecline,
                      child: const Text('Отклонить'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: onJoin,
                      child: const Text('Присоединиться'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.label, this.active = false});

  final String label;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? const Color(0xFF244A6B) : Colors.transparent,
        borderRadius: BorderRadius.circular(13),
        border: active
            ? const Border(
                bottom: BorderSide(color: Color(0xFF55B6FF), width: 2),
              )
            : null,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: TextStyle(
          color: active ? Colors.white : Colors.white60,
          fontSize: 11,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
        ),
      ),
    );
  }
}

class _ProfileInfoRow extends StatelessWidget {
  const _ProfileInfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, color: Colors.white60, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white60, fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallUserAction extends StatelessWidget {
  const _CallUserAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.accent = SpartanPalette.gold,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final String? subtitle;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        constraints: const BoxConstraints(minHeight: 92),
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: accent.withValues(alpha: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: accent, size: 27),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 3),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.58),
                  fontSize: 10,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AvatarView extends StatelessWidget {
  const _AvatarView({
    required this.avatar,
    required this.name,
    required this.featured,
  });

  final ImageProvider? avatar;
  final String name;
  final bool featured;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: CircleAvatar(
        radius: featured ? 58 : 34,
        backgroundImage: avatar,
        backgroundColor: SpartanPalette.blue,
        child: avatar == null
            ? Icon(
                Icons.person_rounded,
                size: featured ? 54 : 32,
                color: Colors.white,
              )
            : null,
      ),
    );
  }
}

class _TileMenu extends StatelessWidget {
  const _TileMenu({
    required this.canModerate,
    required this.canAssignModerator,
    required this.member,
    required this.onFeature,
    required this.onModerate,
  });

  final bool canModerate;
  final bool canAssignModerator;
  final GroupCallMember member;
  final VoidCallback onFeature;
  final ValueChanged<String> onModerate;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Действия с участником',
      onSelected: (value) {
        if (value == 'feature') {
          onFeature();
        } else {
          onModerate(value);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'feature', child: Text('Показать крупно')),
        if (canModerate)
          const PopupMenuItem(value: 'mute', child: Text('Выключить микрофон')),
        if (canModerate)
          const PopupMenuItem(
            value: 'video_off',
            child: Text('Выключить камеру'),
          ),
        if (canAssignModerator)
          PopupMenuItem(
            value: member.isModerator ? 'demote' : 'promote',
            child: Text(
              member.isModerator ? 'Снять модератора' : 'Назначить модератором',
            ),
          ),
        if (canModerate)
          const PopupMenuItem(value: 'kick', child: Text('Удалить из звонка')),
      ],
      icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
    );
  }
}

class _ModerationSheet extends StatelessWidget {
  const _ModerationSheet({
    required this.member,
    required this.canModerate,
    required this.canAssignModerator,
    required this.onFeature,
    required this.onModerate,
  });

  final GroupCallMember member;
  final bool canModerate;
  final bool canAssignModerator;
  final VoidCallback onFeature;
  final ValueChanged<String> onModerate;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.person_rounded),
            title: Text(member.user),
            subtitle: Text(member.isModerator ? 'Модератор' : 'Участник'),
          ),
          ListTile(
            leading: const Icon(Icons.center_focus_strong_rounded),
            title: const Text('Показать крупно'),
            onTap: onFeature,
          ),
          if (canModerate)
            ListTile(
              leading: const Icon(Icons.mic_off_rounded),
              title: const Text('Выключить микрофон'),
              onTap: () => onModerate('mute'),
            ),
          if (canModerate)
            ListTile(
              leading: const Icon(Icons.videocam_off_rounded),
              title: const Text('Выключить камеру'),
              onTap: () => onModerate('video_off'),
            ),
          if (canAssignModerator)
            ListTile(
              leading: const Icon(Icons.shield_rounded),
              title: Text(
                member.isModerator
                    ? 'Снять модератора'
                    : 'Назначить модератором',
              ),
              onTap: () =>
                  onModerate(member.isModerator ? 'demote' : 'promote'),
            ),
          if (canModerate)
            ListTile(
              leading: const Icon(Icons.person_remove_rounded),
              title: const Text('Удалить из звонка'),
              onTap: () => onModerate('kick'),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.52),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, color: Colors.white),
      ),
    );
  }
}

class _LayoutOption extends StatelessWidget {
  const _LayoutOption({
    required this.title,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: selected ? const Icon(Icons.check_rounded) : null,
      onTap: onTap,
    );
  }
}

Future<bool> _confirmLeave(
  BuildContext context, {
  bool endForAll = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(endForAll ? 'Завершить звонок?' : 'Выйти из звонка?'),
      content: Text(
        endForAll
            ? 'Вы создатель звонка. Звонок завершится для всех участников.'
            : 'Вы действительно хотите покинуть групповой звонок?',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(endForAll ? 'Завершить для всех' : 'Выйти'),
        ),
      ],
    ),
  );
  return result == true;
}

Future<void> _chooseJoinMode(
  BuildContext context,
  GroupCallService call,
) async {
  final withVideo = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Как присоединиться?'),
      content: const Text('Выберите, хотите ли вы войти с включённой камерой.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Без камеры'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, true),
          icon: const Icon(Icons.videocam_rounded),
          label: const Text('С камерой'),
        ),
      ],
    ),
  );

  if (withVideo != null) {
    await call.accept(withVideo: withVideo);
  }
}
