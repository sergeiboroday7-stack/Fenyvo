import '../widgets/device_transfer_code_input.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart';

import 'dart:convert';

import '../config/server_config.dart';
import '../services/crypto/old_device_pin.dart';
import '../services/crypto/device_transfer_candidate_store.dart';
import '../services/crypto/signal_secure_store.dart';
import '../services/new_device_transfer_v2_client.dart';
import '../widgets/device_transfer_pairing_screen.dart';

class NewDeviceTransferScreen extends StatefulWidget {
  const NewDeviceTransferScreen({
    super.key,
    required this.username,
    required this.password,
    required this.language,
  });
  final String username, password, language;
  @override
  State<NewDeviceTransferScreen> createState() =>
      _NewDeviceTransferScreenState();
}

class _NewDeviceTransferScreenState extends State<NewDeviceTransferScreen> {
  final _pin = TextEditingController();
  NewDeviceTransferV2Client? _client;
  bool _busy = false;
  String? _error;
  String? _localKeyDiagnostic;
  String t(String ru, String uk, String en) =>
      transferText(widget.language, ru, uk, en);
  Future<void> start() async {
    if (_busy ||
        (_client != null && _client!.phase != TransferV2Phase.interrupted)) {
      return;
    }
    if (_client?.phase == TransferV2Phase.interrupted) {
      _client!.removeListener(update);
      _client!.dispose();
      _client = null;
    }
    var stage = 'code';
    setState(() {
      _busy = true;
      _error = null;
      _localKeyDiagnostic = null;
    });
    try {
      final pin = OldDevicePin.parse(_pin.text.trim());
      stage = 'account';
      if (pin.username != widget.username.trim()) {
        setState(
          () => _error = t(
            'РљРѕРґ РїРµСЂРµРЅРѕСЃР° РїСЂРёРЅР°РґР»РµР¶РёС‚ РґСЂСѓРіРѕРјСѓ Р°РєРєР°СѓРЅС‚Сѓ.',
            'РљРѕРґ РїРµСЂРµРЅРµСЃРµРЅРЅСЏ РЅР°Р»РµР¶РёС‚СЊ С–РЅС€РѕРјСѓ Р°РєР°СѓРЅС‚Сѓ.',
            'This transfer code belongs to another account.',
          ),
        );
        return;
      }
      if (widget.password.isEmpty) {
        setState(
          () => _error = t(
            'РќРµ СѓРєР°Р·Р°РЅ РїР°СЂРѕР»СЊ Р°РєРєР°СѓРЅС‚Р°. Р’РµСЂРЅРёСЃСЊ Рє СЌРєСЂР°РЅСѓ РІС…РѕРґР°.',
            'РќРµ РІРєР°Р·Р°РЅРѕ РїР°СЂРѕР»СЊ Р°РєР°СѓРЅС‚Р°. РџРѕРІРµСЂРЅРёСЃСЏ РґРѕ РµРєСЂР°РЅР° РІС…РѕРґСѓ.',
            'Account password is missing. Return to sign-in.',
          ),
        );
        return;
      }
      stage = 'local_identity';
      final localKeyState = await DeviceTransferCandidateStore(widget.username)
          .diagnoseExistingLocalIdentity(pin);
      if (!mounted) return;
      if (localKeyState != 'NO_LOCAL_IDENTITY') {
        // A pre-existing identity may only resume a previously committed,
        // sealed transfer candidate with the exact same public key.
        final stored = await DeviceTransferCandidateStore(widget.username)
            .readPublic();
        if (!mounted) return;
        final localFingerprint = await SignalSecureStore(widget.username).existingIdentityFingerprintForTransfer();
        if (!mounted) return;
        final matchesCandidate =
            stored != null &&
            localFingerprint != null &&
            sha256.convert(base64Decode(stored.identityKey)).toString() ==
                localFingerprint;
        if (!matchesCandidate ||
            !{'committed', 'installed'}.contains(stored.phase) ||
            stored.accountId != pin.accountId ||
            stored.publicData['oldIdentityKey'] != pin.identityKey) {
          setState(() => _localKeyDiagnostic = localKeyState);
          return;
        }
      }
      stage = 'transfer';
      final client = NewDeviceTransferV2Client(
        server: ServerConfig.websocketUri,
        pin: pin,
      );
      _client = client;
      client.addListener(update);
      setState(() {});
      await client.run(password: widget.password);
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error = switch (stage) {
          'code' => t(
            'РќРµРІРµСЂРЅС‹Р№ С„РѕСЂРјР°С‚ РєРѕРґР° РїРµСЂРµРЅРѕСЃР°. РџРѕР»СѓС‡Рё РЅРѕРІС‹Р№ РєРѕРґ СЃРѕ СЃС‚Р°СЂРѕРіРѕ С‚РµР»РµС„РѕРЅР°.',
            'РќРµРїСЂР°РІРёР»СЊРЅРёР№ С„РѕСЂРјР°С‚ РєРѕРґСѓ РїРµСЂРµРЅРµСЃРµРЅРЅСЏ. РћС‚СЂРёРјР°Р№ РЅРѕРІРёР№ РєРѕРґ Р·С– СЃС‚Р°СЂРѕРіРѕ С‚РµР»РµС„РѕРЅР°.',
            'Invalid transfer code format. Get a new code from the old phone.',
          ),
          'local_identity' => t(
            'РќРµ СѓРґР°Р»РѕСЃСЊ РїСЂРѕРІРµСЂРёС‚СЊ Р·Р°С‰РёС‰С‘РЅРЅС‹Рµ РєР»СЋС‡Рё СЌС‚РѕРіРѕ С‚РµР»РµС„РѕРЅР°. Р”Р°РЅРЅС‹Рµ РЅРµ РёР·РјРµРЅРµРЅС‹.',
            'РќРµ РІРґР°Р»РѕСЃСЏ РїРµСЂРµРІС–СЂРёС‚Рё Р·Р°С…РёС‰РµРЅС– РєР»СЋС‡С– С†СЊРѕРіРѕ С‚РµР»РµС„РѕРЅР°. Р”Р°РЅС– РЅРµ Р·РјС–РЅРµРЅРѕ.',
            'Could not inspect protected keys on this phone. No data was changed.',
          ),
          'transfer' => t(
            'РќРµ СѓРґР°Р»РѕСЃСЊ РЅР°С‡Р°С‚СЊ РїРµСЂРµРЅРѕСЃ. РџСЂРѕРІРµСЂСЊ СЃРѕРµРґРёРЅРµРЅРёРµ Рё РґР°РЅРЅС‹Рµ РІС…РѕРґР°; РєР»СЋС‡Рё РЅРµ СѓРґР°Р»СЏР№.',
            'РќРµ РІРґР°Р»РѕСЃСЏ СЂРѕР·РїРѕС‡Р°С‚Рё РїРµСЂРµРЅРµСЃРµРЅРЅСЏ. РџРµСЂРµРІС–СЂ Р·вЂ™С”РґРЅР°РЅРЅСЏ Р№ РґР°РЅС– РІС…РѕРґСѓ; РЅРµ РІРёРґР°Р»СЏР№ РєР»СЋС‡С–.',
            'Could not start transfer. Check the connection and sign-in details; do not delete keys.',
          ),
          _ => t(
            'РќРµ СѓРґР°Р»РѕСЃСЊ РїСЂРѕРІРµСЂРёС‚СЊ РґР°РЅРЅС‹Рµ Р°РєРєР°СѓРЅС‚Р°.',
            'РќРµ РІРґР°Р»РѕСЃСЏ РїРµСЂРµРІС–СЂРёС‚Рё РґР°РЅС– Р°РєР°СѓРЅС‚Сѓ.',
            'Could not validate account details.',
          ),
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  bool _returning = false;
  void update() {
    if (!mounted) return;
    setState(() {});
    if (_client?.phase == TransferV2Phase.ready && !_returning) {
      _returning = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        TransferredDeviceConnection? connection;
        try {
          connection = _client!.takeConnection();
          Navigator.of(context).pop(connection);
        } catch (_) {
          if (connection != null) {
            unawaited(connection.abort());
          }
          _returning = false;
        }
      });
    }
  }

  @override
  void dispose() {
    _client?.removeListener(update);
    _client?.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final phase = _client?.phase;
    final verified = phase == TransferV2Phase.ready;
    final candidate = _client?.candidate;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          t(
            'РџРѕРґРєР»СЋС‡РёС‚СЊ РЅРѕРІС‹Р№ С‚РµР»РµС„РѕРЅ',
            'РџС–РґРєР»СЋС‡РёС‚Рё РЅРѕРІРёР№ С‚РµР»РµС„РѕРЅ',
            'Connect new phone',
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t(
                'РџРѕР»СѓС‡Рё РєРѕРґ РЅРµРїРѕСЃСЂРµРґСЃС‚РІРµРЅРЅРѕ СЃРѕ СЃРІРѕРµРіРѕ СЃС‚Р°СЂРѕРіРѕ С‚РµР»РµС„РѕРЅР°. РќРµ РёСЃРїРѕР»СЊР·СѓР№ РєРѕРґ, РїСЂРёСЃР»Р°РЅРЅС‹Р№ РЅРµР·РЅР°РєРѕРјС†РµРј.',
                'РћС‚СЂРёРјР°Р№ РєРѕРґ Р±РµР·РїРѕСЃРµСЂРµРґРЅСЊРѕ Р·С– СЃРІРѕРіРѕ СЃС‚Р°СЂРѕРіРѕ С‚РµР»РµС„РѕРЅР°. РќРµ РІРёРєРѕСЂРёСЃС‚РѕРІСѓР№ РєРѕРґ, РЅР°РґС–СЃР»Р°РЅРёР№ РЅРµР·РЅР°Р№РѕРјС†РµРј.',
                'Get the code directly from your own old phone. Do not use a code supplied by a stranger.',
              ),
            ),
            const SizedBox(height: 12),
            DeviceTransferCodeInput(
              controller: _pin,
              username: widget.username,
              language: widget.language,
              enabled:
                  (_client == null ||
                      _client?.phase == TransferV2Phase.interrupted) &&
                  !_busy,
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed:
                  (_client == null ||
                          _client?.phase == TransferV2Phase.interrupted) &&
                      !_busy
                  ? start
                  : null,
              child: Text(
                t(
                  'Р—Р°РїСЂРѕСЃРёС‚СЊ РїРµСЂРµРЅРѕСЃ',
                  'Р—Р°РїСЂРѕСЃРёС‚Рё РїРµСЂРµРЅРµСЃРµРЅРЅСЏ',
                  'Request transfer',
                ),
              ),
            ),
            if (candidate != null) ...[
              const SizedBox(height: 16),
              Text(
                t(
                  'РЎСЂР°РІРЅРё РІРµСЃСЊ СЌС‚РѕС‚ РєРѕРґ СЃРѕ СЃС‚Р°СЂС‹Рј С‚РµР»РµС„РѕРЅРѕРј:',
                  'РџРѕСЂС–РІРЅСЏР№ СѓРІРµСЃСЊ С†РµР№ РєРѕРґ Р·С– СЃС‚Р°СЂРёРј С‚РµР»РµС„РѕРЅРѕРј:',
                  'Compare this entire code with the old phone:',
                ),
              ),
              SelectableText(
                sha256.convert(base64Decode(candidate.identityKey)).toString(),
              ),
            ],
            if (_busy || phase == TransferV2Phase.staging)
              const Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            if (phase == TransferV2Phase.waiting)
              Text(
                t(
                  'РћР¶РёРґР°РµРј РїРѕРґС‚РІРµСЂР¶РґРµРЅРёРµ РЅР° СЃС‚Р°СЂРѕРј С‚РµР»РµС„РѕРЅРµ',
                  'РћС‡С–РєСѓС”РјРѕ РїС–РґС‚РІРµСЂРґР¶РµРЅРЅСЏ РЅР° СЃС‚Р°СЂРѕРјСѓ С‚РµР»РµС„РѕРЅС–',
                  'Waiting for approval on the old phone',
                ),
              ),
            if (verified)
              Text(
                t(
                  'РџРµСЂРµРЅРѕСЃ РїРѕРґС‚РІРµСЂР¶РґС‘РЅ. РћС‚РєСЂС‹РІР°РµРј Р·Р°С‰РёС‰С‘РЅРЅС‹Р№ С‡Р°С‚.',
                  'РџРµСЂРµРЅРµСЃРµРЅРЅСЏ РїС–РґС‚РІРµСЂРґР¶РµРЅРѕ. Р’С–РґРєСЂРёРІР°С”РјРѕ Р·Р°С…РёС‰РµРЅРёР№ С‡Р°С‚.',
                  'Transfer confirmed. Opening the encrypted chat.',
                ),
              ),
            if (phase == TransferV2Phase.interrupted)
              Text(
                t(
                  'РџРµСЂРµРЅРѕСЃ РїСЂРµСЂРІР°РЅ. Р—Р°РєСЂРѕР№ СЌРєСЂР°РЅ Рё РїРѕРІС‚РѕСЂРё: СЃРѕС…СЂР°РЅС‘РЅРЅС‹Р№ РєР»СЋС‡ Р±СѓРґРµС‚ РёСЃРїРѕР»СЊР·РѕРІР°РЅ СЃРЅРѕРІР°.',
                  'РџРµСЂРµРЅРµСЃРµРЅРЅСЏ РїРµСЂРµСЂРІР°РЅРѕ. Р—Р°РєСЂРёР№ РµРєСЂР°РЅ С– РїРѕРІС‚РѕСЂРё: Р·Р±РµСЂРµР¶РµРЅРёР№ РєР»СЋС‡ Р±СѓРґРµ РІРёРєРѕСЂРёСЃС‚Р°РЅРѕ Р·РЅРѕРІСѓ.',
                  'Transfer interrupted. Close and retry; the saved key will be reused.',
                ),
              ),
            if (_localKeyDiagnostic != null)
              Text(
                t(
                  'РќР° СЌС‚РѕРј С‚РµР»РµС„РѕРЅРµ СѓР¶Рµ РµСЃС‚СЊ РґСЂСѓРіР°СЏ Р·Р°С‰РёС‰С‘РЅРЅР°СЏ РёРґРµРЅС‚РёС‡РЅРѕСЃС‚СЊ РёР»Рё РїРµСЂРµРЅРѕСЃ РЅРµ Р·Р°РІРµСЂС€С‘РЅ. РљР»СЋС‡Рё СЃРѕС…СЂР°РЅРµРЅС‹. РќРµ СѓРґР°Р»СЏР№ РґР°РЅРЅС‹Рµ РїСЂРёР»РѕР¶РµРЅРёСЏ.',
                  'РќР° С†СЊРѕРјСѓ С‚РµР»РµС„РѕРЅС– РІР¶Рµ С” С–РЅС€Р° Р·Р°С…РёС‰РµРЅР° С–РґРµРЅС‚РёС‡РЅС–СЃС‚СЊ Р°Р±Рѕ РїРµСЂРµРЅРµСЃРµРЅРЅСЏ РЅРµ Р·Р°РІРµСЂС€РµРЅРѕ. РљР»СЋС‡С– Р·Р±РµСЂРµР¶РµРЅРѕ. РќРµ РІРёРґР°Р»СЏР№ РґР°РЅС– Р·Р°СЃС‚РѕСЃСѓРЅРєСѓ.',
                  'This phone already has another protected identity or an incomplete transfer. Keys were preserved. Do not clear app data.',
                ),
              ),
            if (phase == TransferV2Phase.interrupted &&
                _client?.failure != null)
              Text(
                t(
                  'РџРµСЂРµРЅРѕСЃ РїСЂРµСЂРІР°РЅ. РџСЂРѕРІРµСЂСЊ СЃРѕРµРґРёРЅРµРЅРёРµ Рё РїРѕРІС‚РѕСЂРё РїРѕРїС‹С‚РєСѓ. Р—Р°С‰РёС‰С‘РЅРЅС‹Рµ РєР»СЋС‡Рё РЅРµ СѓРґР°Р»СЏР№.',
                  'РџРµСЂРµРЅРµСЃРµРЅРЅСЏ РїРµСЂРµСЂРІР°РЅРѕ. РџРµСЂРµРІС–СЂ Р·вЂ™С”РґРЅР°РЅРЅСЏ С‚Р° РїРѕРІС‚РѕСЂРё СЃРїСЂРѕР±Сѓ. Р—Р°С…РёС‰РµРЅС– РєР»СЋС‡С– РЅРµ РІРёРґР°Р»СЏР№.',
                  'Transfer interrupted. Check the connection and retry. Do not delete protected keys.',
                ),
              ),
            if (_error != null) Text(_error!),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t('Р—Р°РєСЂС‹С‚СЊ', 'Р—Р°РєСЂРёС‚Рё', 'Close')),
            ),
          ],
        ),
      ),
    );
  }
}
