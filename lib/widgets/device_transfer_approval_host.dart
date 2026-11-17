import 'dart:async';

import 'package:flutter/material.dart';

import '../services/socket_service.dart';
import '../services/app_language_service.dart';
import 'device_transfer_approval_panel.dart';

class DeviceTransferApprovalHost extends StatefulWidget {
  const DeviceTransferApprovalHost({super.key, required this.child});
  final Widget child;
  @override
  State<DeviceTransferApprovalHost> createState() =>
      _DeviceTransferApprovalHostState();
}

class _DeviceTransferApprovalHostState
    extends State<DeviceTransferApprovalHost> {
  Timer? timer;
  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final socket = SocketService.instance,
          request = SocketService.instance.pendingDeviceTransfer.value;
      if (request != null &&
          !request.validAt(DateTime.now().millisecondsSinceEpoch))
        socket.rejectDeviceTransfer(request);
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      widget.child,
      ValueListenableBuilder(
        valueListenable: SocketService.instance.pendingDeviceTransfer,
        builder: (context, request, _) {
          if (request == null) return const SizedBox.shrink();
          return Positioned.fill(
            child: ColoredBox(
              color: Colors.black54,
              child: SafeArea(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: SingleChildScrollView(
                      child: ValueListenableBuilder(
                        valueListenable: AppLanguageService.instance.code,
                        builder: (context, language, _) =>
                            DeviceTransferApprovalPanel(
                              key: ValueKey(request.nonce),
                              request: request,
                              language: language,
                              onApprove: () =>
                                  SocketService.instance.approveDeviceTransfer(
                                    request,
                                    userConfirmed: true,
                                  ),
                              onReject: () => SocketService.instance
                                  .rejectDeviceTransfer(request),
                            ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ],
  );
}
