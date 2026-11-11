part of '../screens/chat_screen.dart';

/// Message ChatGPT sheet extracted from ChatScreen.
/// Existing external-text E2EE guards and request behavior are retained.
String _privateChatGptUiText(String key) {
  final configured = AppLanguageService.instance.code.value;
  final language = configured == 'system'
      ? WidgetsBinding.instance.platformDispatcher.locale.languageCode
      : configured;

  const values = <String, Map<String, String>>{
    'ru': {
      'emptyMessage': 'Пустое сообщение',
      'notConnected': 'Нет подключения к серверу',
      'timeout': 'ChatGPT не ответил вовремя',
      'reply': 'Предложить ответ',
      'explain': 'Объяснить',
      'rewrite': 'Переформулировать',
      'shorter': 'Сделать короче',
      'title': 'ChatGPT для сообщения',
      'message': 'СООБЩЕНИЕ',
      'chooseAction': 'ЧТО СДЕЛАТЬ',
      'thinking': 'ChatGPT думает...',
      'run': 'Выполнить',
      'result': 'РЕЗУЛЬТАТ',
      'copied': 'Ответ ChatGPT скопирован',
      'copy': 'Копировать',
      'insert': 'Вставить',
      'disclosure':
          'Текст отправляется в ChatGPT только после выбора действия.',
    },
    'uk': {
      'emptyMessage': 'Порожнє повідомлення',
      'notConnected': 'Немає з’єднання із сервером',
      'timeout': 'ChatGPT не відповів вчасно',
      'reply': 'Запропонувати відповідь',
      'explain': 'Пояснити',
      'rewrite': 'Перефразувати',
      'shorter': 'Скоротити',
      'title': 'ChatGPT для повідомлення',
      'message': 'ПОВІДОМЛЕННЯ',
      'chooseAction': 'ЩО ЗРОБИТИ',
      'thinking': 'ChatGPT обробляє...',
      'run': 'Виконати',
      'result': 'РЕЗУЛЬТАТ',
      'copied': 'Відповідь ChatGPT скопійовано',
      'copy': 'Копіювати',
      'insert': 'Вставити',
      'disclosure': 'Текст надсилається до ChatGPT лише після вибору дії.',
    },
    'en': {
      'emptyMessage': 'Empty message',
      'notConnected': 'Not connected to the server',
      'timeout': 'ChatGPT did not respond in time',
      'reply': 'Suggest reply',
      'explain': 'Explain',
      'rewrite': 'Rephrase',
      'shorter': 'Make shorter',
      'title': 'ChatGPT for message',
      'message': 'MESSAGE',
      'chooseAction': 'CHOOSE ACTION',
      'thinking': 'ChatGPT is thinking...',
      'run': 'Run',
      'result': 'RESULT',
      'copied': 'ChatGPT response copied',
      'copy': 'Copy',
      'insert': 'Insert',
      'disclosure': 'Text is sent to ChatGPT only after you choose an action.',
    },
  };

  final selected = values[language] ?? values['en']!;
  return selected[key] ?? key;
}

