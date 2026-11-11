part of '../screens/chat_screen.dart';

/// Pinned message controls and navigation.
/// ChatScreen continues to own state and lifecycle.
extension _PrivatePinnedMessages on _ChatScreenState {
  bool _isMessagePinned(Map<String, dynamic> message) {
    return message['isPinned'] == true;
  }

  List<Map<String, dynamic>> _getPinnedMessages() {
    return _messages.where(_isMessagePinned).take(10).toList(growable: false);
  }

  void _togglePinnedMessage(Map<String, dynamic> message) {
    final targetId = _getMessageId(message);

    if (targetId.isEmpty) {
      return;
    }

    final wasPinned = _isMessagePinned(message);

    final pinnedCount = _messages.where(_isMessagePinned).length;

    if (!wasPinned && pinnedCount >= 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_chatText('pinLimit')),
          backgroundColor: FenyvoPalette.surface,
        ),
      );
      return;
    }

    _updatePinnedMessageState(() {
      for (final item in _messages) {
        if (_getMessageId(item) == targetId) {
          item['isPinned'] = !wasPinned;
          break;
        }
      }
    });

    final owner = SocketService.instance.currentUser?.trim() ?? '';
    final peer = widget.targetUser.trim();
    final nextPinned = !wasPinned;

    if (owner.isNotEmpty && peer.isNotEmpty && owner != peer) {
      unawaited(
        StorageService.mutateMessagesDurably(owner, peer, (current) {
          for (final stored in current) {
            if (stored['id']?.toString().trim() != targetId) {
              continue;
            }

            final sender = stored['from']?.toString().trim() ?? '';
            final recipient = stored['to']?.toString().trim() ?? '';
            final belongsToChat =
                (sender == owner && recipient == peer) ||
                (sender == peer && recipient == owner);
            if (!belongsToChat) return null;

            if ((stored['isPinned'] == true) == nextPinned) {
              return null;
            }

            stored['isPinned'] = nextPinned;
            return current;
          }
          return null;
        }).then((_) {}).catchError((Object error, StackTrace stack) {
          debugPrint('Durable local pin update failed: $error');
        }),
      );
    }

    final currentUser = SocketService.instance.currentUser?.trim() ?? '';
    if (currentUser.isNotEmpty) {
      if (wasPinned) {
        StorageService.removePinnedMessage(
          currentUser,
          widget.targetUser,
          targetId,
        );
      } else {
        StorageService.addPinnedMessage(currentUser, widget.targetUser, {
          'messageId': targetId,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }
    }

    SocketService.instance.setPinnedMessage(
      messageId: targetId,
      to: widget.targetUser,
      pinned: !wasPinned,
      messageFrom: message['from']?.toString() ?? '',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(milliseconds: 1100),
        behavior: SnackBarBehavior.floating,
        backgroundColor: FenyvoPalette.surface,
        content: Row(
          children: [
            Icon(
              wasPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
              color: _ChatScreenState._gold,
              size: 18,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                wasPinned
                    ? _chatText('privatePinUnpinned')
                    : _chatText('privatePinPinned'),
                style: const TextStyle(color: FenyvoPalette.ink),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _jumpToPinnedMessage(Map<String, dynamic> message) async {
    final targetId = _getMessageId(message);

    if (targetId.isEmpty) {
      return;
    }

    final messageIndex = _messages.indexWhere(
      (item) => _getMessageId(item) == targetId,
    );

    if (messageIndex < 0) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_chatText('privatePinUnavailable'))),
      );

      return;
    }

    _pinnedHighlightTimer?.cancel();

    if (mounted) {
      _updatePinnedMessageState(() {
        _highlightedMessageId = targetId;
      });
    }

    await Future<void>.delayed(const Duration(milliseconds: 35));

    if (_messageScrollController.hasClients) {
      final targetReverseIndex = _messages.length - 1 - messageIndex;

      final position = _messageScrollController.position;

      final maxExtent = position.maxScrollExtent;

      final estimatedOffset = _messages.length <= 1
          ? 0.0
          : maxExtent * targetReverseIndex / (_messages.length - 1);

      await _messageScrollController.animateTo(
        estimatedOffset.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
      );

      for (var attempt = 0; attempt < 24; attempt++) {
        if (!mounted || !_messageScrollController.hasClients) {
          break;
        }

        await Future<void>.delayed(const Duration(milliseconds: 35));

        final itemContext = _messageItemKeys[targetId]?.currentContext;

        if (itemContext != null) {
          await Scrollable.ensureVisible(
            itemContext,
            alignment: 0.50,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          );

          break;
        }

        final builtReverseIndices = <int>[];

        for (
          var reverseIndex = 0;
          reverseIndex < _messages.length;
          reverseIndex++
        ) {
          final index = _messages.length - 1 - reverseIndex;

          final id = _getMessageId(_messages[index]);

          if (id.isEmpty) {
            continue;
          }

          if (_messageItemKeys[id]?.currentContext != null) {
            builtReverseIndices.add(reverseIndex);
          }
        }

        final currentPosition = _messageScrollController.position;

        final viewport = currentPosition.viewportDimension;

        final step = viewport > 220 ? viewport * 0.78 : 220.0;

        var nextOffset = currentPosition.pixels;

        if (builtReverseIndices.isEmpty) {
          nextOffset = estimatedOffset;
        } else {
          builtReverseIndices.sort();

          final firstBuilt = builtReverseIndices.first;

          final lastBuilt = builtReverseIndices.last;

          if (targetReverseIndex > lastBuilt) {
            nextOffset += step;
          } else if (targetReverseIndex < firstBuilt) {
            nextOffset -= step;
          } else {
            nextOffset = estimatedOffset;
          }
        }

        final clampedOffset = nextOffset.clamp(
          currentPosition.minScrollExtent,
          currentPosition.maxScrollExtent,
        );

        if ((clampedOffset - currentPosition.pixels).abs() < 1.0) {
          break;
        }

        await _messageScrollController.animateTo(
          clampedOffset,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOutCubic,
        );
      }

      final finalContext = _messageItemKeys[targetId]?.currentContext;

      if (finalContext != null) {
        await Scrollable.ensureVisible(
          finalContext,
          alignment: 0.50,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
        );
      }
    }

    _pinnedHighlightTimer = Timer(const Duration(milliseconds: 2200), () {
      if (!mounted || _highlightedMessageId != targetId) {
        return;
      }

      _updatePinnedMessageState(() {
        _highlightedMessageId = null;
      });
    });
  }

  Widget _buildPinnedMessageBanner() {
    final pinned = _getPinnedMessages();
    if (pinned.isEmpty) return const SizedBox.shrink();
    return Container(
      height: 46,
      decoration: const BoxDecoration(
        color: FenyvoPalette.surface,
        border: Border(
          bottom: BorderSide(color: FenyvoPalette.line, width: .5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(
            Icons.push_pin_outlined,
            size: 18,
            color: FenyvoPalette.gold,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: pinned.length,
              separatorBuilder: (_, index) => const SizedBox(width: 12),
              itemBuilder: (context, index) {
                final message = pinned[index];
                return ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: InkWell(
                          onTap: () => unawaited(_jumpToPinnedMessage(message)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              message['text']?.toString() ??
                                  _chatText('message'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 13,
                                color: FenyvoPalette.ink,
                              ),
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: _chatText('unpin'),
                        constraints: const BoxConstraints(
                          minWidth: 40,
                          minHeight: 40,
                        ),
                        onPressed: () => _togglePinnedMessage(message),
                        icon: const Icon(Icons.close_rounded, size: 16),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          Text(
            '${pinned.length}/10',
            style: const TextStyle(
              color: FenyvoPalette.secondary,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}
