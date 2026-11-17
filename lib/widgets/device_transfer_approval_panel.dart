import 'package:flutter/material.dart';

import '../services/crypto/device_transfer_request.dart';

class DeviceTransferApprovalPanel extends StatefulWidget {
  const DeviceTransferApprovalPanel({
    super.key,
    required this.request,
    required this.language,
    required this.onApprove,
    required this.onReject,
  });
  final DeviceTransferRequest request;
  final String language;
  final Future<bool> Function() onApprove;
  final VoidCallback onReject;
  @override
  State<DeviceTransferApprovalPanel> createState() =>
      _DeviceTransferApprovalPanelState();
}

class _DeviceTransferApprovalPanelState
    extends State<DeviceTransferApprovalPanel> {
  bool compared = false, busy = false, failed = false;
  String text(String ru, String uk, String en) => widget.language == 'ru'
      ? ru
      : (widget.language == 'uk' || widget.language == 'ua')
      ? uk
      : en;
  @override
  void didUpdateWidget(covariant DeviceTransferApprovalPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request.nonce != widget.request.nonce) {
      compared = false;
      busy = false;
      failed = false;
    }
  }

  Future<void> approve() async {
    if (!compared ||
        busy ||
        !widget.request.validAt(DateTime.now().millisecondsSinceEpoch))
      return;
    final request = widget.request;
    setState(() {
      busy = true;
      failed = false;
    });
    bool result;
    try {
      result = await widget.onApprove();
    } catch (_) {
      result = false;
    }
    if (!mounted || !identical(request, widget.request)) return;
    setState(() {
      busy = false;
      failed = !result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final valid = widget.request.validAt(DateTime.now().millisecondsSinceEpoch);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text(
                'Подключение нового телефона',
                'Підключення нового телефона',
                'Connect a new phone',
              ),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              text(
                'Подтверждай только свой перенос. Сравни весь код с новым телефоном. Если ты не начинал перенос — отклони запрос.',
                'Підтверджуй лише власне перенесення. Порівняй увесь код із новим телефоном. Якщо ти не починав перенесення — відхили запит.',
                'Approve only your own transfer. Compare the entire code with the new phone. If you did not start this transfer, reject it.',
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(widget.request.candidateHash),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: compared,
              onChanged: busy || !valid
                  ? null
                  : (v) => setState(() => compared = v == true),
              title: Text(
                text(
                  'Я сравнил код на обоих устройствах — он совпадает',
                  'Я порівняв код на обох пристроях — він збігається',
                  'I compared the code on both devices and it matches',
                ),
              ),
            ),
            if (failed)
              Text(
                text(
                  'Подтверждение сервера не получено. Проверь соединение.',
                  'Підтвердження сервера не отримано. Перевір з’єднання.',
                  'Server acknowledgement was not received. Check your connection.',
                ),
              ),
            if (!valid)
              Text(
                text('Запрос истёк', 'Термін запиту минув', 'Request expired'),
              ),
            Wrap(
              spacing: 12,
              children: [
                TextButton(
                  onPressed: busy ? null : widget.onReject,
                  child: Text(text('Отклонить', 'Відхилити', 'Reject')),
                ),
                FilledButton(
                  onPressed: compared && valid && !busy ? approve : null,
                  child: Text(
                    busy
                        ? text(
                            'Ожидаем подтверждение…',
                            'Очікуємо підтвердження…',
                            'Waiting for acknowledgement…',
                          )
                        : text(
                            'Подтвердить перенос',
                            'Підтвердити перенесення',
                            'Approve transfer',
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
