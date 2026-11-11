part of '../screens/chat_screen.dart';

/// UI for text, attachments, voice recording and reply.
/// Message operations remain in ChatScreen.
extension _PrivateMessageComposer on _ChatScreenState {
  Widget _buildMessageInput() {
    if (_isRecordingVoice)
      return _withVoicePointerBridge(
        PrivateVoiceRecordingComposer(
          replyPreview: PrivateComposerReplyPreview(
            replyMessage: _replyToMessage,
            currentUser: SocketService.instance.currentUser ?? '',
            languageCode: AppLanguageService.instance.code.value,
            onCancel: _cancelReply,
          ),
          duration: _voiceRecordDuration,
          languageCode: AppLanguageService.instance.code.value,
          onCancel: () => _finishVoiceRecording(send: false),
          onSend: () => _finishVoiceRecording(send: true),
        ),
      );
    return _withVoicePointerBridge(
      Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTypingIndicator(),
          PrivateComposerReplyPreview(
            replyMessage: _replyToMessage,
            currentUser: SocketService.instance.currentUser ?? '',
            languageCode: AppLanguageService.instance.code.value,
            onCancel: _cancelReply,
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(10, 5, 10, 9),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [FenyvoPalette.surfaceSoft, FenyvoPalette.rail],
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: FenyvoPalette.line),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x4A000000),
                  blurRadius: 16,
                  offset: Offset(0, 7),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
            child: SafeArea(
              top: false,
              minimum: const EdgeInsets.only(bottom: 1),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: Platform.isWindows ? 800 : 920,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton.outlined(
                        tooltip: _chatText('attachment'),
                        onPressed: _sendingPrivateMedia
                            ? null
                            : () => unawaited(_showPrivateAttachmentMenu()),
                        icon: _sendingPrivateMedia
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.add_circle_outline_rounded,
                                color: FenyvoPalette.gold,
                              ),
                        style: IconButton.styleFrom(
                          side: BorderSide(
                            color: FenyvoPalette.gold.withValues(alpha: .58),
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: CallbackShortcuts(
                          bindings: Platform.isWindows
                              ? <ShortcutActivator, VoidCallback>{
                                  const SingleActivator(
                                    LogicalKeyboardKey.enter,
                                  ): _sendMessage,
                                  const SingleActivator(
                                    LogicalKeyboardKey.escape,
                                  ): _cancelReply,
                                }
                              : const <ShortcutActivator, VoidCallback>{},
                          child: TextField(
                            key: const ValueKey('private-composer'),
                            controller: _messageController,
                            focusNode: _messageFocusNode,
                            onTap: () {
                              if (_emojiVisible)
                                _updateComposerState(
                                  () => _emojiVisible = false,
                                );
                            },
                            autofocus: false,
                            style: const TextStyle(
                              color: FenyvoPalette.ink,
                              fontSize: 16,
                            ),
                            keyboardType: TextInputType.multiline,
                            minLines: 1,
                            maxLines: 6,
                            textInputAction: TextInputAction.newline,
                            onChanged: _handleTextChanged,
                            decoration: InputDecoration(
                              hintText: _chatText('messageHint'),
                              fillColor: FenyvoPalette.canvasDeep.withValues(
                                alpha: .72,
                              ),
                              filled: true,
                              suffixIcon: IconButton(
                                tooltip: _chatText('emoji'),
                                onPressed: _openComposerEmoji,
                                icon: const Icon(
                                  Icons.emoji_emotions_outlined,
                                  color: FenyvoPalette.ink,
                                ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(26),
                                borderSide: const BorderSide(
                                  color: FenyvoPalette.line,
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(26),
                                borderSide: const BorderSide(
                                  color: FenyvoPalette.line,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(26),
                                borderSide: BorderSide(
                                  color: FenyvoPalette.gold.withValues(
                                    alpha: .72,
                                  ),
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 13,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_messageController.text.trim().isEmpty)
                        PrivateVoiceRecordButton(
                          icon: _videoNoteMode
                              ? Icons.videocam_rounded
                              : Icons.mic_rounded,
                          tooltip: _videoNoteMode
                              ? _videoNoteText(
                                  'Удерживайте для записи видео',
                                  'Утримуйте для запису відео',
                                  'Hold to record video',
                                )
                              : AppLanguageService.instance.text(
                                  'chatHoldToRecord',
                                ),
                          onTap: _togglePrivateVideoNoteMode,
                          onLongPressStart: _videoNoteMode
                              ? _beginHexVideoHold
                              : _handleVoiceLongPressStart,
                          onLongPressMoveUpdate: _videoNoteMode
                              ? _moveHexVideoHold
                              : _handleVoiceLongPressMove,
                          onLongPressEnd: _videoNoteMode
                              ? (_) => _endHexVideoHold()
                              : _handleVoiceLongPressEnd,
                        )
                      else
                        SizedBox(
                          width: 48,
                          height: 48,
                          child: IconButton.filled(
                            tooltip: Platform.isWindows
                                ? _chatText('sendEnter')
                                : _chatText('send'),
                            onPressed: _sendMessage,
                            style: IconButton.styleFrom(
                              backgroundColor: FenyvoPalette.gold,
                              foregroundColor: FenyvoPalette.onGold,
                            ),
                            icon: const Icon(Icons.send_rounded),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
