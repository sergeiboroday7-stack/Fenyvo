import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/app_language_service.dart';
import '../services/fenyvo_pro_trial_service.dart';
import '../theme/spartan_theme.dart';

class FenyvoProScreen extends StatefulWidget {
  const FenyvoProScreen({super.key});

  @override
  State<FenyvoProScreen> createState() => _FenyvoProScreenState();
}

class _FenyvoProScreenState extends State<FenyvoProScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion;
  FenyvoProTrialSnapshot? _trial;
  bool _activating = false;
  int _selectedSticker = 0;

  _ProCopy get copy => _ProCopy.forCode(AppLanguageService.instance.code.value);

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    FenyvoProTrialService.load().then((value) {
      if (mounted) setState(() => _trial = value);
    });
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  Future<void> _activateTrial() async {
    if (_activating) return;
    setState(() => _activating = true);
    final trial = await FenyvoProTrialService.activate();
    if (!mounted) return;
    setState(() {
      _trial = trial;
      _activating = false;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(copy.activated)));
  }

  @override
  Widget build(BuildContext context) {
    final trial = _trial;
    return Scaffold(
      appBar: AppBar(title: const Text('FENYVO PRO')),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [SpartanPalette.surface, SpartanPalette.canvasDeep],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          children: [
            _buildHero(trial),
            const SizedBox(height: 18),
            _SectionTitle(copy.features),
            const SizedBox(height: 10),
            _buildFeatures(),
            const SizedBox(height: 22),
            _SectionTitle(copy.stickers),
            const SizedBox(height: 4),
            Text(
              copy.stickerHint,
              style: const TextStyle(color: SpartanPalette.secondary),
            ),
            const SizedBox(height: 12),
            _buildAnimatedSticker(),
            const SizedBox(height: 12),
            _buildStickerGrid(),
            const SizedBox(height: 22),
            _SectionTitle(copy.themes),
            const SizedBox(height: 10),
            const Row(
              children: [
                Expanded(
                  child: _ThemePreview(
                    colors: [Color(0xFF10243A), Color(0xFFC7A65C)],
                    label: 'Blue Gold',
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _ThemePreview(
                    colors: [Color(0xFF17151D), Color(0xFFA882FF)],
                    label: 'Midnight',
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: _ThemePreview(
                    colors: [Color(0xFF102824), Color(0xFF77D6B0)],
                    label: 'Emerald',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            _SectionTitle(copy.frames),
            const SizedBox(height: 10),
            const Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _FramePreview(kind: 0),
                _FramePreview(kind: 1),
                _FramePreview(kind: 2),
                _FramePreview(kind: 3),
              ],
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SpartanPalette.surfaceSoft,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: SpartanPalette.line),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.science_outlined,
                    color: SpartanPalette.gold,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      copy.testNotice,
                      style: const TextStyle(color: SpartanPalette.secondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHero(FenyvoProTrialSnapshot? trial) {
    final isActive = trial?.isActive ?? false;
    final hasExpired = (trial?.hasStarted ?? false) && !isActive;
    final status = isActive
        ? copy.daysLeft(trial!.daysRemaining)
        : hasExpired
        ? copy.expired
        : copy.freeMonth;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: SpartanPalette.gold.withValues(alpha: 0.75)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [SpartanPalette.surfaceRaised, SpartanPalette.canvasDeep],
        ),
        boxShadow: [
          BoxShadow(
            color: SpartanPalette.gold.withValues(alpha: 0.13),
            blurRadius: 28,
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(
            Icons.auto_awesome_rounded,
            size: 46,
            color: SpartanPalette.gold,
          ),
          const SizedBox(height: 10),
          const Text(
            'FENYVO PRO',
            style: TextStyle(
              fontSize: 29,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            copy.subtitle,
            textAlign: TextAlign.center,
            style: const TextStyle(color: SpartanPalette.secondary),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isActive
                  ? SpartanPalette.online.withValues(alpha: 0.13)
                  : SpartanPalette.gold.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(99),
              border: Border.all(
                color: isActive ? SpartanPalette.online : SpartanPalette.gold,
              ),
            ),
            child: Text(
              status,
              style: TextStyle(
                color: isActive ? SpartanPalette.online : SpartanPalette.gold,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (!isActive && !hasExpired)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _activating ? null : _activateTrial,
                icon: _activating
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bolt_rounded),
                label: Text(copy.activate),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            copy.noPayment,
            textAlign: TextAlign.center,
            style: const TextStyle(color: SpartanPalette.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatures() => Row(
    children: [
      Expanded(
        child: _FeatureCard(
          icon: Icons.palette_outlined,
          title: copy.themes,
          value: '3',
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _FeatureCard(
          icon: Icons.account_circle_outlined,
          title: copy.frames,
          value: '4',
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: _FeatureCard(
          icon: Icons.emoji_emotions_outlined,
          title: copy.stickers,
          value: '16',
        ),
      ),
    ],
  );

  Widget _buildAnimatedSticker() => Container(
    height: 180,
    decoration: BoxDecoration(
      color: SpartanPalette.canvasDeep,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: SpartanPalette.gold.withValues(alpha: 0.45)),
    ),
    child: AnimatedBuilder(
      animation: _motion,
      builder: (context, child) {
        final curve = Curves.easeInOut.transform(_motion.value);
        return Transform.translate(
          offset: Offset(0, -5 * curve),
          child: Transform.rotate(
            angle: math.sin(_motion.value * math.pi * 2) * 0.025,
            child: Transform.scale(scale: 0.94 + curve * 0.06, child: child),
          ),
        );
      },
      child: Center(
        child: SizedBox.square(
          dimension: 150,
          child: _SpriteCell(index: _selectedSticker),
        ),
      ),
    ),
  );

  Widget _buildStickerGrid() => GridView.builder(
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    itemCount: 16,
    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: 4,
      mainAxisSpacing: 8,
      crossAxisSpacing: 8,
    ),
    itemBuilder: (context, index) => InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => setState(() => _selectedSticker = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: SpartanPalette.surfaceSoft,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: index == _selectedSticker
                ? SpartanPalette.gold
                : SpartanPalette.line,
            width: index == _selectedSticker ? 2 : 1,
          ),
        ),
        child: _SpriteCell(index: index),
      ),
    ),
  );
}

class _SpriteCell extends StatelessWidget {
  const _SpriteCell({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final column = index % 4;
    final row = index ~/ 4;
    return ClipRect(
      child: Align(
        alignment: Alignment(-1 + (column * 2 / 3), -1 + (row * 2 / 3)),
        widthFactor: 0.25,
        heightFactor: 0.25,
        child: Image.asset(
          'assets/images/fenyvo_pro_spark_stickers.png',
          width: 400,
          height: 400,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.high,
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    style: const TextStyle(
      color: SpartanPalette.gold,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.1,
    ),
  );
}

class _FeatureCard extends StatelessWidget {
  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.value,
  });
  final IconData icon;
  final String title;
  final String value;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
    decoration: BoxDecoration(
      color: SpartanPalette.surfaceRaised,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: SpartanPalette.line),
    ),
    child: Column(
      children: [
        Icon(icon, color: SpartanPalette.gold),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        Text(
          title,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: SpartanPalette.secondary, fontSize: 11),
        ),
      ],
    ),
  );
}

class _ThemePreview extends StatelessWidget {
  const _ThemePreview({required this.colors, required this.label});
  final List<Color> colors;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
    height: 92,
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: colors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: SpartanPalette.line),
    ),
    alignment: Alignment.bottomCenter,
    padding: const EdgeInsets.all(8),
    child: Text(
      label,
      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
    ),
  );
}

class _FramePreview extends StatelessWidget {
  const _FramePreview({required this.kind});
  final int kind;
  @override
  Widget build(BuildContext context) {
    final colors = <List<Color>>[
      [SpartanPalette.gold, const Color(0xFFFFE3A1)],
      [const Color(0xFFA882FF), const Color(0xFF60D9FF)],
      [const Color(0xFF63E6B5), const Color(0xFFC7A65C)],
      [const Color(0xFFFF8A65), const Color(0xFFFFD166)],
    ][kind];
    return Container(
      width: 62,
      height: 62,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(colors: [...colors, colors.first]),
      ),
      child: const CircleAvatar(
        backgroundColor: SpartanPalette.blue,
        child: Icon(Icons.person_rounded, color: SpartanPalette.ink),
      ),
    );
  }
}

class _ProCopy {
  const _ProCopy(this.values);
  final Map<String, String> values;
  String get subtitle => values['subtitle']!;
  String get freeMonth => values['freeMonth']!;
  String get noPayment => values['noPayment']!;
  String get activate => values['activate']!;
  String get activated => values['activated']!;
  String get expired => values['expired']!;
  String get features => values['features']!;
  String get themes => values['themes']!;
  String get frames => values['frames']!;
  String get stickers => values['stickers']!;
  String get stickerHint => values['stickerHint']!;
  String get testNotice => values['testNotice']!;
  String daysLeft(int days) =>
      values['daysLeft']!.replaceFirst('{days}', '$days');

  static _ProCopy forCode(String code) {
    final resolved = code == 'system'
        ? WidgetsBinding.instance.platformDispatcher.locale.languageCode
        : code;
    return _ProCopy(_all[resolved] ?? _all['en']!);
  }

  static const _all = <String, Map<String, String>>{
    'ru': {
      'subtitle': 'Темы, рамки и живая коллекция стикеров',
      'freeMonth': '30 ДНЕЙ БЕСПЛАТНО',
      'noPayment':
          'Без карты и списаний. Оплата подключится только после тестирования.',
      'activate': 'Включить пробный месяц',
      'activated': 'Пробный месяц Fenyvo Pro включён',
      'expired': 'Пробный период завершён',
      'features': 'Что входит',
      'themes': 'Темы',
      'frames': 'Рамки',
      'stickers': 'Стикеры',
      'stickerHint': 'Нажмите на персонажа, чтобы посмотреть его движение.',
      'testNotice': 'Тестовый режим: доступ хранится только на этом устройстве. Реальная подписка и автоматическое продление отключены.',
      'daysLeft': 'Осталось дней: {days}',
    },
    'uk': {
      'subtitle': 'Теми, рамки та жива колекція стікерів',
      'freeMonth': '30 ДНІВ БЕЗКОШТОВНО',
      'noPayment':
          'Без картки та списань. Оплату підключимо лише після тестування.',
      'activate': 'Увімкнути пробний місяць',
      'activated': 'Пробний місяць Fenyvo Pro увімкнено',
      'expired': 'Пробний період завершено',
      'features': 'Що входить',
      'themes': 'Теми',
      'frames': 'Рамки',
      'stickers': 'Стікери',
      'stickerHint': 'Натисніть на персонажа, щоб переглянути рух.',
      'testNotice': 'Тестовий режим: доступ зберігається лише на цьому пристрої. Реальна підписка й автоматичне продовження вимкнені.',
      'daysLeft': 'Залишилося днів: {days}',
    },
    'en': {
      'subtitle': 'Themes, frames and a living sticker collection',
      'freeMonth': '30 DAYS FREE',
      'noPayment':
          'No card or charges. Billing will be added only after testing.',
      'activate': 'Start free month',
      'activated': 'Fenyvo Pro free month started',
      'expired': 'Trial period ended',
      'features': 'Included',
      'themes': 'Themes',
      'frames': 'Frames',
      'stickers': 'Stickers',
      'stickerHint': 'Tap a character to preview its motion.',
      'testNotice': 'Test mode: access is stored only on this device. Real billing and automatic renewal are disabled.',
      'daysLeft': 'Days remaining: {days}',
    },
    'de': {
      'subtitle': 'Themen, Rahmen und lebendige Sticker',
      'freeMonth': '30 TAGE KOSTENLOS',
      'noPayment': 'Keine Karte, keine Abbuchung. Zahlung erst nach dem Test.',
      'activate': 'Gratismonat starten',
      'activated': 'Fenyvo Pro Probemonat gestartet',
      'expired': 'Testzeitraum beendet',
      'features': 'Enthalten',
      'themes': 'Themen',
      'frames': 'Rahmen',
      'stickers': 'Sticker',
      'stickerHint': 'Figur antippen, um die Bewegung zu sehen.',
      'testNotice': 'Testmodus: Zugriff wird nur auf diesem Gerät gespeichert. Abrechnung und Verlängerung sind deaktiviert.',
      'daysLeft': 'Verbleibende Tage: {days}',
    },
    'fr': {
      'subtitle': 'Thèmes, cadres et collection de stickers animés',
      'freeMonth': '30 JOURS GRATUITS',
      'noPayment': 'Sans carte ni débit. Le paiement viendra après les tests.',
      'activate': 'Démarrer le mois gratuit',
      'activated': 'Mois gratuit Fenyvo Pro activé',
      'expired': 'Période d’essai terminée',
      'features': 'Inclus',
      'themes': 'Thèmes',
      'frames': 'Cadres',
      'stickers': 'Stickers',
      'stickerHint': 'Touchez un personnage pour voir son mouvement.',
      'testNotice': 'Mode test : accès enregistré uniquement sur cet appareil. Paiement et renouvellement désactivés.',
      'daysLeft': 'Jours restants : {days}',
    },
    'es': {
      'subtitle': 'Temas, marcos y una colección de stickers vivos',
      'freeMonth': '30 DÍAS GRATIS',
      'noPayment':
          'Sin tarjeta ni cobros. El pago se añadirá tras las pruebas.',
      'activate': 'Iniciar mes gratis',
      'activated': 'Mes gratis de Fenyvo Pro iniciado',
      'expired': 'Prueba finalizada',
      'features': 'Incluye',
      'themes': 'Temas',
      'frames': 'Marcos',
      'stickers': 'Stickers',
      'stickerHint': 'Toca un personaje para ver su movimiento.',
      'testNotice': 'Modo de prueba: el acceso solo se guarda en este dispositivo. Pagos y renovación desactivados.',
      'daysLeft': 'Días restantes: {days}',
    },
    'pt': {
      'subtitle': 'Temas, molduras e uma coleção de stickers vivos',
      'freeMonth': '30 DIAS GRÁTIS',
      'noPayment': 'Sem cartão ou cobranças. O pagamento virá após os testes.',
      'activate': 'Iniciar mês grátis',
      'activated': 'Mês grátis do Fenyvo Pro iniciado',
      'expired': 'Teste terminado',
      'features': 'Incluído',
      'themes': 'Temas',
      'frames': 'Molduras',
      'stickers': 'Stickers',
      'stickerHint': 'Toque num personagem para ver o movimento.',
      'testNotice': 'Modo de teste: acesso guardado apenas neste dispositivo. Pagamento e renovação desativados.',
      'daysLeft': 'Dias restantes: {days}',
    },
    'pl': {
      'subtitle': 'Motywy, ramki i żywa kolekcja naklejek',
      'freeMonth': '30 DNI ZA DARMO',
      'noPayment': 'Bez karty i opłat. Płatności dodamy po testach.',
      'activate': 'Włącz darmowy miesiąc',
      'activated': 'Darmowy miesiąc Fenyvo Pro rozpoczęty',
      'expired': 'Okres próbny zakończony',
      'features': 'W pakiecie',
      'themes': 'Motywy',
      'frames': 'Ramki',
      'stickers': 'Naklejki',
      'stickerHint': 'Dotknij postaci, aby zobaczyć ruch.',
      'testNotice': 'Tryb testowy: dostęp zapisany tylko na tym urządzeniu. Płatności i odnowienie są wyłączone.',
      'daysLeft': 'Pozostało dni: {days}',
    },
    'tr': {
      'subtitle': 'Temalar, çerçeveler ve canlı çıkartmalar',
      'freeMonth': '30 GÜN ÜCRETSİZ',
      'noPayment': 'Kart ve ücret yok. Ödeme testlerden sonra eklenecek.',
      'activate': 'Ücretsiz ayı başlat',
      'activated': 'Fenyvo Pro ücretsiz ayı başladı',
      'expired': 'Deneme süresi bitti',
      'features': 'Dahil',
      'themes': 'Temalar',
      'frames': 'Çerçeveler',
      'stickers': 'Çıkartmalar',
      'stickerHint': 'Hareketi görmek için karaktere dokunun.',
      'testNotice': 'Test modu: erişim yalnızca bu cihazda saklanır. Ödeme ve otomatik yenileme kapalıdır.',
      'daysLeft': 'Kalan gün: {days}',
    },
    'ar': {
      'subtitle': 'سمات وإطارات وملصقات حية',
      'freeMonth': '30 يوماً مجاناً',
      'noPayment': 'بدون بطاقة أو رسوم. ستضاف المدفوعات بعد الاختبار.',
      'activate': 'ابدأ الشهر المجاني',
      'activated': 'بدأ الشهر المجاني من Fenyvo Pro',
      'expired': 'انتهت الفترة التجريبية',
      'features': 'المزايا',
      'themes': 'السمات',
      'frames': 'الإطارات',
      'stickers': 'الملصقات',
      'stickerHint': 'اضغط على الشخصية لمعاينة الحركة.',
      'testNotice': 'وضع تجريبي: يُحفظ الوصول على هذا الجهاز فقط. الدفع والتجديد التلقائي معطلان.',
      'daysLeft': 'الأيام المتبقية: {days}',
    },
    'hi': {
      'subtitle': 'थीम, फ्रेम और जीवंत स्टिकर संग्रह',
      'freeMonth': '30 दिन मुफ़्त',
      'noPayment':
          'कोई कार्ड या शुल्क नहीं। परीक्षण के बाद भुगतान जोड़ा जाएगा।',
      'activate': 'मुफ़्त महीना शुरू करें',
      'activated': 'Fenyvo Pro का मुफ़्त महीना शुरू हुआ',
      'expired': 'परीक्षण समाप्त',
      'features': 'शामिल सुविधाएँ',
      'themes': 'थीम',
      'frames': 'फ्रेम',
      'stickers': 'स्टिकर',
      'stickerHint': 'गतिविधि देखने के लिए पात्र पर टैप करें।',
      'testNotice': 'परीक्षण मोड: पहुँच केवल इस डिवाइस पर सहेजी जाती है। भुगतान और स्वतः नवीनीकरण बंद हैं।',
      'daysLeft': 'शेष दिन: {days}',
    },
    'zh': {
      'subtitle': '主题、头像框和动态贴纸合集',
      'freeMonth': '免费 30 天',
      'noPayment': '无需银行卡，不会扣费。测试后再接入付款。',
      'activate': '开始免费体验',
      'activated': 'Fenyvo Pro 免费体验已开始',
      'expired': '试用期已结束',
      'features': '包含内容',
      'themes': '主题',
      'frames': '头像框',
      'stickers': '贴纸',
      'stickerHint': '点击角色预览动作。',
      'testNotice': '测试模式：权限仅保存在此设备。真实付款和自动续订均已关闭。',
      'daysLeft': '剩余天数：{days}',
    },
    'ja': {
      'subtitle': 'テーマ、フレーム、動くステッカー',
      'freeMonth': '30日間無料',
      'noPayment': 'カードも請求もありません。支払いはテスト後に追加します。',
      'activate': '無料体験を開始',
      'activated': 'Fenyvo Pro無料体験を開始しました',
      'expired': '無料体験は終了しました',
      'features': '含まれるもの',
      'themes': 'テーマ',
      'frames': 'フレーム',
      'stickers': 'ステッカー',
      'stickerHint': 'キャラクターをタップして動きを確認。',
      'testNotice': 'テストモード：アクセスはこの端末のみに保存。課金と自動更新は無効です。',
      'daysLeft': '残り日数：{days}',
    },
  };
}
