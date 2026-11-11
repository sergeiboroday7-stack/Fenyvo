part of '../screens/chat_screen.dart';

/// Presentation of shared contacts and call history.
/// Message handling and storage remain in ChatScreen.
extension _PrivateMessageDisplayWidgets on _ChatScreenState {
  Widget _buildSharedContactCard(
    Map<String, dynamic> contact, {
    required bool isMe,
  }) {
    final username = contact['username']?.toString().trim() ?? '';
    final name = contact['name']?.toString().trim() ?? '';
    final title = name.isNotEmpty ? name : username;
    final initial = title.isNotEmpty
        ? title.substring(0, 1).toUpperCase()
        : '?';

    return Container(
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isMe
            ? FenyvoPalette.surface.withValues(alpha: .18)
            : FenyvoPalette.blue.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isMe
              ? FenyvoPalette.line
              : _ChatScreenState._gold.withValues(alpha: .42),
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 23,
            backgroundColor: FenyvoPalette.surfaceRaised,
            child: Text(
              initial,
              style: const TextStyle(
                color: _ChatScreenState._gold,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: FenyvoPalette.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (username.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '@$username',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: FenyvoPalette.secondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          const Icon(
            Icons.person_rounded,
            color: _ChatScreenState._gold,
            size: 22,
          ),
        ],
      ),
    );
  }

  Widget _buildCallHistoryBubble(Map<String, dynamic> message) {
    final raw = message['call'];
    final call = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final missed = call['outcome'] == 'missed';
    final incoming = call['incoming'] == true;
    final video = call['video'] == true;
    final accent = missed ? Colors.redAccent : _ChatScreenState._gold;
    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 14),
        child: Material(
          color: FenyvoPalette.surface.withValues(alpha: 0.94),
          borderRadius: BorderRadius.circular(18),
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => unawaited(
              CallService.instance.startCall(
                peer: widget.targetUser,
                video: video,
              ),
            ),
            child: Container(
              constraints: BoxConstraints(
                maxWidth: Platform.isWindows ? 310 : 340,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: accent.withValues(alpha: 0.42)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    video ? Icons.videocam_rounded : Icons.call_rounded,
                    color: accent,
                  ),
                  const SizedBox(width: 11),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          CallHistoryService.title(call),
                          style: TextStyle(
                            color: missed
                                ? Colors.redAccent
                                : FenyvoPalette.ink,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          CallHistoryService.status(call),
                          style: const TextStyle(
                            color: FenyvoPalette.secondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    incoming
                        ? Icons.call_received_rounded
                        : Icons.call_made_rounded,
                    color: accent,
                    size: 19,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageListItem(int reverseIndex) {
    final messageIndex = _messages.length - 1 - reverseIndex;

    final message = _messages[messageIndex];

    final isFirstMessage = messageIndex == 0;

    final previousMessage = isFirstMessage ? null : _messages[messageIndex - 1];

    final showDateSeparator =
        isFirstMessage ||
        previousMessage == null ||
        !_isSameMessageDay(message['time'], previousMessage['time']);

    final messageId = _getMessageId(message);

    return KeyedSubtree(
      key: _messageItemKey(messageId),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showDateSeparator) _buildMessageDateSeparator(message['time']),
          _buildMessageBubble(message),
        ],
      ),
    );
  }

  Widget _buildHeartIcon({
    required bool filled,
    required bool enabled,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Container(
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: FenyvoPalette.surface.withValues(alpha: 0.72),
          border: Border.all(
            color: _ChatScreenState._gold.withValues(
              alpha: enabled ? 0.95 : 0.70,
            ),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 5,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          filled ? Icons.favorite : Icons.favorite_border,
          color: _ChatScreenState._gold,
          size: 18,
        ),
      ),
    );
  }

  Widget _buildMessageStatus(Map<String, dynamic> message) {
    final status = message['status']?.toString().trim() ?? 'sent';

    final isRead = status == 'read';

    if (status == 'queued') {
      return Icon(
        Icons.schedule_rounded,
        size: 15,
        color: FenyvoPalette.secondary,
        semanticLabel: _chatText('waitingToSend'),
      );
    }
    if (status == 'sending') {
      return Icon(
        Icons.sync_rounded,
        size: 15,
        color: FenyvoPalette.secondary,
        semanticLabel: _chatText('sending'),
      );
    }
    if (status == 'failed') {
      return Icon(
        Icons.error_outline_rounded,
        size: 15,
        color: Colors.red,
        semanticLabel: _chatText('notSent'),
      );
    }

    return Icon(
      isRead || status == 'delivered'
          ? Icons.done_all_rounded
          : Icons.done_rounded,
      size: 15,
      color: isRead ? FenyvoPalette.gold : FenyvoPalette.secondary,
      semanticLabel: isRead
          ? _chatText('read')
          : status == 'delivered'
          ? _chatText('delivered')
          : _chatText('sent'),
    );
  }

  // ========================================
  // \u041C\u0415\u041D\u042E \u041F\u041E \u0414\u041E\u041B\u0413\u041E\u041C\u0423 \u041D\u0410\u0416\u0410\u0422\u0418\u042E
  // ========================================
}
