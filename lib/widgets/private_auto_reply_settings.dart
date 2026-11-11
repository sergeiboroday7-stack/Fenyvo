part of '../screens/chat_screen.dart';

/// FENYVO AI per-chat auto-reply settings.
/// Existing localization, network operations and settings are preserved.
extension _PrivateAutoReplySettings on _ChatScreenState {
  Future<void> _showAutoReplySettings() async {
    if (!SocketService.instance.isConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_chatText('aiInternetRequired')),
            backgroundColor: Colors.red,
          ),
        );
      }

      return;
    }

    const legacyGoal =
        '\u041F\u043E\u0434\u0434\u0435\u0440\u0436\u0438\u0432\u0430\u0442\u044C \u043F\u043E\u043B\u0435\u0437\u043D\u044B\u0439, \u0443\u0432\u0430\u0436\u0438\u0442\u0435\u043B\u044C\u043D\u044B\u0439 \u0434\u0438\u0430\u043B\u043E\u0433 \u0438 \u043F\u043E\u043C\u043E\u0433\u0430\u0442\u044C \u043F\u0440\u0438\u0439\u0442\u0438 \u043A \u043D\u0443\u0436\u043D\u043E\u043C\u0443 \u0440\u0435\u0437\u0443\u043B\u044C\u0442\u0430\u0442\u0443.';
    const legacyPrompt =
        '\u041E\u0442\u0432\u0435\u0447\u0430\u0439 \u043A\u043E\u0440\u043E\u0442\u043A\u043E, \u0435\u0441\u0442\u0435\u0441\u0442\u0432\u0435\u043D\u043D\u043E \u0438 \u0434\u0440\u0443\u0436\u0435\u043B\u044E\u0431\u043D\u043E. \u041E\u0442\u0432\u0435\u0447\u0430\u0439 \u043D\u0430 \u044F\u0437\u044B\u043A\u0435 \u0441\u043E\u0431\u0435\u0441\u0435\u0434\u043D\u0438\u043A\u0430. \u041D\u0435 \u0434\u043E\u0431\u0430\u0432\u043B\u044F\u0439 \u043F\u043E\u044F\u0441\u043D\u0435\u043D\u0438\u0439 \u043E\u0442 \u0441\u0435\u0431\u044F.';
    const legacyPromptWithEverything =
        '\u041E\u0442\u0432\u0435\u0447\u0430\u0439 \u043A\u043E\u0440\u043E\u0442\u043A\u043E, \u0435\u0441\u0442\u0435\u0441\u0442\u0432\u0435\u043D\u043D\u043E \u0438 \u0434\u0440\u0443\u0436\u0435\u043B\u044E\u0431\u043D\u043E. \u041E\u0442\u0432\u0435\u0447\u0430\u0439 \u043D\u0430 \u044F\u0437\u044B\u043A\u0435 \u0441\u043E\u0431\u0435\u0441\u0435\u0434\u043D\u0438\u043A\u0430. \u041D\u0435 \u0434\u043E\u0431\u0430\u0432\u043B\u044F\u0439 \u043F\u043E\u044F\u0441\u043D\u0435\u043D\u0438\u0439 \u043E\u0442 \u0441\u0435\u0431\u044F. \u0413\u043E\u0432\u043E\u0440\u0438 \u043E\u0431\u043E \u0432\u0441\u0451\u043C.';
    const legacyBoundaries =
        '\u041D\u0435 \u0434\u0430\u0432\u0438, \u043D\u0435 \u0443\u0433\u0440\u043E\u0436\u0430\u0439, \u043D\u0435 \u043E\u0431\u043C\u0430\u043D\u044B\u0432\u0430\u0439 \u0438 \u043D\u0435 \u043C\u0430\u043D\u0438\u043F\u0443\u043B\u0438\u0440\u0443\u0439. \u0423\u0432\u0430\u0436\u0430\u0439 \u043E\u0442\u043A\u0430\u0437 \u0438 \u043F\u0440\u043E\u0441\u044C\u0431\u0443 \u043F\u0440\u0435\u043A\u0440\u0430\u0442\u0438\u0442\u044C \u043E\u0431\u0449\u0435\u043D\u0438\u0435.';
    final goalController = TextEditingController(
      text:
          (_autoReplyGoal == legacyGoal ||
              (_autoReplyGoal.startsWith(
                    '\u041F\u043E\u0434\u0434\u0435\u0440\u0436\u0438\u0432\u0430\u0442\u044C \u043F\u043E\u043B\u0435\u0437\u043D\u044B\u0439',
                  ) &&
                  _autoReplyGoal.length < 220))
          ? _chatText('autoGoalDefault')
          : _autoReplyGoal,
    );
    final promptController = TextEditingController(
      text:
          (_autoReplyPrompt == legacyPrompt ||
              _autoReplyPrompt == legacyPromptWithEverything ||
              (_autoReplyPrompt.startsWith(
                    '\u041E\u0442\u0432\u0435\u0447\u0430\u0439 \u043A\u043E\u0440\u043E\u0442\u043A\u043E',
                  ) &&
                  _autoReplyPrompt.contains(
                    '\u044F\u0437\u044B\u043A\u0435 \u0441\u043E\u0431\u0435\u0441\u0435\u0434\u043D\u0438\u043A\u0430',
                  )))
          ? _chatText('autoPromptDefault')
          : _autoReplyPrompt,
    );
    final contextController = TextEditingController(text: _autoReplyContext);
    final boundariesController = TextEditingController(
      text: _autoReplyBoundaries == legacyBoundaries
          ? _chatText('autoBoundariesDefault')
          : _autoReplyBoundaries,
    );

    var enabled = _autoReplyEnabled;
    var mode = _autoReplyMode;
    var idleSeconds = _autoReplyIdleSeconds;
    var delaySeconds = _autoReplyDelaySeconds;

    Widget buildLabel(String text) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          text,
          style: const TextStyle(
            color: FenyvoPalette.ink,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    InputDecoration inputDecoration(String hint) {
      return InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: FenyvoPalette.muted),
        filled: true,
        fillColor: FenyvoPalette.surface,
        counterStyle: const TextStyle(color: FenyvoPalette.muted),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: FenyvoPalette.line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: _ChatScreenState._gold),
        ),
      );
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final bottomInset = MediaQuery.viewInsetsOf(sheetContext).bottom;

            return AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 620),
                decoration: const BoxDecoration(
                  color: FenyvoPalette.canvas,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: FenyvoPalette.line,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: FenyvoPalette.blue.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _ChatScreenState._gold.withValues(
                                  alpha: 0.55,
                                ),
                              ),
                            ),
                            child: const Icon(
                              Icons.smart_toy_rounded,
                              color: _ChatScreenState._gold,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _chatText('aiAutoTitle'),
                                  style: const TextStyle(
                                    color: FenyvoPalette.ink,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _chatText('aiSeparateSession', {
                                    'user': widget.targetUser,
                                  }),
                                  style: const TextStyle(
                                    color: FenyvoPalette.secondary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        decoration: BoxDecoration(
                          color: FenyvoPalette.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: enabled
                                ? _ChatScreenState._gold.withValues(alpha: 0.55)
                                : FenyvoPalette.line,
                          ),
                        ),
                        child: SwitchListTile.adaptive(
                          value: enabled,
                          onChanged: (value) {
                            setSheetState(() {
                              enabled = value;
                            });

                            // V616: switching OFF is an emergency stop and is
                            // applied to the server immediately. Switching ON
                            // still waits for the Save button so the user can
                            // finish goal/style/context settings first.
                            if (!value) {
                              SocketService.instance.setAutoReplySettings(
                                peer: widget.targetUser,
                                enabled: false,
                                mode: mode,
                                idleSeconds: idleSeconds,
                                goal: goalController.text.trim(),
                                prompt: promptController.text.trim(),
                                context: contextController.text.trim(),
                                boundaries: boundariesController.text.trim(),
                                delaySeconds: delaySeconds,
                              );

                              if (mounted) {
                                _autoReplyApplyState(() {
                                  _autoReplyEnabled = false;
                                });
                              }
                            }
                          },
                          title: Text(
                            enabled
                                ? _chatText('autoReplyEnabled')
                                : _chatText('autoReplyDisabled'),
                            style: const TextStyle(
                              color: FenyvoPalette.ink,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            _chatText('autoReplyDescription'),
                            style: const TextStyle(
                              color: FenyvoPalette.secondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      buildLabel(_chatText('aiParticipationMode')),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children:
                            <Map<String, String>>[
                              {
                                'id': 'auto',
                                'label': '\u26A1 ${_chatText('modeAuto')}',
                              },
                              {
                                'id': 'suggest',
                                'label':
                                    '\u{1F4A1} ${_chatText('modeSuggest')}',
                              },
                              {
                                'id': 'idle',
                                'label': '\u23F3 ${_chatText('modeIdle')}',
                              },
                              {
                                'id': 'until_goal',
                                'label':
                                    '\u{1F3AF} ${_chatText('modeUntilGoal')}',
                              },
                            ].map((item) {
                              final id = item['id']!;
                              final selected = mode == id;

                              return ChoiceChip(
                                label: Text(item['label']!),
                                selected: selected,
                                onSelected: (_) {
                                  setSheetState(() {
                                    mode = id;
                                  });
                                },
                                selectedColor: _ChatScreenState._gold,
                                backgroundColor: FenyvoPalette.surface,
                                side: BorderSide(
                                  color: selected
                                      ? _ChatScreenState._gold
                                      : FenyvoPalette.line,
                                ),
                                labelStyle: TextStyle(
                                  color: selected
                                      ? FenyvoPalette.ink
                                      : FenyvoPalette.secondary,
                                  fontWeight: FontWeight.w700,
                                ),
                                showCheckmark: false,
                              );
                            }).toList(),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        mode == 'suggest'
                            ? '\u{1F4A1} ${_chatText('modeSuggestDescription')}'
                            : mode == 'idle'
                            ? '\u23F3 ${_chatText('modeIdleDescription')}'
                            : mode == 'until_goal'
                            ? '\u{1F3AF} ${_chatText('modeUntilGoalDescription')}'
                            : '\u26A1 ${_chatText('modeAutoDescription')}',
                        style: const TextStyle(
                          color: FenyvoPalette.secondary,
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                      if (mode == 'idle') ...[
                        const SizedBox(height: 14),
                        buildLabel(_chatText('idleDelayLabel')),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <int>[30, 60, 120, 300].map((seconds) {
                            final selected = idleSeconds == seconds;
                            final label = seconds < 60
                                ? _chatText('secondsShort', {'count': seconds})
                                : _chatText('minutesShort', {
                                    'count': seconds ~/ 60,
                                  });

                            return ChoiceChip(
                              label: Text(label),
                              selected: selected,
                              onSelected: (_) {
                                setSheetState(() {
                                  idleSeconds = seconds;
                                });
                              },
                              selectedColor: _ChatScreenState._gold,
                              backgroundColor: FenyvoPalette.surface,
                              side: BorderSide(
                                color: selected
                                    ? _ChatScreenState._gold
                                    : FenyvoPalette.line,
                              ),
                              labelStyle: TextStyle(
                                color: selected
                                    ? FenyvoPalette.ink
                                    : FenyvoPalette.secondary,
                                fontWeight: FontWeight.w700,
                              ),
                              showCheckmark: false,
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 18),
                      buildLabel(_chatText('conversationGoal')),
                      TextField(
                        controller: goalController,
                        maxLength: 500,
                        minLines: 2,
                        maxLines: 5,
                        style: const TextStyle(color: FenyvoPalette.ink),
                        decoration: inputDecoration(
                          _chatText('conversationGoalHint'),
                        ),
                      ),
                      const SizedBox(height: 6),
                      buildLabel(_chatText('conversationStyle')),
                      TextField(
                        controller: promptController,
                        maxLength: 600,
                        minLines: 2,
                        maxLines: 5,
                        style: const TextStyle(color: FenyvoPalette.ink),
                        decoration: inputDecoration(
                          _chatText('conversationStyleHint'),
                        ),
                      ),
                      const SizedBox(height: 6),
                      buildLabel(_chatText('aiContext')),
                      TextField(
                        controller: contextController,
                        maxLength: 800,
                        minLines: 2,
                        maxLines: 6,
                        style: const TextStyle(color: FenyvoPalette.ink),
                        decoration: inputDecoration(_chatText('aiContextHint')),
                      ),
                      const SizedBox(height: 6),
                      buildLabel(_chatText('aiBoundaries')),
                      TextField(
                        controller: boundariesController,
                        maxLength: 500,
                        minLines: 2,
                        maxLines: 5,
                        style: const TextStyle(color: FenyvoPalette.ink),
                        decoration: inputDecoration(
                          _chatText('aiBoundariesHint'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      buildLabel(_chatText('replyDelay')),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <int>[3, 5, 10].map((seconds) {
                          final selected = delaySeconds == seconds;

                          return ChoiceChip(
                            label: Text(
                              _chatText('secondsShort', {'count': seconds}),
                            ),
                            selected: selected,
                            onSelected: (_) {
                              setSheetState(() {
                                delaySeconds = seconds;
                              });
                            },
                            selectedColor: _ChatScreenState._gold,
                            backgroundColor: FenyvoPalette.surface,
                            side: BorderSide(
                              color: selected
                                  ? _ChatScreenState._gold
                                  : FenyvoPalette.line,
                            ),
                            labelStyle: TextStyle(
                              color: selected
                                  ? FenyvoPalette.ink
                                  : FenyvoPalette.secondary,
                              fontWeight: FontWeight.w700,
                            ),
                            showCheckmark: false,
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: FenyvoPalette.blue.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(
                            color: _ChatScreenState._gold.withValues(
                              alpha: 0.20,
                            ),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              color: _ChatScreenState._gold,
                              size: 18,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                _chatText('autoReplyMemoryInfo'),
                                style: const TextStyle(
                                  color: FenyvoPalette.secondary,
                                  fontSize: 12,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            SocketService.instance.clearAutoReplyHistory(
                              widget.targetUser,
                            );
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: FenyvoPalette.secondary,
                            side: const BorderSide(color: FenyvoPalette.line),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.restart_alt_rounded),
                          label: Text(_chatText('restartAiDialog')),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            var goal = goalController.text.trim();
                            var prompt = promptController.text.trim();
                            final aiContext = contextController.text.trim();
                            var boundaries = boundariesController.text.trim();

                            if (goal.isEmpty) {
                              goal = _chatText('autoGoalDefault');
                            }

                            if (prompt.isEmpty) {
                              prompt = _chatText('autoPromptDefault');
                            }

                            if (boundaries.isEmpty) {
                              boundaries = _chatText('autoBoundariesDefault');
                            }

                            SocketService.instance.setAutoReplySettings(
                              peer: widget.targetUser,
                              enabled: enabled,
                              mode: mode,
                              idleSeconds: idleSeconds,
                              goal: goal,
                              prompt: prompt,
                              context: aiContext,
                              boundaries: boundaries,
                              delaySeconds: delaySeconds,
                            );

                            if (mounted) {
                              _autoReplyApplyState(() {
                                _autoReplyEnabled = enabled;
                                _autoReplyMode = mode;
                                _autoReplyIdleSeconds = idleSeconds;
                                _autoReplyGoal = goal;
                                _autoReplyPrompt = prompt;
                                _autoReplyContext = aiContext;
                                _autoReplyBoundaries = boundaries;
                                _autoReplyDelaySeconds = delaySeconds;
                                _autoReplyLoading = false;
                              });
                            }

                            Navigator.of(sheetContext).pop();
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: FenyvoPalette.blue,
                            foregroundColor: FenyvoPalette.ink,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(15),
                            ),
                          ),
                          icon: const Icon(Icons.save_rounded),
                          label: Text(
                            _chatText('saveGoalAndStart'),
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
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

    goalController.dispose();
    promptController.dispose();
    contextController.dispose();
    boundariesController.dispose();
  }
}
