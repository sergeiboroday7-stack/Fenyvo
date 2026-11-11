part of '../screens/chat_screen.dart';

/// Reusable private message menu presentation helpers.
/// Message operations remain in ChatScreen.
extension _PrivateMessageMenuWidgets on _ChatScreenState {
  Widget _buildMessageMenuItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final color = danger ? const Color(0xFFFF4D4D) : FenyvoPalette.ink;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 37,
              child: Icon(
                icon,
                color: danger
                    ? const Color(0xFFFF4D4D)
                    : _ChatScreenState._gold,
                size: 22,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null && subtitle.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: danger
                            ? const Color(0xFFFF6A6A)
                            : _ChatScreenState._gold.withValues(alpha: 0.78),
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildDesktopMessageContextItem({
    required String value,
    required IconData icon,
    required String label,
    bool danger = false,
  }) {
    final itemColor = danger ? const Color(0xFFFF6262) : FenyvoPalette.ink;

    return PopupMenuItem<String>(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: danger ? const Color(0xFFFF6262) : _ChatScreenState._gold,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: itemColor,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // LEGACY_MEDIA_REGRANT_UI_V1

  Widget _buildDesktopQuickMessageAction({
    required IconData icon,
    required String tooltip,
    required bool isMe,
    required VoidCallback onTap,
  }) {
    final foreground = isMe
        ? FenyvoPalette.secondary
        : _ChatScreenState._gold.withValues(alpha: 0.88);

    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isMe
                  ? FenyvoPalette.surface.withValues(alpha: 0.075)
                  : FenyvoPalette.blue.withValues(alpha: 0.075),
              border: Border.all(
                color: isMe
                    ? FenyvoPalette.ink.withValues(alpha: 0.14)
                    : _ChatScreenState._gold.withValues(alpha: 0.16),
                width: 0.7,
              ),
            ),
            child: Icon(icon, size: 14, color: foreground),
          ),
        ),
      ),
    );
  }

  // ========================================
  // \u041E\u0414\u041D\u041E \u0421\u041E\u041E\u0411\u0429\u0415\u041D\u0418\u0415
  // ========================================
}