extension _PrivateChatGptSheet on _ChatScreenState {
  Future<void> _showChatGptSheet(Map<String, dynamic> message) async {
    if (!PrivateExternalTextPolicy.canSendMessage(
      message,
      isChatE2eeActive: SocketService.instance.isE2eeActiveWith(
        widget.targetUser,
      ),
    )) {
      return;
    }
    final originalText = message['text']?.toString().trim() ?? '';

    if (originalText.isEmpty || !mounted) {
      return;
    }

    var selectedAction = 'reply';
    var resultText = '';
    var isLoading = false;
    String? errorText;

    final actionLabels = <String, String>{
      'reply': _privateChatGptUiText('reply'),
      'explain': _privateChatGptUiText('explain'),
      'rewrite': _privateChatGptUiText('rewrite'),
      'shorter': _privateChatGptUiText('shorter'),
    };

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> performAction() async {
              if (!PrivateExternalTextPolicy.canSendMessage(
                message,
                isChatE2eeActive: SocketService.instance.isE2eeActiveWith(
                  widget.targetUser,
                ),
              )) {
                return;
              }
              if (isLoading) {
                return;
              }

              setSheetState(() {
                isLoading = true;
                errorText = null;
                resultText = '';
              });

              try {
                final result = await _requestChatGpt(
                  action: selectedAction,
                  text: originalText,
                );

                if (!sheetContext.mounted) {
                  return;
                }

                setSheetState(() {
                  resultText = result;
                  isLoading = false;
                });
              } catch (error) {
                if (!sheetContext.mounted) {
                  return;
                }

                var message = error.toString();

                if (message.startsWith('Exception: ')) {
                  message = message.substring(11);
                }

                setSheetState(() {
                  isLoading = false;
                  errorText = message;
                });
              }
            }

            Widget actionButton({
              required String action,
              required IconData icon,
            }) {
              final selected = selectedAction == action;

              return OutlinedButton.icon(
                onPressed: isLoading
                    ? null
                    : () {
                        setSheetState(() {
                          selectedAction = action;
                          resultText = '';
                          errorText = null;
                        });
                      },
                style: OutlinedButton.styleFrom(
                  foregroundColor: selected
                      ? FenyvoPalette.ink
                      : FenyvoPalette.ink,
                  backgroundColor: selected
                      ? FenyvoPalette.blue
                      : FenyvoPalette.surface,
                  side: BorderSide(
                    color: selected
                        ? _ChatScreenState._gold
                        : _ChatScreenState._gold.withValues(alpha: 0.45),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                icon: Icon(icon, size: 17),
                label: Text(
                  actionLabels[action] ?? action,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              );
            }

            return SafeArea(
              top: false,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.90,
                ),
                decoration: const BoxDecoration(
                  color: FenyvoPalette.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(
                    top: BorderSide(color: _ChatScreenState._gold, width: 1.2),
                  ),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Align(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: FenyvoPalette.line,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome_rounded,
                            color: _ChatScreenState._gold,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _privateChatGptUiText('title'),
                              style: TextStyle(
                                color: FenyvoPalette.ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _privateChatGptUiText('message'),
                        style: TextStyle(
                          color: _ChatScreenState._gold,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: FenyvoPalette.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: _ChatScreenState._gold.withValues(
                              alpha: 0.30,
                            ),
                          ),
                        ),
                        child: SelectableText(
                          originalText,
                          style: const TextStyle(
                            color: FenyvoPalette.ink,
                            fontSize: 15,
                            height: 1.35,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        _privateChatGptUiText('chooseAction'),
                        style: TextStyle(
                          color: _ChatScreenState._gold,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          actionButton(
                            action: 'reply',
                            icon: Icons.reply_rounded,
                          ),
                          actionButton(
                            action: 'explain',
                            icon: Icons.lightbulb_outline_rounded,
                          ),
                          actionButton(
                            action: 'rewrite',
                            icon: Icons.edit_note_rounded,
                          ),
                          actionButton(
                            action: 'shorter',
                            icon: Icons.compress_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: isLoading ? null : performAction,
                          style: FilledButton.styleFrom(
                            backgroundColor: FenyvoPalette.blue,
                            foregroundColor: FenyvoPalette.ink,
                            disabledBackgroundColor: _ChatScreenState._gold
                                .withValues(alpha: 0.35),
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          icon: isLoading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: FenyvoPalette.ink,
                                  ),
                                )
                              : const Icon(Icons.auto_awesome_rounded),
                          label: Text(
                            isLoading
                                ? _privateChatGptUiText('thinking')
                                : actionLabels[selectedAction] ??
                                      _privateChatGptUiText('run'),
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                      if (errorText != null) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.redAccent.withValues(alpha: 0.45),
                            ),
                          ),
                          child: Text(
                            errorText!,
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                      if (resultText.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Text(
                          _privateChatGptUiText('result'),
                          style: TextStyle(
                            color: _ChatScreenState._gold,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.1,
                          ),
                        ),
                        const SizedBox(height: 7),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: FenyvoPalette.surface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: _ChatScreenState._gold.withValues(
                                alpha: 0.55,
                              ),
                            ),
                          ),
                          child: SelectableText(
                            resultText,
                            style: const TextStyle(
                              color: FenyvoPalette.ink,
                              fontSize: 16,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  await Clipboard.setData(
                                    ClipboardData(text: resultText),
                                  );

                                  if (!sheetContext.mounted) {
                                    return;
                                  }

                                  ScaffoldMessenger.of(
                                    sheetContext,
                                  ).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        _privateChatGptUiText('copied'),
                                      ),
                                      backgroundColor: FenyvoPalette.surface,
                                      duration: Duration(milliseconds: 1000),
                                    ),
                                  );
                                },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: _ChatScreenState._gold,
                                  side: BorderSide(
                                    color: _ChatScreenState._gold.withValues(
                                      alpha: 0.65,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                                icon: const Icon(Icons.copy_rounded),
                                label: Text(
                                  _privateChatGptUiText('copy'),
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () {
                                  final value = resultText.trim();

                                  if (value.isEmpty) {
                                    return;
                                  }

                                  Navigator.of(sheetContext).pop();

                                  _messageController.text = value;
                                  _messageController.selection =
                                      TextSelection.collapsed(
                                        offset: value.length,
                                      );
                                  _messageFocusNode.requestFocus();
                                },
                                style: FilledButton.styleFrom(
                                  backgroundColor: FenyvoPalette.blue,
                                  foregroundColor: FenyvoPalette.ink,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                ),
                                icon: const Icon(Icons.input_rounded),
                                label: Text(
                                  _privateChatGptUiText('insert'),
                                  style: TextStyle(fontWeight: FontWeight.w800),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      Text(
                        _privateChatGptUiText('disclosure'),
                        style: TextStyle(
                          color: FenyvoPalette.ink.withValues(alpha: 0.45),
                          fontSize: 11,
                          height: 1.3,
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
  }
}
