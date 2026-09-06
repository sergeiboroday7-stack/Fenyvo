import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/group_call_service.dart';
import '../services/group_call_state.dart';
import '../services/storage_service.dart';
import '../theme/spartan_theme.dart';

class GroupCallScreen extends StatelessWidget {
  const GroupCallScreen({super.key, this.service});
  final GroupCallService? service;

  @override
  Widget build(BuildContext context) {
    final call = service ?? GroupCallService.instance;
    return AnimatedBuilder(
      animation: call,
      builder: (context, _) {
        final invited = call.phase == GroupCallPhase.invited;
        final active = call.phase == GroupCallPhase.active;
        final duration =
            '${call.elapsed.inMinutes.toString().padLeft(2, '0')}:'
            '${(call.elapsed.inSeconds % 60).toString().padLeft(2, '0')}';
        final members = call.current?.members ?? <GroupCallMember>[];
        final status = invited
            ? 'Приглашение в голосовой звонок'
            : active
            ? (call.connectedCount > 0
                  ? 'На связи · $duration'
                  : 'Ожидание участников / соединения…')
            : call.phase == GroupCallPhase.leaving
            ? 'Выходим из звонка…'
            : 'Подключаем микрофон…';
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop || call.phase == GroupCallPhase.leaving) return;
            final leave = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Выйти из звонка?'),
                content: const Text(
                  'Остальные участники смогут продолжить разговор.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Остаться'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Выйти'),
                  ),
                ],
              ),
            );
            if (leave == true) await call.leave();
          },
          child: Scaffold(
            appBar: AppBar(
              automaticallyImplyLeading: false,
              title: const Text('Групповой звонок'),
            ),
            body: SafeArea(
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(
                          call.groupName,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          status,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: SpartanPalette.secondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${members.length}/4 участника',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final columns = constraints.maxWidth >= 700 ? 4 : 2;
                            final width =
                                (constraints.maxWidth - (columns - 1) * 12) /
                                columns;
                            return Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              alignment: WrapAlignment.center,
                              children: members
                                  .map(
                                    (member) => SizedBox(
                                      width: width,
                                      child: _MemberCard(
                                        member: member,
                                        me: member.user == call.user,
                                        status: member.user == call.user
                                            ? 'Вы'
                                            : invited
                                            ? 'В звонке'
                                            : call.peerStatus(member.user),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            );
                          },
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'Тестовая версия · голос до 4 участников.\n'
                          'Держите приложение открытым на всех устройствах.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: SpartanPalette.secondary,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 20),
                    color: SpartanPalette.surface,
                    child: Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        if (invited)
                          _Action(
                            label: 'Присоединиться',
                            icon: Icons.call_rounded,
                            color: Colors.green.shade700,
                            onTap: () => unawaited(call.accept()),
                          ),
                        if (active)
                          _Action(
                            key: const ValueKey('group-mic'),
                            label: call.microphoneEnabled
                                ? 'Микрофон'
                                : 'Без звука',
                            icon: call.microphoneEnabled
                                ? Icons.mic_rounded
                                : Icons.mic_off_rounded,
                            onTap: call.toggleMicrophone,
                            color: call.microphoneEnabled
                                ? SpartanPalette.blue
                                : Colors.orange.shade900,
                          ),
                        if (active && call.canSwitchSpeaker)
                          _Action(
                            key: const ValueKey('group-speaker'),
                            label: call.speakerphoneEnabled
                                ? 'Громкая связь'
                                : 'Динамик',
                            icon: call.speakerphoneEnabled
                                ? Icons.volume_up_rounded
                                : Icons.hearing_rounded,
                            onTap: () => unawaited(call.toggleSpeaker()),
                            color: call.speakerphoneEnabled
                                ? SpartanPalette.gold
                                : SpartanPalette.blue,
                          ),
                        _Action(
                          key: const ValueKey('group-leave'),
                          label: invited ? 'Не сейчас' : 'Выйти',
                          icon: Icons.call_end_rounded,
                          color: const Color(0xFFB43E49),
                          onTap: call.phase == GroupCallPhase.leaving
                              ? null
                              : () => unawaited(call.leave()),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.me,
    required this.status,
  });
  final GroupCallMember member;
  final bool me;
  final String status;
  @override
  Widget build(BuildContext context) {
    ImageProvider? avatar;
    try {
      final raw = StorageService.getAvatar(member.user);
      if (raw != null && raw.isNotEmpty)
        avatar = MemoryImage(
          base64Decode(raw.contains(',') ? raw.split(',').last : raw),
        );
    } catch (_) {}
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: SpartanPalette.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: me ? SpartanPalette.gold : SpartanPalette.line,
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundImage: avatar,
            backgroundColor: SpartanPalette.blue,
            child: avatar == null
                ? const Icon(Icons.person_rounded, size: 38)
                : null,
          ),
          const SizedBox(height: 12),
          Text(
            member.user,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 5),
          Text(
            status,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              color: SpartanPalette.secondary,
            ),
          ),
          const SizedBox(height: 8),
          Icon(
            member.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
            size: 20,
            color: member.muted ? Colors.red.shade300 : SpartanPalette.gold,
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    required this.color,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 106,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filled(
          tooltip: label,
          onPressed: onTap,
          icon: Icon(icon),
          iconSize: 27,
          style: IconButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            minimumSize: const Size(56, 56),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    ),
  );
}
