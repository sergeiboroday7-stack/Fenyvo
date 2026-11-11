part of '../screens/chat_screen.dart';

/// Existing translation UI moved into this Dart library part.
/// Requests and E2EE policy remain connected to ChatScreen.
String _privateTranslationUiText(String key) {
  final configured = AppLanguageService.instance.code.value;
  final language = configured == 'system'
      ? WidgetsBinding.instance.platformDispatcher.locale.languageCode
      : configured;

  const values = <String, Map<String, String>>{
    'ru': {
      'title': 'Перевод сообщения',
      'original': 'ОРИГИНАЛ',
      'translateTo': 'ПЕРЕВЕСТИ НА',
      'loading': 'Переводим...',
      'translate': 'Перевести',
      'result': 'ПЕРЕВОД',
      'copied': 'Перевод скопирован',
      'copy': 'Скопировать перевод',
      'error': 'Не удалось перевести. Проверь интернет и попробуй ещё раз.',
    },
    'uk': {
      'title': 'Переклад повідомлення',
      'original': 'ОРИГІНАЛ',
      'translateTo': 'ПЕРЕКЛАСТИ НА',
      'loading': 'Перекладаємо...',
      'translate': 'Перекласти',
      'result': 'ПЕРЕКЛАД',
      'copied': 'Переклад скопійовано',
      'copy': 'Скопіювати переклад',
      'error': 'Не вдалося перекласти. Перевір інтернет і спробуй ще раз.',
    },
    'en': {
      'title': 'Message translation',
      'original': 'ORIGINAL',
      'translateTo': 'TRANSLATE TO',
      'loading': 'Translating...',
      'translate': 'Translate',
      'result': 'TRANSLATION',
      'copied': 'Translation copied',
      'copy': 'Copy translation',
      'error':
          'Could not translate. Check your internet connection and try again.',
    },
  };

  final selected = values[language] ?? values['en']!;
  return selected[key] ?? key;
}

extension _PrivateTranslationSheet on _ChatScreenState {
  Future<void> _translateMessage(Map<String, dynamic> message) async {
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

    var targetLanguage = 'uk';
    var translatedText = '';
    var isLoading = false;
    String? errorText;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> performTranslation() async {
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
              });

              try {
                final result = await _requestTranslation(
                  text: originalText,
                  targetLanguage: targetLanguage,
                );

                if (!sheetContext.mounted) {
                  return;
                }

                setSheetState(() {
                  translatedText = result;
                  isLoading = false;
                });
              } catch (_) {
                if (!sheetContext.mounted) {
                  return;
                }

                setSheetState(() {
                  translatedText = '';
                  isLoading = false;
                  errorText = _privateTranslationUiText('error');
                });
              }
            }

            Widget languageButton({
              required String code,
              required String label,
            }) {
              final selected = targetLanguage == code;

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: OutlinedButton(
                    onPressed: isLoading
                        ? null
                        : () {
                            setSheetState(() {
                              targetLanguage = code;
                              translatedText = '';
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
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              );
            }

            return SafeArea(
              top: false,
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.88,
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
                            Icons.translate_rounded,
                            color: _ChatScreenState._gold,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _privateTranslationUiText('title'),
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
                        _privateTranslationUiText('original'),
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
                        _privateTranslationUiText('translateTo'),
                        style: TextStyle(
                          color: _ChatScreenState._gold,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.1,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Row(
                        children: [
                          languageButton(
                            code: 'uk',
                            label: '\u0423\u043A\u0440\u0430\u0457\u043D\u0441\u044C\u043A\u0430',
                          ),
                          languageButton(
                            code: 'ru',
                            label: '\u0420\u0443\u0441\u0441\u043A\u0438\u0439',
                          ),
                          languageButton(code: 'en', label: 'English'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          languageButton(
                            code: 'ar',
                            label: '\u0627\u0644\u0639\u0631\u0628\u064A\u0629',
                          ),
                          languageButton(code: 'zh-CN', label: '\u4E2D\u6587'),
                          languageButton(
                            code: 'ja',
                            label: '\u65E5\u672C\u8A9E',
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: isLoading ? null : performTranslation,
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
                              : const Icon(Icons.translate_rounded),
                          label: Text(
                            isLoading
                                ? _privateTranslationUiText('loading')
                                : _privateTranslationUiText('translate'),
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
                      if (translatedText.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Text(
                          _privateTranslationUiText('result'),
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
                            translatedText,
                            textDirection: targetLanguage == 'ar'
                                ? TextDirection.rtl
                                : TextDirection.ltr,
                            textAlign: targetLanguage == 'ar'
                                ? TextAlign.right
                                : TextAlign.left,
                            style: const TextStyle(
                              color: FenyvoPalette.ink,
                              fontSize: 16,
                              height: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: translatedText),
                              );

                              if (!sheetContext.mounted) {
                                return;
                              }

                              ScaffoldMessenger.of(sheetContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _privateTranslationUiText('copied'),
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
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(15),
                              ),
                            ),
                            icon: const Icon(Icons.copy_rounded),
                            label: Text(
                              _privateTranslationUiText('copy'),
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
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
