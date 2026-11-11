part of '../screens/chat_screen.dart';

/// Private message reaction UI components.
/// Sending and message mutation stay in ChatScreen.
extension _PrivateReactionWidgets on _ChatScreenState {
  Widget _buildReactionChip({
    required String reaction,
    required int count,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? FenyvoPalette.blue.withValues(alpha: 0.22)
              : FenyvoPalette.surface.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _ChatScreenState._gold.withValues(
              alpha: selected ? 1.0 : 0.75,
            ),
            width: selected ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: selected
                  ? _ChatScreenState._gold.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: selected ? 8 : 5,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(reaction, style: const TextStyle(fontSize: 16, height: 1)),
            if (count > 1) ...[
              const SizedBox(width: 4),
              Text(
                '$count',
                style: const TextStyle(
                  color: FenyvoPalette.ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ========================================
  // \u0420\u042F\u0414 \u0420\u0415\u0410\u041A\u0426\u0418\u0419
  // ========================================

  Widget _buildQuickReactionButton({
    String? emoji,
    IconData? icon,
    Color? iconColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        child: icon != null
            ? Icon(icon, color: iconColor ?? FenyvoPalette.ink, size: 26)
            : Text(emoji ?? '', style: const TextStyle(fontSize: 24)),
      ),
    );
  }

  // ========================================
  // \u041F\u041E\u041B\u041D\u042B\u0419 \u0412\u042B\u0411\u041E\u0420 \u0420\u0415\u0410\u041A\u0426\u0418\u0419
  // ========================================
  Widget _buildReactionRow(Map<String, dynamic> message) {
    final currentUser = SocketService.instance.currentUser ?? '';
    final reactions = _getMessageReactions(message);

    if (reactions.isEmpty) return const SizedBox.shrink();

    final counts = countMessageReactions(reactions.values);

    final widgets = <Widget>[];
    for (final reaction in _ChatScreenState._supportedReactions) {
      final count = counts[reaction] ?? 0;
      if (count == 0) continue;
      if (widgets.isNotEmpty) widgets.add(const SizedBox(width: 4));
      widgets.add(
        _buildReactionChip(
          reaction: reaction,
          count: count,
          selected: reactions[currentUser] == reaction,
          onTap: () {
            _sendReaction(message, reaction);
          },
        ),
      );
    }

    if (currentUser.isNotEmpty && !reactions.containsKey(currentUser)) {
      if (widgets.isNotEmpty) widgets.add(const SizedBox(width: 4));
      widgets.add(
        _buildHeartIcon(
          filled: false,
          enabled: true,
          onTap: () {
            _sendReaction(message, '\u2764\uFE0F');
          },
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: widgets);
  }

  // ========================================
  // \u0413\u0410\u041B\u041E\u0427\u041A\u0418 \u0421\u0422\u0410\u0422\u0423\u0421\u0410
  // ========================================

  Future<void> _showReactionPicker(Map<String, dynamic> message) async {
    if (!mounted) return;

    final currentUser = SocketService.instance.currentUser ?? '';
    final selectedReaction = currentUser.isEmpty
        ? ''
        : _getMessageReactions(message)[currentUser] ?? '';

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final sheetHeight = MediaQuery.sizeOf(sheetContext).height * 0.50;

        return SafeArea(
          top: false,
          child: Container(
            height: sheetHeight,
            decoration: const BoxDecoration(
              color: FenyvoPalette.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(color: _ChatScreenState._gold, width: 1.2),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
            child: Column(
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: FenyvoPalette.line,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 14),
                const Row(
                  children: [
                    Icon(
                      Icons.emoji_emotions_outlined,
                      color: _ChatScreenState._gold,
                    ),
                    SizedBox(width: 10),
                    Text(
                      '\u0412\u044B\u0431\u0435\u0440\u0438\u0442\u0435 \u0440\u0435\u0430\u043A\u0446\u0438\u044E',
                      style: TextStyle(
                        color: FenyvoPalette.ink,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: GridView.builder(
                    itemCount: _ChatScreenState._supportedReactions.length,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 6,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                    itemBuilder: (context, index) {
                      final reaction =
                          _ChatScreenState._supportedReactions[index];
                      final selected = reaction == selectedReaction;
                      return InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          Future<void>.delayed(
                            const Duration(milliseconds: 60),
                            () {
                              if (!mounted) return;
                              _sendReaction(message, reaction);
                            },
                          );
                        },
                        child: Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? FenyvoPalette.blue.withValues(alpha: 0.20)
                                : FenyvoPalette.surface.withValues(alpha: 0.42),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _ChatScreenState._gold.withValues(
                                alpha: selected ? 1.0 : 0.45,
                              ),
                            ),
                          ),
                          child: Text(
                            reaction,
                            style: const TextStyle(fontSize: 28),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  // ========================================
  // \u041A\u041E\u041C\u041F\u0410\u041A\u0422\u041D\u0410\u042F \u0421\u0422\u0420\u041E\u041A\u0410 \u041C\u0415\u041D\u042E
  // ========================================
}
