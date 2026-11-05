import 'package:flutter/material.dart';

import '../services/legacy_media_regrant_result.dart';

typedef LegacyRegrantConfirm = Future<LegacyMediaRegrantResult> Function();

/// Explicit owner confirmation for sharing access to an existing file.
/// Does not transmit anything until the user taps the confirm button.
/// The caller must supply an authenticated, authorized regrant operation.
class LegacyMediaRegrantDialog extends StatefulWidget {
  const LegacyMediaRegrantDialog({
    super.key,
    required this.recipient,
    required this.languageCode,
    required this.onConfirm,
  });

  final String recipient;
  final String languageCode;
  final LegacyRegrantConfirm onConfirm;

  @override
  State<LegacyMediaRegrantDialog> createState() =>
      _LegacyMediaRegrantDialogState();
}

class _LegacyMediaRegrantDialogState
    extends State<LegacyMediaRegrantDialog> {
  bool _busy = false;
  LegacyMediaRegrantResult? _result;

  String get _language {
    final code = widget.languageCode.toLowerCase().split('-').first;
    return code == 'uk' || code == 'en' ? code : 'ru';
  }

  String _tr(String ru, String uk, String en) {
    switch (_language) {
      case 'uk':
        return uk;
      case 'en':
        return en;
      default:
        return ru;
    }
  }

  Future<void> _confirm() async {
    if (_busy || _result != null) return;

    setState(() => _busy = true);

    LegacyMediaRegrantResult result;
    try {
      result = await widget.onConfirm();
    } catch (_) {
      result = const LegacyMediaRegrantResult(
        approved: false,
        reason: 'REGRANT_FAILED',
      );
    }

    if (!mounted) return;

    setState(() {
      _busy = false;
      _result = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;

    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        title: Text(_tr(
          'Предоставить доступ к файлу?',
          'Надати доступ до файлу?',
          'Grant access to this file?',
        )),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_tr(
              'Получатель: ${widget.recipient}',
              'Одержувач: ${widget.recipient}',
              'Recipient: ${widget.recipient}',
            )),
            const SizedBox(height: 12),
            Text(_tr(
              'Подтвердите, что хотите предоставить этому контакту доступ к файлу.',
              'Підтвердьте, що хочете надати цьому контакту доступ до файлу.',
              'Confirm that you want this contact to access the file.',
            )),
            if (_busy) ...[
              const SizedBox(height: 16),
              const Center(child: CircularProgressIndicator()),
            ],
            if (result != null) ...[
              const SizedBox(height: 12),
              Text(
                result.localizedMessage(widget.languageCode),
                key: const Key('regrant-result'),
              ),
            ],
          ],
        ),
        actions: [
          if (!_busy)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(result == null
                  ? _tr('Отмена', 'Скасувати', 'Cancel')
                  : _tr('Закрыть', 'Закрити', 'Close')),
            ),
          if (!_busy && result == null)
            FilledButton(
              key: const Key('regrant-confirm'),
              onPressed: _confirm,
              child: Text(_tr(
                'Предоставить доступ',
                'Надати доступ',
                'Grant access',
              )),
            ),
        ],
      ),
    );
  }
}