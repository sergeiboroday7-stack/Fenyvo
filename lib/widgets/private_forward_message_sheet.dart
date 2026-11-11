part of '../screens/chat_screen.dart';

/// Forwarding recipient selection and preview.
/// The actual send operation remains in ChatScreen and SocketService.
extension _PrivateForwardMessageSheet on _ChatScreenState {
  Future<void> _forwardMessage(Map<String, dynamic> message) async {
    final currentUser = SocketService.instance.currentUser ?? '';

    final messageType = PrivateAttachmentHelpers.messageType(message);
    final rawText = message['text']?.toString().trim() ?? '';
    final text = rawText.isNotEmpty
        ? rawText
        : messageType == 'voice'
        ? ('🎤 ' + _chatText('privateForwardVoice'))
        : messageType == 'image'
        ? ('📷 ' + _chatText('privateForwardPhoto'))
        : messageType == 'video'
        ? ('🎥 ' + _chatText('privateForwardVideo'))
        : messageType == 'file'
        ? '📎 ${_privateAttachmentName(message)}'
        : '';

    if (currentUser.isEmpty || (messageType == 'text' && text.isEmpty)) {
      return;
    }

    final users = StorageService.getChatUsers(currentUser)
      ..removeWhere((user) => user.trim().isEmpty || user == currentUser)
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    if (users.isEmpty) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_chatText('privateForwardNoChats')),
          backgroundColor: FenyvoPalette.surface,
        ),
      );

      return;
    }

    final forwardedFrom =
        message['forwardedFrom']?.toString().trim().isNotEmpty == true
        ? message['forwardedFrom'].toString().trim()
        : message['from']?.toString().trim() ?? currentUser;

    final commentController = TextEditingController();

    final searchController = TextEditingController();

    final selectedUsers = <String>{};
    var searchQuery = '';

    if (!mounted) {
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final filteredUsers = users
                .where((user) => user.toLowerCase().contains(searchQuery))
                .toList();

            final keyboardHeight = MediaQuery.viewInsetsOf(sheetContext).bottom;

            final screenHeight = MediaQuery.sizeOf(sheetContext).height;

            return AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(bottom: keyboardHeight),
              child: SafeArea(
                child: Container(
                  constraints: BoxConstraints(
                    maxHeight: (screenHeight - keyboardHeight) * 0.92,
                  ),
                  decoration: const BoxDecoration(
                    color: FenyvoPalette.surface,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: FenyvoPalette.line,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.fromLTRB(18, 16, 18, 12),
                        child: Row(
                          children: [
                            Icon(
                              Icons.forward_rounded,
                              color: _ChatScreenState._gold,
                            ),
                            SizedBox(width: 10),
                            Text(
                              _chatText('privateForwardTitle'),
                              style: TextStyle(
                                color: FenyvoPalette.ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0x33171B20)),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                        child: TextField(
                          controller: searchController,
                          onChanged: (value) {
                            setSheetState(() {
                              searchQuery = value.trim().toLowerCase();
                            });
                          },
                          style: const TextStyle(color: FenyvoPalette.ink),
                          decoration: InputDecoration(
                            hintText: _chatText('privateForwardSearchContact'),
                            hintStyle: const TextStyle(
                              color: FenyvoPalette.muted,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              color: _ChatScreenState._gold,
                            ),
                            suffixIcon: searchQuery.isEmpty
                                ? null
                                : IconButton(
                                    onPressed: () {
                                      searchController.clear();
                                      setSheetState(() {
                                        searchQuery = '';
                                      });
                                    },
                                    icon: const Icon(
                                      Icons.close,
                                      color: FenyvoPalette.secondary,
                                    ),
                                  ),
                            filled: true,
                            fillColor: FenyvoPalette.surface,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: _ChatScreenState._gold,
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                      if (selectedUsers.isNotEmpty)
                        SizedBox(
                          height: 42,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            children: selectedUsers
                                .map(
                                  (user) => Padding(
                                    padding: const EdgeInsets.only(right: 7),
                                    child: InputChip(
                                      label: Text(user),
                                      labelStyle: const TextStyle(
                                        color: FenyvoPalette.ink,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      backgroundColor: FenyvoPalette.blue,
                                      deleteIconColor: Colors.black,
                                      side: BorderSide.none,
                                      onDeleted: () {
                                        setSheetState(() {
                                          selectedUsers.remove(user);
                                        });
                                      },
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      Flexible(
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: filteredUsers.length,
                          itemBuilder: (context, index) {
                            final user = filteredUsers[index];
                            final avatar = StorageService.getAvatar(user);
                            ImageProvider? imageProvider;

                            if (avatar != null && avatar.isNotEmpty) {
                              try {
                                imageProvider = MemoryImage(
                                  base64Decode(avatar),
                                );
                              } catch (_) {
                                imageProvider = null;
                              }
                            }

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: FenyvoPalette.surface,
                                backgroundImage: imageProvider,
                                child: imageProvider == null
                                    ? Text(
                                        user.isEmpty
                                            ? '?'
                                            : user[0].toUpperCase(),
                                        style: const TextStyle(
                                          color: _ChatScreenState._gold,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : null,
                              ),
                              title: Text(
                                user,
                                style: const TextStyle(
                                  color: FenyvoPalette.ink,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              trailing: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                width: 27,
                                height: 27,
                                decoration: BoxDecoration(
                                  color: selectedUsers.contains(user)
                                      ? FenyvoPalette.blue
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: _ChatScreenState._gold,
                                    width: 1.3,
                                  ),
                                ),
                                child: selectedUsers.contains(user)
                                    ? const Icon(
                                        Icons.check,
                                        color: FenyvoPalette.ink,
                                        size: 18,
                                      )
                                    : null,
                              ),
                              onTap: () {
                                setSheetState(() {
                                  if (!selectedUsers.add(user)) {
                                    selectedUsers.remove(user);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const Divider(height: 1, color: Color(0x33171B20)),
                      Container(
                        width: double.infinity,
                        margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: FenyvoPalette.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _ChatScreenState._gold.withValues(
                              alpha: 0.35,
                            ),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '\u21AA ' +
                                  AppLanguageService.instance
                                      .text('chatForwardedFromPeerLabelV2')
                                      .replaceAll('{user}', forwardedFrom),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _ChatScreenState._gold,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: FenyvoPalette.secondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextField(
                          controller: commentController,
                          minLines: 1,
                          maxLines: 3,
                          style: const TextStyle(color: FenyvoPalette.ink),
                          decoration: InputDecoration(
                            hintText: _chatText('privateForwardAddComment'),
                            hintStyle: const TextStyle(
                              color: FenyvoPalette.muted,
                            ),
                            prefixIcon: const Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: _ChatScreenState._gold,
                            ),
                            filled: true,
                            fillColor: FenyvoPalette.surface,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: const BorderSide(
                                color: _ChatScreenState._gold,
                                width: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
                        child: SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: selectedUsers.isEmpty
                                ? null
                                : () {
                                    final comment = commentController.text
                                        .trim();
                                    final recipients = selectedUsers.toList();

                                    Navigator.of(sheetContext).pop();

                                    unawaited(
                                      _sendForwardedMessage(
                                        message: message,
                                        recipients: recipients,
                                        forwardedFrom: forwardedFrom,
                                        comment: comment,
                                      ),
                                    );
                                  },
                            icon: const Icon(Icons.send_rounded),
                            label: Text(
                              selectedUsers.isEmpty
                                  ? _chatText('privateForwardSelectRecipient')
                                  : selectedUsers.length == 1
                                  ? _chatText('privateForwardSend')
                                  : _chatText('privateForwardSendCount', {
                                      'count': selectedUsers.length,
                                    }),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: FenyvoPalette.blue,
                              foregroundColor: FenyvoPalette.ink,
                              disabledBackgroundColor: FenyvoPalette.surface,
                              disabledForegroundColor: FenyvoPalette.muted,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              textStyle: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    commentController.dispose();
    searchController.dispose();
  }
}
