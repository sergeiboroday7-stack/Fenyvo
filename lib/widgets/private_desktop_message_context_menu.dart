part of '../screens/chat_screen.dart';

/// Windows private message context menu.
extension _PrivateDesktopMessageContextMenu on _ChatScreenState {
  Future<void> _showDesktopMessageContextMenu(
    Map<String, dynamic> message,
    Offset globalPosition,
  ) async {
    if (!mounted || !Platform.isWindows) {
      return;
    }

    final overlayState = Overlay.of(context);

    final overlayObject = overlayState.context.findRenderObject();

    if (overlayObject is! RenderBox) {
      return;
    }

    final localPosition = overlayObject.globalToLocal(globalPosition);

    final isMe = message['isMe'] == true;

    final isE2ee = message['e2ee'] == true;

    final forwardedFrom = message['forwardedFrom']?.toString().trim() ?? '';

    final isPinned = _isMessagePinned(message);

    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        localPosition.dx,
        localPosition.dy,
        overlayObject.size.width - localPosition.dx,
        overlayObject.size.height - localPosition.dy,
      ),
      color: FenyvoPalette.surface,
      elevation: 14,
      shadowColor: Colors.black.withValues(alpha: 0.72),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: _ChatScreenState._gold.withValues(alpha: 0.34),
          width: 0.8,
        ),
      ),
      items: [
        _buildDesktopMessageContextItem(
          value: 'save',
          icon: Icons.bookmark_add_outlined,
          label: _chatText('save'),
        ),
        _buildDesktopMessageContextItem(
          value: 'reply',
          icon: Icons.reply_rounded,
          label: _chatText('reply'),
        ),
        _buildDesktopMessageContextItem(
          value: 'copy',
          icon: Icons.copy_rounded,
          label: _chatText('copy'),
        ),
        _buildDesktopMessageContextItem(
          value: 'forward',
          icon: Icons.forward_rounded,
          label: _chatText('forward'),
        ),
        if (_canOfferLegacyMediaAccess(message))
          _buildDesktopMessageContextItem(
            value: 'legacy_media_access',
            icon: Icons.lock_open_rounded,
            label: _legacyMediaAccessText(
              'Открыть доступ',
              'Надати доступ',
              'Grant access',
            ),
          ),
        if (isMe && forwardedFrom.isEmpty && !isE2ee)
          _buildDesktopMessageContextItem(
            value: 'edit',
            icon: Icons.edit_rounded,
            label: _chatText('edit'),
          ),
        const PopupMenuDivider(height: 8),
        _buildDesktopMessageContextItem(
          value: 'heart',
          icon: Icons.favorite_rounded,
          label: '${_chatText('reaction')} ❤️',
        ),
        if (!isE2ee)
          _buildDesktopMessageContextItem(
            value: 'translate',
            icon: Icons.translate_rounded,
            label: _chatText('translate'),
          ),
        if (!isE2ee)
          _buildDesktopMessageContextItem(
            value: 'chatgpt',
            icon: Icons.auto_awesome_rounded,
            label: 'ChatGPT',
          ),
        _buildDesktopMessageContextItem(
          value: 'pin',
          icon: isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
          label: isPinned ? _chatText('unpin') : _chatText('pin'),
        ),
        const PopupMenuDivider(height: 8),
        if (isMe)
          _buildDesktopMessageContextItem(
            value: 'delete_everyone',
            icon: Icons.delete_sweep_rounded,
            label: _chatText('deleteForEveryone'),
            danger: true,
          ),
        _buildDesktopMessageContextItem(
          value: 'delete_me',
          icon: Icons.delete_rounded,
          label: _chatText('delete'),
          danger: true,
        ),
      ],
    );

    if (!mounted || result == null) {
      return;
    }

    switch (result) {
      case 'save':
        unawaited(_saveToSaved(message));
        break;
      case 'reply':
        _startReply(message);
        break;

      case 'copy':
        unawaited(_copyMessageText(message));
        break;

      case 'forward':
        unawaited(_forwardMessage(message));
        break;

      case 'legacy_media_access':
        unawaited(_showLegacyMediaAccess(message));
        break;
      case 'edit':
        unawaited(_editMessage(message));
        break;

      case 'heart':
        _sendReaction(message, '\u2764\uFE0F');
        break;

      case 'translate':
        unawaited(_translateMessage(message));
        break;

      case 'chatgpt':
        unawaited(_showChatGptSheet(message));
        break;

      case 'pin':
        _togglePinnedMessage(message);
        break;

      case 'delete_everyone':
        unawaited(_deleteMessageForEveryone(message));
        break;

      case 'delete_me':
        unawaited(_deleteMessageForMe(message));
        break;
    }
  }
}
