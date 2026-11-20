import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fenyvo/services/new_device_transfer_v2_client.dart';
import 'package:fenyvo/services/crypto/signal_e2ee_service.dart';

import 'new_device_transfer_v2_client_test.dart' as support;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await SignalE2eeService.instance.prepareDeviceTransferCrypto();
  });
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final overflow in [false, true]) {
    test(
      overflow
          ? 'queue overflow stops activation handoff'
          : 'one socket preserves buffered and live frames with one owner',
      () async {
        await support.fixture((owner, pin, old) async {
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
              fake = support.Wire(old, owner);
          WebSocket? peer;
          StreamSubscription<dynamic>? input;
          StreamSubscription<Map<String, dynamic>>? output;
          var connections = 0;
          final probe = Completer<void>();
          final accept = server.listen((request) async {
            final socket = await WebSocketTransformer.upgrade(request);
            peer = socket;
            connections++;
            output = fake.messages.stream.listen((frame) {
              if (frame['type'] == 'e2ee_bundle_published') {
                for (var i = 0; i < (overflow ? 129 : 2); i++) {
                  socket.add(
                    jsonEncode({
                      'type': i == 0 ? 'users_list' : 'message',
                      'data': {'sequence': i},
                    }),
                  );
                }
              }
              socket.add(jsonEncode(frame));
              if (frame['type'] == 'e2ee_bundle_published' && !overflow)
                socket.add(
                  jsonEncode({
                    'type': 'message',
                    'data': {'sequence': 2},
                  }),
                );
            });
            input = socket.listen((raw) {
              final frame = jsonDecode(raw as String) as Map;
              if (frame['type'] == 'probe') {
                if (!probe.isCompleted) probe.complete();
                return;
              }
              fake.send(
                frame['type'] as String,
                Map<String, dynamic>.from(frame['data'] as Map),
              );
            });
          });
          final client = NewDeviceTransferV2Client(
            server: Uri.parse('ws://127.0.0.1:${server.port}/ws'),
            pin: pin,
            responseTimeout: const Duration(seconds: 10),
          );
          TransferredDeviceConnection? ticket;
          Future<void>? drain;
          var disposed = false;
          try {
            expect(() => client.takeConnection(), throwsStateError);
            await client.run(password: 'synthetic-password');
            if (overflow) {
              expect(client.phase, TransferV2Phase.interrupted);
              expect(() => client.takeConnection(), throwsStateError);
              return;
            }
            expect(client.phase, TransferV2Phase.ready);
            ticket = client.takeConnection();
            expect(() => client.takeConnection(), throwsStateError);
            client.dispose();
            disposed = true;
            final frames = <Map<String, dynamic>>[], got = Completer<void>();
            drain = ticket.drain((raw) async {
              frames.add(jsonDecode(raw as String) as Map<String, dynamic>);
              if (frames.length == 4 && !got.isCompleted) got.complete();
            });
            await got.future.timeout(const Duration(seconds: 5));
            expect(frames.map((f) => f['type']).toList(), [
              'login_success',
              'users_list',
              'message',
              'message',
            ]);
            expect(
              frames
                  .skip(1)
                  .map((f) => (f['data'] as Map)['sequence'])
                  .toList(),
              [0, 1, 2],
            );
            expect(connections, 1);
            ticket.channel.sink.add(jsonEncode({'type': 'probe', 'data': {}}));
            await probe.future.timeout(const Duration(seconds: 5));
            await expectLater(ticket.drain((_) async {}), throwsStateError);
          } finally {
            if (!disposed) client.dispose();
            await ticket?.abort();
            if (drain != null) await drain.timeout(const Duration(seconds: 5));
            await input?.cancel();
            await output?.cancel();
            await peer?.close();
            await accept.cancel();
            await server.close(force: true);
            unawaited(fake.messages.close());
          }
        });
      },
    );
  }
}
