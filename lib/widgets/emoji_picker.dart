import 'package:flutter/material.dart';

import '../theme/spartan_theme.dart';

/// Replaces the current selection, preserving surrounding text and UTF-16 offsets.
void insertComposerEmoji(TextEditingController controller, String emoji) {
  final value = controller.value;
  final selection = value.selection;
  final start = selection.isValid
      ? selection.start.clamp(0, value.text.length)
      : value.text.length;
  final end = selection.isValid
      ? selection.end.clamp(start, value.text.length)
      : start;
  controller.value = TextEditingValue(
    text: value.text.replaceRange(start, end, emoji),
    selection: TextSelection.collapsed(offset: start + emoji.length),
  );
}

Future<void> showComposerEmojiPicker(
  BuildContext context, {
  required TextEditingController controller,
  required VoidCallback onChanged,
}) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  useSafeArea: true,
  builder: (context) => ComposerEmojiPanel(
    controller: controller,
    onChanged: onChanged,
    onClose: () => Navigator.pop(context),
  ),
);

/// Inline beneath the composer: never covers the draft or send button.
class ComposerEmojiPanel extends StatefulWidget {
  const ComposerEmojiPanel({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.onClose,
    this.height = 280,
  });
  final TextEditingController controller;
  final VoidCallback onChanged;
  final VoidCallback onClose;
  final double height;
  @override
  State<ComposerEmojiPanel> createState() => _EmojiSheetState();
}

class _EmojiSheetState extends State<ComposerEmojiPanel> {
  int _category = 0;
  static const _categories = ['Смайлики', 'Жесты', 'Сердца', 'Разное'];
  static const _emoji = [
    [
      '😀',
      '😃',
      '😄',
      '😁',
      '😊',
      '🙂',
      '😉',
      '😍',
      '🥰',
      '😘',
      '😎',
      '🤗',
      '😂',
      '🤣',
      '🥹',
      '😅',
      '🙃',
      '😇',
      '🤔',
      '😐',
      '😔',
      '😢',
      '😭',
      '😮',
      '😴',
      '🥳',
      '🤩',
      '😋',
      '😌',
      '😏',
      '😬',
      '😳',
    ],
    [
      '👍',
      '👎',
      '👏',
      '🙌',
      '🤝',
      '🙏',
      '✊',
      '✌️',
      '🤞',
      '💪',
      '👋',
      '🤙',
      '🫶',
      '👌',
      '☝️',
      '👀',
      '🫂',
      '💯',
      '✅',
      '✨',
      '🎉',
      '🔥',
      '💬',
      '💤',
    ],
    [
      '❤️',
      '🧡',
      '💛',
      '💚',
      '💙',
      '💜',
      '🤍',
      '🖤',
      '🤎',
      '🩷',
      '💔',
      '❤️‍🔥',
      '💕',
      '💞',
      '💓',
      '💗',
      '💖',
      '💝',
      '💘',
      '❣️',
      '💌',
      '🌹',
      '🌷',
      '🌻',
    ],
    [
      '☀️',
      '🌙',
      '⭐',
      '🌈',
      '☕',
      '🍰',
      '🍕',
      '🍎',
      '🎂',
      '🎁',
      '🎵',
      '🎧',
      '📷',
      '📹',
      '📞',
      '🏠',
      '🚗',
      '✈️',
      '⚽',
      '🏆',
      '🐶',
      '🐱',
      '🌿',
      '📌',
    ],
  ];
  @override
  Widget build(BuildContext context) => SizedBox(
    key: const ValueKey('composer-emoji-panel'),
    height: widget.height,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Смайлики',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Закрыть смайлики',
                onPressed: widget.onClose,
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _categories.length,
            separatorBuilder: (_, index) => const SizedBox(width: 8),
            itemBuilder: (_, index) => ChoiceChip(
              label: Text(_categories[index]),
              selected: _category == index,
              onSelected: (_) => setState(() => _category = index),
            ),
          ),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _emoji[_category].length,
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 52,
              mainAxisExtent: 48,
            ),
            itemBuilder: (_, index) {
              final emoji = _emoji[_category][index];
              return Semantics(
                label: 'Вставить $emoji',
                button: true,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    insertComposerEmoji(widget.controller, emoji);
                    widget.onChanged();
                  },
                  child: Center(
                    child: Text(
                      emoji,
                      style: const TextStyle(
                        fontSize: 26,
                        fontFamilyFallback: [
                          'Segoe UI Emoji',
                          'Noto Color Emoji',
                          'Apple Color Emoji',
                        ],
                        color: SpartanPalette.ink,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    ),
  );
}
