import '../services/app_language_service.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

class MyContactScreen extends StatelessWidget {
  const MyContactScreen({super.key, required this.username});

  final String username;

  String get contactLink => Uri.https('fenyvo.com', '/u/$username').toString();

  Future<void> _copyLink(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: contactLink));

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLanguageService.instance.text('myContactLinkCopied')),
      ),
    );
  }

  Future<void> _shareContact() async {
    await SharePlus.instance.share(
      ShareParams(
        title: 'FENYVO',
        text: AppLanguageService.instance
            .text('myContactInvitation')
            .replaceAll('{username}', username)
            .replaceAll('{link}', contactLink),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(AppLanguageService.instance.text('myContactTitle')),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.person_pin_circle_rounded, size: 54),
                  const SizedBox(height: 12),
                  Text(
                    '@$username',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppLanguageService.instance.text('myContactQrInstructions'),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 28),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: ColoredBox(
                        color: Colors.white,
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: QrImageView(
                            data: contactLink,
                            version: QrVersions.auto,
                            size: 220,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SelectableText(contactLink, textAlign: TextAlign.center),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => _shareContact(),
                      icon: const Icon(Icons.share_rounded),
                      label: Text(
                        AppLanguageService.instance.text('myContactShare'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _copyLink(context),
                      icon: const Icon(Icons.copy_rounded),
                      label: Text(
                        AppLanguageService.instance.text('myContactCopyLink'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    AppLanguageService.instance.text(
                      'myContactPrivacyExplanation',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
