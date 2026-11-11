part of '../screens/chat_screen.dart';

/// Private message list presentation.
/// Sending, storage, and E2EE remain in existing services.
extension _PrivateMessageList on _ChatScreenState {
  Widget _buildMessages() {
    if (_messages.isEmpty) {
      return Center(
        child: Text(
          _chatText('noMessages'),
          style: const TextStyle(
            color: FenyvoPalette.secondary,
            fontSize: 16,
            fontWeight: FontWeight.w500,
            shadows: [Shadow(blurRadius: 4, color: FenyvoPalette.ink)],
          ),
        ),
      );
    }

    final isWindowsDesktop = Platform.isWindows;

    return Stack(
      children: [
        if (!isWindowsDesktop)
          Positioned(
            left: 27,
            top: 0,
            bottom: 0,
            child: Container(
              width: 1.2,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    FenyvoPalette.line.withValues(alpha: .82),
                    FenyvoPalette.line.withValues(alpha: .82),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: isWindowsDesktop
              ? ScrollbarTheme(
                  data: ScrollbarThemeData(
                    thumbColor: WidgetStateProperty.resolveWith<Color?>((
                      states,
                    ) {
                      if (states.contains(WidgetState.dragged)) {
                        return _ChatScreenState._gold.withValues(alpha: 0.88);
                      }

                      if (states.contains(WidgetState.hovered)) {
                        return _ChatScreenState._gold.withValues(alpha: 0.72);
                      }

                      return _ChatScreenState._gold.withValues(alpha: 0.34);
                    }),
                    thickness: WidgetStateProperty.resolveWith<double?>((
                      states,
                    ) {
                      if (states.contains(WidgetState.dragged) ||
                          states.contains(WidgetState.hovered)) {
                        return 8;
                      }

                      return 5;
                    }),
                    radius: const Radius.circular(10),
                    trackColor: WidgetStatePropertyAll(FenyvoPalette.line),
                    trackBorderColor: WidgetStatePropertyAll(
                      Colors.transparent,
                    ),
                  ),
                  child: Scrollbar(
                    controller: _messageScrollController,
                    thumbVisibility: true,
                    trackVisibility: false,
                    interactive: true,
                    child: ListView.builder(
                      controller: _messageScrollController,
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(28, 22, 28, 22),
                      itemCount: _messages.length,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      itemBuilder: (context, index) {
                        return _buildMessageListItem(index);
                      },
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _messageScrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  itemCount: _messages.length,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  itemBuilder: (context, index) {
                    return _buildMessageListItem(index);
                  },
                ),
        ),

        if (isWindowsDesktop)
          Positioned(
            right: 24,
            bottom: 18,
            child: _buildScrollToLatestButton(),
          ),
      ],
    );
  }
}
