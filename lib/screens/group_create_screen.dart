import '../theme/spartan_theme.dart';

import 'package:flutter/material.dart';

import '../services/socket_service.dart';

class GroupCreateScreen extends StatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  State<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends State<GroupCreateScreen> {
  static const Color _gold = SpartanPalette.ink;

  final TextEditingController _nameController = TextEditingController();
  final Set<String> _selectedUsers = <String>{};
  List<String> _users = <String>[];
  bool _loadingUsers = true;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    SocketService.instance.addMessageHandler(_handleMessage);
    SocketService.instance.getRegisteredUsers();
  }

  @override
  void dispose() {
    SocketService.instance.removeMessageHandler(_handleMessage);
    _nameController.dispose();
    super.dispose();
  }

  void _handleMessage(Map<String, dynamic> msg) {
    if (!mounted) return;

    final type = msg['type']?.toString() ?? '';
    final rawData = msg['data'];
    final data = rawData is Map
        ? Map<String, dynamic>.from(rawData)
        : <String, dynamic>{};

    if (type == 'registered_users') {
      final rawUsers = data['users'];
      if (rawUsers is! List) return;

      final currentUser = SocketService.instance.currentUser ?? '';
      final users =
          rawUsers
              .map((value) => value.toString().trim())
              .where((user) => user.isNotEmpty && user != currentUser)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

      setState(() {
        _users = users;
        _loadingUsers = false;
      });
      return;
    }

    if (type == 'group_created') {
      final rawGroup = data['group'];
      if (rawGroup is! Map) return;

      setState(() {
        _creating = false;
      });

      Navigator.of(context).pop(Map<String, dynamic>.from(rawGroup));
      return;
    }

    if (type == 'group_error') {
      final reason = data['reason']?.toString().trim();
      setState(() {
        _creating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            reason == null || reason.isEmpty
                ? 'Не удалось создать группу'
                : reason,
          ),
          backgroundColor: SpartanPalette.surface,
        ),
      );
    }
  }

  void _createGroup() {
    final name = _nameController.text.trim();

    if (name.length < 2) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Введите название группы')));
      return;
    }

    if (_selectedUsers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Выберите хотя бы одного участника')),
      );
      return;
    }

    setState(() {
      _creating = true;
    });

    SocketService.instance.createGroup(name, _selectedUsers.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpartanPalette.canvas,
      appBar: AppBar(
        backgroundColor: SpartanPalette.canvas,
        foregroundColor: SpartanPalette.ink,
        title: const Text(
          'Новая группа',
          style: TextStyle(color: _gold, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
              child: TextField(
                controller: _nameController,
                maxLength: 60,
                style: const TextStyle(color: SpartanPalette.ink),
                decoration: InputDecoration(
                  labelText: 'Название группы',
                  labelStyle: const TextStyle(color: SpartanPalette.secondary),
                  prefixIcon: const Icon(Icons.groups_rounded, color: _gold),
                  filled: true,
                  fillColor: SpartanPalette.surface,
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: SpartanPalette.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: _gold),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  const Text(
                    'Участники',
                    style: TextStyle(
                      color: SpartanPalette.ink,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Выбрано: ${_selectedUsers.length}',
                    style: const TextStyle(color: _gold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _loadingUsers
                  ? const Center(child: CircularProgressIndicator(color: _gold))
                  : _users.isEmpty
                  ? const Center(
                      child: Text(
                        'Нет доступных пользователей',
                        style: TextStyle(color: SpartanPalette.secondary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _users.length,
                      itemBuilder: (context, index) {
                        final user = _users[index];
                        final selected = _selectedUsers.contains(user);

                        return CheckboxListTile(
                          value: selected,
                          activeColor: SpartanPalette.blue,
                          checkColor: SpartanPalette.ink,
                          title: Text(
                            user,
                            style: const TextStyle(color: SpartanPalette.ink),
                          ),
                          secondary: CircleAvatar(
                            backgroundColor: SpartanPalette.surface,
                            child: Text(
                              user.isEmpty ? '?' : user[0].toUpperCase(),
                              style: const TextStyle(
                                color: _gold,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          onChanged: _creating
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
                  onPressed: _creating ? null : _createGroup,
                  icon: _creating
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: SpartanPalette.ink,
                          ),
                        )
                      : const Icon(Icons.group_add_rounded),
                  label: Text(_creating ? 'Создание...' : 'Создать группу'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: SpartanPalette.blue,
                    foregroundColor: SpartanPalette.ink,
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
