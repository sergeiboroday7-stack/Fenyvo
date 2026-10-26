import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/support_links.dart';
import '../services/app_language_service.dart';
import '../theme/fenyvo_theme.dart';

class SupportOptionsScreen extends StatelessWidget {
  const SupportOptionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final language = AppLanguageService.instance;
    String t(String key) => language.text(key);

    return Scaffold(
      appBar: AppBar(title: Text(t('supportFenyvo'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
          children: [
            Text(
              t('supportChooseDescription'),
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: FenyvoPalette.secondary, height: 1.4),
            ),
            const SizedBox(height: 22),
            _SupportMethodCard(
              key: const ValueKey('support-method-monobank'),
              icon: Icons.account_balance_rounded,
              title: t('supportCardTitle'),
              subtitle: t('supportMonobankSubtitle'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MonobankSupportScreen(),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _SupportMethodCard(
              key: const ValueKey('support-method-crypto'),
              icon: Icons.currency_bitcoin_rounded,
              title: t('supportCryptoTitle'),
              subtitle: t('supportCryptoSubtitle'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CryptoSupportScreen(),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              t('supportFreeNotice'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: FenyvoPalette.secondary, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportMethodCard extends StatelessWidget {
  const _SupportMethodCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: FenyvoPalette.gold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: FenyvoPalette.gold, size: 29),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: FenyvoPalette.secondary,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class MonobankSupportScreen extends StatelessWidget {
  const MonobankSupportScreen({super.key});

  Future<void> _openMonobank(
    BuildContext context,
    AppLanguageService language,
  ) async {
    final opened = await launchUrl(
      SupportLinks.monobankJar,
      mode: LaunchMode.externalApplication,
    );
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(language.text('paymentLinkError'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = AppLanguageService.instance;
    String t(String key) => language.text(key);

    return Scaffold(
      appBar: AppBar(title: Text(t('supportCardTitle'))),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: FenyvoPalette.gold.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: FenyvoPalette.gold.withValues(alpha: 0.55),
                ),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.account_balance_rounded,
                    color: FenyvoPalette.gold,
                    size: 54,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    t('supportCardTitle'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    t('supportCardDescription'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(height: 1.45),
                  ),
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    key: const ValueKey('support-monobank-button'),
                    style: FilledButton.styleFrom(
                      backgroundColor: FenyvoPalette.gold,
                      foregroundColor: const Color(0xFF091B2D),
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: () => _openMonobank(context, language),
                    icon: const Icon(Icons.open_in_new_rounded),
                    label: Text(t('openMonobank')),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              t('supportExternalPaymentNotice'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: FenyvoPalette.secondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CryptoNetwork {
  const _CryptoNetwork({
    required this.name,
    required this.address,
    required this.explorerBaseUrl,
    required this.color,
    required this.icon,
  });

  final String name;
  final String address;
  final String explorerBaseUrl;
  final Color color;
  final IconData icon;

  Uri get explorerUri => Uri.parse('$explorerBaseUrl$address');
}

class CryptoSupportScreen extends StatefulWidget {
  const CryptoSupportScreen({super.key});

  @override
  State<CryptoSupportScreen> createState() => _CryptoSupportScreenState();
}

class _CryptoSupportScreenState extends State<CryptoSupportScreen> {
  static const _evmAddress = '0x8d9BC28A0AD9CfE9D64C468080f23D1433124366';

  static const List<_CryptoNetwork> _networks = [
    _CryptoNetwork(
      name: 'Ethereum',
      address: _evmAddress,
      explorerBaseUrl: 'https://etherscan.io/address/',
      color: Color(0xFF627EEA),
      icon: Icons.diamond_outlined,
    ),
    _CryptoNetwork(
      name: 'Bitcoin',
      address: 'bc1qy3t7a0fgy807vxzwhl6u6kvtj3pvgy2m2cn07y',
      explorerBaseUrl: 'https://mempool.space/address/',
      color: Color(0xFFF7931A),
      icon: Icons.currency_bitcoin_rounded,
    ),
    _CryptoNetwork(
      name: 'Solana',
      address: '3ziAr67waBVgBrPyQ1zefMWobJhKUGsY9zBE8DUJDYVS',
      explorerBaseUrl: 'https://solscan.io/account/',
      color: Color(0xFF111111),
      icon: Icons.blur_on_rounded,
    ),
    _CryptoNetwork(
      name: 'Tron',
      address: 'TRJEfFX5yN1rYsiLXxb8eWChTsG2TK2f9p',
      explorerBaseUrl: 'https://tronscan.org/#/address/',
      color: Color(0xFFEF0027),
      icon: Icons.change_history_rounded,
    ),
    _CryptoNetwork(
      name: 'Linea',
      address: _evmAddress,
      explorerBaseUrl: 'https://lineascan.build/address/',
      color: Color(0xFF55DDE0),
      icon: Icons.crop_square_rounded,
    ),
    _CryptoNetwork(
      name: 'Arbitrum',
      address: _evmAddress,
      explorerBaseUrl: 'https://arbiscan.io/address/',
      color: Color(0xFF213147),
      icon: Icons.layers_rounded,
    ),
    _CryptoNetwork(
      name: 'Arc',
      address: _evmAddress,
      explorerBaseUrl: 'https://explorer.arc.io/address/',
      color: Color(0xFF10283B),
      icon: Icons.route_rounded,
    ),
    _CryptoNetwork(
      name: 'BNB Chain',
      address: _evmAddress,
      explorerBaseUrl: 'https://bscscan.com/address/',
      color: Color(0xFFF3BA2F),
      icon: Icons.token_rounded,
    ),
    _CryptoNetwork(
      name: 'Base',
      address: _evmAddress,
      explorerBaseUrl: 'https://basescan.org/address/',
      color: Color(0xFF0052FF),
      icon: Icons.horizontal_rule_rounded,
    ),
    _CryptoNetwork(
      name: 'Monad',
      address: _evmAddress,
      explorerBaseUrl: 'https://monadscan.com/address/',
      color: Color(0xFF836EF9),
      icon: Icons.hexagon_outlined,
    ),
    _CryptoNetwork(
      name: 'Polygon',
      address: _evmAddress,
      explorerBaseUrl: 'https://polygonscan.com/address/',
      color: Color(0xFF8247E5),
      icon: Icons.hub_rounded,
    ),
    _CryptoNetwork(
      name: 'Optimism',
      address: _evmAddress,
      explorerBaseUrl: 'https://optimistic.etherscan.io/address/',
      color: Color(0xFFFF0420),
      icon: Icons.circle_outlined,
    ),
  ];

  String _shortAddress(String value) {
    if (value.length <= 18) return value;
    return '${value.substring(0, 9)}...${value.substring(value.length - 6)}';
  }

  Future<void> _copyAddress(
    BuildContext context,
    _CryptoNetwork network,
  ) async {
    await Clipboard.setData(ClipboardData(text: network.address));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLanguageService.instance.text('addressCopied')),
      ),
    );
  }

  Future<void> _showQr(BuildContext context, _CryptoNetwork network) async {
    final language = AppLanguageService.instance;
    String t(String key) => language.text(key);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${t('cryptoAddress')} · ${network.name}',
                style: Theme.of(sheetContext).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: QrImageView(
                  data: network.address,
                  size: 250,
                  backgroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 18),
              SelectableText(
                network.address,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, height: 1.35),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: FenyvoPalette.gold,
                  foregroundColor: const Color(0xFF091B2D),
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => _copyAddress(sheetContext, network),
                icon: const Icon(Icons.copy_rounded),
                label: Text(t('copyAddress')),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: () => launchUrl(
                  network.explorerUri,
                  mode: LaunchMode.externalApplication,
                ),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(t('openExplorer')),
              ),
              const SizedBox(height: 14),
              Text(
                t('cryptoWarning'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 12,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final language = AppLanguageService.instance;
    String t(String key) => language.text(key);

    return Scaffold(
      appBar: AppBar(title: Text(t('supportCryptoTitle'))),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              child: Text(
                t('cryptoInstruction'),
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: ListView.separated(
                key: const ValueKey('support-crypto-network-list'),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _networks.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final network = _networks[index];
                  return ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    onTap: () => _showQr(context, network),
                    leading: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: network.color,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(network.icon, color: Colors.white, size: 27),
                    ),
                    title: Text(
                      network.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _shortAddress(network.address),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.qr_code_rounded),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
              child: Text(
                t('cryptoWarning'),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.orange,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
