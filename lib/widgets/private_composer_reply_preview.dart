import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/fenyvo_theme.dart';

/// Reply preview shared by text and voice composers.
/// Reply selection and cancellation remain in the parent chat.
class PrivateComposerReplyPreview extends StatelessWidget {
  const PrivateComposerReplyPreview({
    super.key,
    required this.replyMessage,
    required this.currentUser,
    required this.languageCode,
    required this.onCancel,
  });

  final Map<String, dynamic>? replyMessage;
  final String currentUser;
  final String languageCode;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final language = languageCode.toLowerCase().split(RegExp(r'[-_]')).first;

    final selfLabel = switch (language) {
      'uk' => 'Ви',
      'en' => 'You',
      _ => 'Вы',
    };

    final replyLabel = switch (language) {
      'uk' => 'Відповідь',
      'en' => 'Reply',
      _ => 'Ответ',
    };

    final reply = replyMessage;

    if (reply == null) {
      return const SizedBox.shrink();
    }

    final currentUser = this.currentUser;

    final from = reply['from']?.toString().trim() ?? '';

    final text = reply['text']?.toString().trim() ?? '';

    final author = from == currentUser ? selfLabel : from;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      decoration: BoxDecoration(
        color: FenyvoPalette.surface,
        border: Border(
          top: BorderSide(
            color: FenyvoPalette.gold.withValues(alpha: 0.22),
            width: 0.8,
          ),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 38,
            decoration: BoxDecoration(
              color: FenyvoPalette.blue,
              borderRadius: BorderRadius.circular(3),
              boxShadow: [
                BoxShadow(
                  color: FenyvoPalette.gold.withValues(alpha: 0.06),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  author.isEmpty ? replyLabel : author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: FenyvoPalette.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: FenyvoPalette.secondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (Platform.isWindows) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: FenyvoPalette.blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: FenyvoPalette.gold.withValues(alpha: 0.18),
                  width: 0.7,
                ),
              ),
              child: const Text(
                'ESC',
                style: TextStyle(
                  color: FenyvoPalette.secondary,
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            const SizedBox(width: 2),
          ],
          IconButton(
            onPressed: onCancel,
            visualDensity: VisualDensity.compact,
            icon: const Icon(
              Icons.close_rounded,
              color: FenyvoPalette.gold,
              size: 21,
            ),
          ),
        ],
      ),
    );
  }
}
