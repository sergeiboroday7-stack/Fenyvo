import '../theme/fenyvo_theme.dart';

import 'package:flutter/material.dart';

import '../services/socket_service.dart';
import '../services/app_language_service.dart';

class GroupAddMembersScreen extends StatefulWidget {
  final Map<String, dynamic> group;

  const GroupAddMembersScreen({super.key, required this.group});

  @override
  State<GroupAddMembersScreen> createState() => _GroupAddMembersScreenState();
}

class _GroupAddMembersScreenState extends State<GroupAddMembersScreen> {
  static const Color _gold = FenyvoPalette.ink;

  final Set<String> _selectedUsers = <String>{};
  List<String> _users = <String>[];
  bool _loadingUsers = true;
  bool _saving = false;

  String get _groupId => widget.group['id']?.toString().trim() ?? '';

  Set<String> get _existingMembers {
    final rawMembers = widget.group['members'];
    if (rawMembers is! List) {
      return <String>{};
    }

    return rawMembers
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  @override
  void initState() {
    super.initState();
    SocketService.instance.addMessageHandler(_handleMessage);
    AppLanguageService.instance.code.addListener(_onLanguageChanged);
    SocketService.instance.getRegisteredUsers();
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    SocketService.instance.removeMessageHandler(_handleMessage);
    AppLanguageService.instance.code.removeListener(_onLanguageChanged);
    super.dispose();
  }

  void _handleMessage(Map<String, dynamic> msg) {
    if (!mounted) {
      return;
    }

    final type = msg['type']?.toString() ?? '';
    final rawData = msg['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};

    if (type == 'registered_users') {
      final rawUsers = data['users'];
      if (rawUsers is! List) {
        return;
      }

      final existing = _existingMembers;
      final currentUser = SocketService.instance.currentUser ?? '';

      final users =
          rawUsers
              .map((value) => value.toString().trim())
              .where(
                (user) =>
                    user.isNotEmpty &&
                    user != currentUser &&
                    !existing.contains(user),
              )
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      setState(() {
        _users = users;
        _loadingUsers = false;
      });
      return;
    }

    if (type == 'group_updated') {
      final rawGroup = data['group'];
      if (rawGroup is! Map) {
        return;
      }

      final group = Map<String, dynamic>.from(rawGroup);
      if (group['id']?.toString() != _groupId) {
        return;
      }

      setState(() {
        _saving = false;
      });

      Navigator.of(context).pop(group);
      return;
    }

    if (type == 'group_error') {
      final reason = data['reason']?.toString().trim();

      setState(() {
        _saving = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reason == null || reason.isEmpty
                ? AppLanguageService.instance.text('groupAddFailed')
                : reason,
          ),
          backgroundColor: FenyvoPalette.surface,
        ),
      );
    }
  }

  void _addMembers() {
    if (_groupId.isEmpty || _selectedUsers.isEmpty) {
      return;
    }

    setState(() {
      _saving = true;
    });

    SocketService.instance.addGroupMembers(_groupId, _selectedUsers.toList());
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLanguageService.instance.text;
    final groupName =
        widget.group['name']?.toString().trim() ??
        AppLanguageService.instance.text('group');

    return Scaffold(
      backgroundColor: FenyvoPalette.canvas,
      appBar: AppBar(
        backgroundColor: FenyvoPalette.canvas,
        foregroundColor: FenyvoPalette.ink,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t('groupAddTitle'),
              style: TextStyle(
                color: _gold,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            Text(
              groupName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: FenyvoPalette.secondary,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                children: [
                  Text(
                    t('groupAddNewMembers'),
                    style: TextStyle(
                      color: FenyvoPalette.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    t(
                      'groupAddSelected',
                    ).replaceAll('{count}', _selectedUsers.length.toString()),
                    style: const TextStyle(color: _gold),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loadingUsers
                  ? const Center(child: CircularProgressIndicator(color: _gold))
                  : _users.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          t('groupAddNoAvailableUsers'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: FenyvoPalette.secondary,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _users.length,
                      itemBuilder: (context, index) {
                        final user = _users[index];
                        final selected = _selectedUsers.contains(user);

                        return CheckboxListTile(
                          value: selected,
                          activeColor: FenyvoPalette.blue,
                          checkColor: FenyvoPalette.ink,
                          title: Text(
                            user,
                            style: const TextStyle(color: FenyvoPalette.ink),
                          ),
                          secondary: CircleAvatar(
                            backgroundColor: FenyvoPalette.surface,
                            child: Text(
                              user.isEmpty ? '?' : user[0].toUpperCase(),
                              style: const TextStyle(
                                color: _gold,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          onChanged: _saving
                              ? null
                              : (value) {
                                  setState(() {
                                    if (value == true) {
                                      _selectedUsers.add(user);
                                    } else {
                                      _selectedUsers.remove(user);
                                    }
                                  });
                                },
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _saving || _selectedUsers.isEmpty
                      ? null
                      : _addMembers,
                  icon: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: FenyvoPalette.ink,
                          ),
                        )
                      : const Icon(Icons.person_add_alt_1_rounded),
                  label: Text(
                    _saving
                        ? t('groupAddSaving')
                        : _selectedUsers.isEmpty
                        ? t('groupAddSelectMembers')
                        : t('groupAddCount').replaceAll(
                            '{count}',
                            _selectedUsers.length.toString(),
                          ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: FenyvoPalette.blue,
                    foregroundColor: FenyvoPalette.ink,
                    disabledBackgroundColor: FenyvoPalette.surface,
                    disabledForegroundColor: FenyvoPalette.muted,
                    textStyle: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
