import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../services/group_call_service.dart';
import '../services/group_call_state.dart';
import '../services/storage_service.dart';
import '../theme/spartan_theme.dart';

class GroupCallScreen extends StatefulWidget {
  const GroupCallScreen({super.key, this.service});

  final GroupCallService? service;

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  @override
  void initState() {
    super.initState();
    unawaited(WakelockPlus.enable());
  }

  @override
  void dispose() {
    unawaited(WakelockPlus.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final call = widget.service ?? GroupCallService.instance;

    return AnimatedBuilder(
      animation: call,
      builder: (context, _) {
        final invited = call.phase == GroupCallPhase.invited;
        final active = call.phase == GroupCallPhase.active;
        final leaving = call.phase == GroupCallPhase.leaving;
        final members = call.current?.members ?? <GroupCallMember>[];
        final duration =
            '${call.elapsed.inMinutes.toString().padLeft(2, '0')}:'
            '${(call.elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop || leaving) return;
            final leave = await _confirmLeave(context);
            if (leave) await call.leave();
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
                      ),
                    ),
                    if (call.controlsVisible || !active)
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: false,
                          child: _TopAndBottomChrome(
                            call: call,
                            members: members,
                            invited: invited,
                            active: active,
                            leaving: leaving,
                            duration: duration,
                            onLeave: () async {
                              final ok = await _confirmLeave(context);
                              if (ok) await call.leave();
                            },
                            onJoin: () => _chooseJoinMode(context, call),
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
  });

  final GroupCallService call;
  final List<GroupCallMember> members;
  final bool active;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return const Center(
        child: Text(
          'Ожидание участников…',
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

    ImageProvider? avatar;
    try {
      final raw = StorageService.getAvatar(member.user);
      if (raw != null && raw.isNotEmpty) {
        avatar = MemoryImage(
          base64Decode(raw.contains(',') ? raw.split(',').last : raw),
        );
      }
    } catch (_) {}

    final hasVideo = member.videoEnabled && renderer?.srcObject != null;

    return GestureDetector(
      onTap: active ? call.revealControls : null,
      onDoubleTap: active ? () => call.feature(member.user) : null,
      onLongPress: active && call.canModerate(member)
          ? () => _showModeration(context)
          : null,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(featured ? 0 : 18),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF171717),
            border: Border.all(
              color: me ? SpartanPalette.gold : Colors.white12,
              width: me ? 1.5 : 1,
            ),
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
              Positioned(
                left: 10,
                right: 10,
                bottom: 10,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        host
                            ? '${member.user} · Ведущий'
                            : member.isModerator
                            ? '${member.user} · Модератор'
                            : me
                            ? '${member.user} · Вы'
                            : member.user,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          shadows: [Shadow(blurRadius: 5, color: Colors.black)],
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
                  ],
                ),
              ),
              if (member.isModerator || host)
                Positioned(
                  left: 10,
                  top: 10,
                  child: _RoleBadge(text: host ? 'Ведущий' : 'Модератор'),
                ),
              if (active && !me)
                Positioned(
                  right: 8,
                  top: 8,
                  child: _TileMenu(
                    canModerate: call.canModerate(member),
                    canAssignModerator:
                        call.isHost && !host && member.user != call.user,
                    member: member,
                    onFeature: () => call.feature(member.user),
                    onModerate: (action) => call.moderate(member.user, action),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _showModeration(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _ModerationSheet(
        member: member,
        canModerate: call.canModerate(member),
        canAssignModerator:
            call.isHost && !member.isHost && member.user != call.user,
        onFeature: () {
          Navigator.pop(context);
          call.feature(member.user);
        },
        onModerate: (action) {
          Navigator.pop(context);
          call.moderate(member.user, action);
        },
      ),
    );
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
  });

  final GroupCallService call;
  final List<GroupCallMember> members;
  final bool invited;
  final bool active;
  final bool leaving;
  final String duration;
  final Future<void> Function() onLeave;
  final VoidCallback onJoin;

  @override
  Widget build(BuildContext context) {
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
                tooltip: 'Свернуть',
                onTap: () {},
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
                          ? '${members.length}/4 · $duration'
                          : invited
                          ? 'Вас приглашают в звонок'
                          : leaving
                          ? 'Выходим из звонка…'
                          : 'Подключаемся…',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              _CircleButton(
                icon: Icons.grid_view_rounded,
                tooltip: 'Вид',
                onTap: active ? () => _showLayoutSheet(context) : null,
              ),
              const SizedBox(width: 8),
              _CircleButton(
                icon: Icons.more_horiz_rounded,
                tooltip: 'Действия',
                onTap: active ? () => _showActions(context) : null,
              ),
            ],
          ),
        ),
        if (active)
          Positioned(
            left: 14,
            right: 14,
            bottom: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _ControlButton(
                  icon: call.microphoneEnabled
                      ? Icons.mic_rounded
                      : Icons.mic_off_rounded,
                  label: call.microphoneEnabled ? 'Микрофон' : 'Без звука',
                  onTap: call.toggleMicrophone,
                ),
                const SizedBox(width: 10),
                _ControlButton(
                  icon: call.videoEnabled
                      ? Icons.videocam_rounded
                      : Icons.videocam_off_rounded,
                  label: call.videoEnabled ? 'Камера' : 'Без видео',
                  onTap: call.toggleVideo,
                ),
                if (call.canSwitchSpeaker) ...[
                  const SizedBox(width: 10),
                  _ControlButton(
                    icon: call.speakerphoneEnabled
                        ? Icons.volume_up_rounded
                        : Icons.hearing_rounded,
                    label: 'Динамик',
                    onTap: () => unawaited(call.toggleSpeaker()),
                  ),
                ],
                const SizedBox(width: 10),
                _ControlButton(
                  icon: Icons.call_end_rounded,
                  label: 'Выйти',
                  danger: true,
                  onTap: leaving ? null : () => unawaited(onLeave()),
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
                    label: const Text('Не сейчас'),
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
                'Вид звонка',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            _LayoutOption(
              title: 'Ведущий крупно',
              icon: Icons.person_rounded,
              selected: call.layout == GroupCallLayout.stage,
              onTap: () {
                Navigator.pop(context);
                call.setLayout(GroupCallLayout.stage);
              },
            ),
            _LayoutOption(
              title: 'Все участники',
              icon: Icons.grid_view_rounded,
              selected: call.layout == GroupCallLayout.grid,
              onTap: () {
                Navigator.pop(context);
                call.setLayout(GroupCallLayout.grid);
              },
            ),
            _LayoutOption(
              title: 'Выбранный участник',
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(
              title: Text(
                'Действия',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.chat_bubble_outline_rounded),
              title: const Text('Открыть чат'),
              onTap: () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Чат во время звонка будет подключён отдельно.',
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.grid_view_rounded),
              title: const Text('Изменить вид'),
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
                      child: const Text('Не сейчас'),
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
      tooltip: 'Действия',
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
            child: Text('Выключить видео'),
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
              title: const Text('Выключить видео'),
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

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
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

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: danger
          ? const Color(0xFFB43E49)
          : Colors.black.withValues(alpha: 0.62),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 64,
          height: 64,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 25),
              const SizedBox(height: 2),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 9),
              ),
            ],
          ),
        ),
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
  final VoidCallback onTap;

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

Future<bool> _confirmLeave(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Выйти из звонка?'),
      content: const Text('Остальные участники смогут продолжить разговор.'),
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
      content: const Text(
        'Выберите, включать ли камеру. Это можно изменить во время звонка.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Только голос'),
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
