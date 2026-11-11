part of '../screens/chat_screen.dart';

/// Existing registered-user picker with localized UI.
extension _PrivateShareContactPicker on _ChatScreenState {
  Future<void> _showShareContactPicker() async {
    if (_sendingPrivateMedia || _isRecordingVoice) return;

    final completer = Completer<List<String>>();
    _registeredUsersCompleter = completer;
    SocketService.instance.getRegisteredUsers();

    List<String> users = _registeredUsers;
    try {
      users = await completer.future.timeout(const Duration(seconds: 8));
    } on TimeoutException {
      users = _registeredUsers;
    } finally {
      if (identical(_registeredUsersCompleter, completer)) {
        _registeredUsersCompleter = null;
      }
    }

    if (!mounted) return;
    if (users.isEmpty) {
      _privateMediaSnack(
        AppLanguageService.instance.text('chatContactsNotFound'),
      );
      return;
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: FenyvoPalette.surface,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * .65,
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(
                  AppLanguageService.instance.text('chatShareContact'),
                  style: TextStyle(
                    color: FenyvoPalette.ink,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return ListTile(
                      leading: CircleAvatar(
                        child: Text(user.substring(0, 1).toUpperCase()),
                      ),
                      title: Text(
                        user,
                        style: const TextStyle(
                          color: FenyvoPalette.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        '@$user',
                        style: const TextStyle(color: FenyvoPalette.secondary),
                      ),
                      trailing: Icon(
                        Icons.send_rounded,
                        color: _ChatScreenState._gold,
                      ),
                      onTap: () => Navigator.of(sheetContext).pop(user),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (!mounted || selected == null || selected.trim().isEmpty) return;

    final username = selected.trim();
    SocketService.instance.sendMessage(
      widget.targetUser,
      'Контакт: @$username',
      sharedContact: <String, dynamic>{'username': username, 'name': username},
    );
  }
}
