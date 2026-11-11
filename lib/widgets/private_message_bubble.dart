part of '../screens/chat_screen.dart';

/// Private chat bubble presentation.
/// State mutations remain owned by ChatScreen.
extension _PrivateMessageBubble on _ChatScreenState {
  Widget _buildMessageBubble(Map<String, dynamic> message) {
    if (message['localCallEntry'] == true) {
      return _buildCallHistoryBubble(message);
    }
    final isMe = message['isMe'] == true;

    final isAiGenerated =
        message['aiGenerated'] == true || message['autoReply'] == true;

    final isE2ee = message['e2ee'] == true;

    final isVoiceMessage = _isVoiceMessage(message);

    final privateMessageType = PrivateAttachmentHelpers.messageType(message);

    final isPrivateMediaMessage =
        privateMessageType == 'image' ||
        privateMessageType == 'video' ||
        privateMessageType == 'file';

    final isHexVideoNote =
        privateMessageType == 'video' &&
        _privateAttachmentName(message)
            .toLowerCase()
            .startsWith('fenyvo_hex_note_');

    final text = message['text']?.toString() ?? '';
    Map<String, dynamic>? sharedContact;
    final rawSharedContact = message['sharedContact'];
    if (rawSharedContact is Map) {
      final parsed = Map<String, dynamic>.from(rawSharedContact);
      if (parsed['username']?.toString().trim().isNotEmpty == true) {
        sharedContact = parsed;
      }
    }

    final from = message['from']?.toString() ?? '';

    final forwardedFrom = message['forwardedFrom']?.toString().trim() ?? '';

    final forwardComment = message['forwardComment']?.toString().trim() ?? '';

    final isWindowsDesktop = Platform.isWindows;

    final messageId = _getMessageId(message);

    final isHovered = isWindowsDesktop && _hoveredMessageId == messageId;

    final showDesktopActions = isHovered;

    final isPinnedHighlight = _highlightedMessageId == messageId;

    final bubbleMaxWidth = isWindowsDesktop
        ? forwardedFrom.isNotEmpty
              ? 520.0
              : 480.0
        : MediaQuery.of(context).size.width * 0.7;

    final timeStr = _formatTime(message['time']);

    final isEdited =
        message['isEdited'] == true ||
        (message['editedAt']?.toString().trim().isNotEmpty ?? false);

    Map<String, dynamic>? replyTo;

    final rawReplyTo = message['replyTo'];

    if (rawReplyTo is Map) {
      replyTo = Map<String, dynamic>.from(rawReplyTo);
    }

    final signalBorder = isPinnedHighlight
        ? BorderSide(
            color: isMe ? FenyvoPalette.ink : _ChatScreenState._gold,
            width: 2,
          )
        : isHovered
        ? BorderSide(
            color: isMe
                ? FenyvoPalette.ink.withValues(alpha: .30)
                : _ChatScreenState._gold.withValues(alpha: .52),
            width: .9,
          )
        : BorderSide(
            color: isMe
                ? _ChatScreenState._gold.withValues(alpha: .38)
                : FenyvoPalette.line.withValues(alpha: .88),
            width: .75,
          );
    final signalShape = isWindowsDesktop
        ? RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(isMe ? 18 : 6),
              topRight: Radius.circular(isMe ? 6 : 18),
              bottomLeft: const Radius.circular(18),
              bottomRight: const Radius.circular(18),
            ),
            side: signalBorder,
          )
        : BeveledRectangleBorder(
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(isMe ? 13 : 5),
              topRight: Radius.circular(isMe ? 5 : 13),
              bottomRight: Radius.circular(isMe ? 13 : 5),
              bottomLeft: Radius.circular(isMe ? 5 : 13),
            ),
            side: signalBorder,
          );

    // HEX video notes deliberately bypass the ordinary message card.
    // Regular videos, images and files keep their existing presentation.
    if (isHexVideoNote &&
        replyTo == null &&
        sharedContact == null &&
        forwardedFrom.isEmpty &&
        forwardComment.isEmpty) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () => _showMessageActionMenu(message),
          onSecondaryTapDown: isWindowsDesktop
              ? (details) => unawaited(
                  _showDesktopMessageContextMenu(
                    message,
                    details.globalPosition,
                  ),
                )
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: isMe
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                if (from.trim().isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(
                      left: 5,
                      right: 5,
                      bottom: 4,
                    ),
                    child: Text(
                      '@${from.trim()}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _ChatScreenState._gold,
                      ),
                    ),
                  ),
                ],
                _buildPrivateMediaBody(message, isMe: isMe),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isE2ee) ...[
                      Icon(
                        message['e2eeError'] == true
                            ? Icons.lock_reset_rounded
                            : Icons.lock_rounded,
                        size: 10,
                        color: message['e2eeError'] == true
                            ? Colors.redAccent
                            : _ChatScreenState._gold,
                      ),
                      const SizedBox(width: 4),
                    ],
                    if (timeStr.isNotEmpty)
                      Text(
                        timeStr,
                        style: TextStyle(
                          fontSize: 10,
                          color: _ChatScreenState._gold.withValues(alpha: 0.85),
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

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: MouseRegion(
        cursor: isWindowsDesktop ? SystemMouseCursors.basic : MouseCursor.defer,
        onEnter: isWindowsDesktop
            ? (_) {
                if (_hoveredMessageId != messageId) {
                  _updateMessageBubbleState(() {
                    _hoveredMessageId = messageId;
                  });
                }
              }
            : null,
        onExit: isWindowsDesktop
            ? (_) {
                if (_hoveredMessageId == messageId) {
                  _updateMessageBubbleState(() {
                    _hoveredMessageId = null;
                  });
                }
              }
            : null,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onLongPress: () {
            _showMessageActionMenu(message);
          },
          onDoubleTap: isWindowsDesktop
              ? () {
                  _startReply(message);
                }
              : null,
          onSecondaryTapDown: isWindowsDesktop
              ? (details) {
                  unawaited(
                    _showDesktopMessageContextMenu(
                      message,
                      details.globalPosition,
                    ),
                  );
                }
              : null,
          child: Padding(
            padding: EdgeInsets.only(
              top: isWindowsDesktop ? 2 : 4,
              bottom: isWindowsDesktop ? 8 : 18,
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
                  decoration: ShapeDecoration(
                    gradient: isMe
                        ? const LinearGradient(
                            colors: [
                              FenyvoPalette.surfaceRaised,
                              FenyvoPalette.blue,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : const LinearGradient(
                            colors: [
                              FenyvoPalette.surfaceSoft,
                              FenyvoPalette.surface,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                    shape: signalShape,
                    shadows: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: isPinnedHighlight
                              ? 0.10
                              : isHovered
                              ? 0.07
                              : 0.03,
                        ),
                        blurRadius: isPinnedHighlight
                            ? 14
                            : isHovered
                            ? 9
                            : 4,
                        offset: const Offset(0, 2),
                      ),
                      if (isPinnedHighlight)
                        BoxShadow(
                          color: _ChatScreenState._gold.withValues(alpha: 0.06),
                          blurRadius: 24,
                          spreadRadius: 1.5,
                        )
                      else if (isHovered)
                        BoxShadow(
                          color: isMe
                              ? _ChatScreenState._gold.withValues(alpha: 0.06)
                              : _ChatScreenState._gold.withValues(alpha: 0.06),
                          blurRadius: 14,
                          spreadRadius: -2,
                        ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isMe && from.isNotEmpty && forwardedFrom.isEmpty)
                        Text(
                          from,
                          style: const TextStyle(
                            fontSize: 10,
                            color: _ChatScreenState._gold,
                            fontWeight: FontWeight.bold,
                          ),
                        ),

                      if (!isMe && from.isNotEmpty && forwardedFrom.isEmpty)
                        const SizedBox(height: 2),

                      if (replyTo != null)
                        _buildReplyPreview(replyTo, isMe: isMe),

                      if (forwardedFrom.isNotEmpty) ...[
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.forward_rounded,
                              size: 12,
                              color: isMe
                                  ? FenyvoPalette.secondary
                                  : _ChatScreenState._gold.withValues(
                                      alpha: 0.90,
                                    ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                AppLanguageService.instance
                                    .text('chatForwardedFromPeerLabelV2')
                                    .replaceAll('{user}', forwardedFrom),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isMe
                                      ? FenyvoPalette.secondary
                                      : _ChatScreenState._gold.withValues(
                                          alpha: 0.90,
                                        ),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                      ],

                      if (sharedContact != null)
                        _buildSharedContactCard(sharedContact, isMe: isMe)
                      else if (isVoiceMessage)
                        PrivateVoiceMessagePlayer(
                          message: message,
                          isMe: isMe,
                          messageId: _getMessageId(message),
                          playingVoiceMessageId: _playingVoiceMessageId,
                          playbackPosition: _voicePlaybackPosition,
                          playbackDuration: _voicePlaybackDuration,
                          playbackRate: _voicePlaybackRate,
                          isPlaying: _voiceIsPlaying,
                          gold: _ChatScreenState._gold,
                          onToggle: () => _toggleVoicePlayback(message),
                          onSeek: (fraction) =>
                              _seekVoiceMessage(message, fraction),
                          onCycleRate: () => _cycleVoicePlaybackRate(message),
                        )
                      else if (isPrivateMediaMessage)
                        _buildPrivateMediaBody(message, isMe: isMe)
                      else
                        Text(
                          text,
                          style: TextStyle(
                            color: isMe ? FenyvoPalette.ink : FenyvoPalette.ink,
                            fontSize: 16,
                          ),
                        ),

                      if (forwardComment.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Container(
                            height: 0.6,
                            color: isMe
                                ? FenyvoPalette.line
                                : FenyvoPalette.blue.withValues(alpha: 0.22),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 11,
                              color: isMe
                                  ? FenyvoPalette.secondary
                                  : _ChatScreenState._gold.withValues(
                                      alpha: 0.82,
                                    ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                from.isNotEmpty
                                    ? from
                                    : AppLanguageService.instance.text(
                                        'chatCommentFallback',
                                      ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isMe
                                      ? FenyvoPalette.secondary
                                      : _ChatScreenState._gold.withValues(
                                          alpha: 0.82,
                                        ),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          forwardComment,
                          style: TextStyle(
                            color: isMe ? FenyvoPalette.ink : FenyvoPalette.ink,
                            fontSize: 14,
                            height: 1.18,
                          ),
                        ),
                      ],

                      if (isWindowsDesktop &&
                          isHovered &&
                          (isVoiceMessage || isPrivateMediaMessage))
                        Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Tooltip(
                              message: AppLanguageService.instance.text(
                                'chatForwardMedia',
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () =>
                                    unawaited(_forwardMessage(message)),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isMe
                                        ? FenyvoPalette.surface.withValues(
                                            alpha: 0.09,
                                          )
                                        : FenyvoPalette.blue.withValues(
                                            alpha: 0.10,
                                          ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: isMe
                                          ? FenyvoPalette.line
                                          : _ChatScreenState._gold.withValues(
                                              alpha: 0.42,
                                            ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.forward_rounded,
                                        size: 16,
                                        color: isMe
                                            ? FenyvoPalette.ink
                                            : _ChatScreenState._gold,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        AppLanguageService.instance.text(
                                          'chatForward',
                                        ),
                                        style: TextStyle(
                                          color: isMe
                                              ? FenyvoPalette.ink
                                              : _ChatScreenState._gold,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 4),

                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isE2ee) ...[
                            Icon(
                              message['e2eeError'] == true
                                  ? Icons.lock_reset_rounded
                                  : Icons.lock_rounded,
                              size: 10,
                              color: message['e2eeError'] == true
                                  ? Colors.redAccent
                                  : _ChatScreenState._gold,
                            ),
                            const SizedBox(width: 3),
                          ],
                          if (isAiGenerated) ...[
                            Icon(
                              Icons.smart_toy_rounded,
                              size: 10,
                              color: isMe
                                  ? FenyvoPalette.secondary
                                  : _ChatScreenState._gold.withValues(
                                      alpha: 0.88,
                                    ),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              'AI',
                              style: TextStyle(
                                color: isMe
                                    ? FenyvoPalette.secondary
                                    : _ChatScreenState._gold.withValues(
                                        alpha: 0.88,
                                      ),
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(width: 5),
                          ],
                          if (timeStr.isNotEmpty)
                            Text(
                              timeStr,
                              style: TextStyle(
                                color: isMe
                                    ? FenyvoPalette.secondary
                                    : FenyvoPalette.secondary,
                                fontSize: 10,
                              ),
                            ),

                          if (isEdited) ...[
                            const SizedBox(width: 4),
                            Text(
                              AppLanguageService.instance.text(
                                'privateBubbleEdited',
                              ),
                              style: TextStyle(
                                color: isMe
                                    ? FenyvoPalette.secondary
                                    : FenyvoPalette.muted,
                                fontSize: 9,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ],

                          if (isMe) ...[
                            const SizedBox(width: 4),
                            _buildMessageStatus(message),
                          ],

                          if (!isWindowsDesktop &&
                              (isVoiceMessage || isPrivateMediaMessage)) ...[
                            const SizedBox(width: 5),
                            Tooltip(
                              message: AppLanguageService.instance.text(
                                'chatForward',
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(15),
                                onTap: () =>
                                    unawaited(_forwardMessage(message)),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.forward_rounded,
                                    size: 17,
                                    color: isMe
                                        ? FenyvoPalette.secondary
                                        : _ChatScreenState._gold,
                                  ),
                                ),
                              ),
                            ),
                          ],

                          if (isWindowsDesktop) ...[
                            const SizedBox(width: 8),
                            AnimatedOpacity(
                              duration: const Duration(milliseconds: 120),
                              curve: Curves.easeOutCubic,
                              opacity: showDesktopActions ? 1.0 : 0.0,
                              child: AnimatedScale(
                                duration: const Duration(milliseconds: 130),
                                curve: Curves.easeOutCubic,
                                scale: showDesktopActions ? 1.0 : 0.90,
                                child: IgnorePointer(
                                  ignoring: !showDesktopActions,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _buildDesktopQuickMessageAction(
                                        icon: Icons.reply_rounded,
                                        tooltip: AppLanguageService.instance
                                            .text('privateBubbleReply'),
                                        isMe: isMe,
                                        onTap: () {
                                          _startReply(message);
                                        },
                                      ),
                                      const SizedBox(width: 4),
                                      _buildDesktopQuickMessageAction(
                                        icon: Icons.copy_rounded,
                                        tooltip: AppLanguageService.instance
                                            .text('privateBubbleCopy'),
                                        isMe: isMe,
                                        onTap: () {
                                          unawaited(_copyMessageText(message));
                                        },
                                      ),
                                      const SizedBox(width: 4),
                                      _buildDesktopQuickMessageAction(
                                        icon: Icons.forward_rounded,
                                        tooltip: AppLanguageService.instance
                                            .text('privateBubbleForward'),
                                        isMe: isMe,
                                        onTap: () {
                                          unawaited(_forwardMessage(message));
                                        },
                                      ),
                                      if (isMe && forwardedFrom.isEmpty) ...[
                                        const SizedBox(width: 4),
                                        _buildDesktopQuickMessageAction(
                                          icon: Icons.edit_rounded,
                                          tooltip: AppLanguageService.instance
                                              .text('privateBubbleEdit'),
                                          isMe: isMe,
                                          onTap: () {
                                            unawaited(_editMessage(message));
                                          },
                                        ),
                                      ],
                                      const SizedBox(width: 4),
                                      _buildDesktopQuickMessageAction(
                                        icon: Icons.favorite_outline_rounded,
                                        tooltip: AppLanguageService.instance
                                            .text('privateBubbleReactionHeart'),
                                        isMe: isMe,
                                        onTap: () {
                                          _sendReaction(
                                            message,
                                            '\u2764\uFE0F',
                                          );
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                if (!isMe)
                  Positioned(
                    left: -8,
                    top: 22,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: _ChatScreenState._gold,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: FenyvoPalette.canvasDeep,
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: _ChatScreenState._gold.withValues(
                              alpha: .30,
                            ),
                            blurRadius: 7,
                          ),
                        ],
                      ),
                    ),
                  ),

                if (isMe && !isWindowsDesktop)
                  Positioned(
                    right: 2,
                    top: 12,
                    bottom: 12,
                    child: Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: _ChatScreenState._gold.withValues(alpha: .82),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),

                Positioned(
                  bottom: -15,
                  left: isMe ? -15 : null,
                  right: isMe ? null : -15,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    transitionBuilder: (child, animation) {
                      return ScaleTransition(
                        scale: CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutBack,
                        ),
                        child: child,
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey<String>(_reactionStateKey(message)),
                      child: _buildReactionRow(message),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
