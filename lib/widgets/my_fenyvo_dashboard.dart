import 'package:flutter/material.dart';

import '../theme/spartan_theme.dart';

class MyFenyvoDashboard extends StatelessWidget {
  const MyFenyvoDashboard({
    super.key,
    required this.username,
    required this.avatar,
    required this.status,
    required this.about,
    required this.region,
    required this.phone,
    required this.birthDate,
    required this.uploadingAvatar,
    required this.onAvatarTap,
    required this.onEditProfile,
    required this.onOpenContact,
    required this.onOpenAppearance,
    required this.onOpenPrivacy,
  });

  final String username;
  final Widget avatar;
  final String status;
  final String about;
  final String region;
  final String phone;
  final String birthDate;
  final bool uploadingAvatar;
  final VoidCallback onAvatarTap;
  final VoidCallback onEditProfile;
  final VoidCallback onOpenContact;
  final VoidCallback onOpenAppearance;
  final VoidCallback onOpenPrivacy;

  @override
  Widget build(BuildContext context) {
    final safeStatus = status.trim().isEmpty ? 'На связи' : status.trim();
    final safeAbout = about.trim().isEmpty
        ? 'Ваше личное пространство в Fenyvo'
        : about.trim();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            key: const ValueKey('my-fenyvo-hero'),
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: const Color(0x88C7A65C)),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  SpartanPalette.surfaceRaised,
                  SpartanPalette.canvasDeep,
                ],
              ),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 22,
                  offset: Offset(0, 12),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: SpartanPalette.gold.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                        border: Border.all(color: SpartanPalette.gold),
                      ),
                      child: const Icon(
                        Icons.bolt_rounded,
                        color: SpartanPalette.gold,
                        size: 26,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'МОЙ FENYVO',
                            style: TextStyle(
                              color: SpartanPalette.ink,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Text(
                            'Личный кабинет',
                            style: TextStyle(
                              color: SpartanPalette.gold,
                              fontSize: 12,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    GestureDetector(
                      key: const ValueKey('my-fenyvo-avatar'),
                      onTap: onAvatarTap,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: SpartanPalette.gold,
                                width: 2,
                              ),
                            ),
                            child: avatar,
                          ),
                          Positioned(
                            right: -2,
                            bottom: 2,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: SpartanPalette.gold,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: SpartanPalette.canvasDeep,
                                  width: 3,
                                ),
                              ),
                              child: const Icon(
                                Icons.camera_alt_rounded,
                                color: SpartanPalette.onGold,
                                size: 17,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (uploadingAvatar) ...[
                            const SizedBox(height: 10),
                            const SizedBox(
                              width: 120,
                              child: LinearProgressIndicator(minHeight: 2),
                            ),
                          ],
                          const SizedBox(height: 14),
                          Text(
                            username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: SpartanPalette.ink,
                              fontSize: 23,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: SpartanPalette.online.withValues(
                                alpha: 0.10,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: SpartanPalette.online.withValues(
                                  alpha: 0.45,
                                ),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.circle,
                                  size: 8,
                                  color: SpartanPalette.online,
                                ),
                                const SizedBox(width: 7),
                                Flexible(
                                  child: Text(
                                    safeStatus,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: SpartanPalette.online,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            safeAbout,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.start,
                            style: const TextStyle(
                              color: SpartanPalette.secondary,
                              height: 1.35,
                            ),
                          ),
                          if (region.trim().isNotEmpty) ...[
                            const SizedBox(height: 9),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.location_on_outlined,
                                  color: SpartanPalette.gold,
                                  size: 17,
                                ),
                                const SizedBox(width: 5),
                                Flexible(
                                  child: Text(
                                    region.trim(),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: SpartanPalette.secondary,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                if (phone.trim().isNotEmpty || birthDate.trim().isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Divider(color: SpartanPalette.line),
                  const SizedBox(height: 5),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 18,
                    runSpacing: 8,
                    children: [
                      if (phone.trim().isNotEmpty)
                        _ProfileFact(
                          icon: Icons.phone_outlined,
                          value: phone.trim(),
                        ),
                      if (birthDate.trim().isNotEmpty)
                        _ProfileFact(
                          icon: Icons.cake_outlined,
                          value: _formatBirthDate(birthDate),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'БЫСТРЫЕ ДЕЙСТВИЯ',
              style: TextStyle(
                color: SpartanPalette.gold,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = (constraints.maxWidth - 24) / 3;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _DashboardAction(
                    width: cardWidth,
                    icon: Icons.manage_accounts_rounded,
                    title: 'Профиль',
                    subtitle: 'Данные, QR и контакт',
                    onTap: () {
                      showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        builder: (sheetContext) => SafeArea(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                leading: const Icon(Icons.edit_outlined),
                                title: const Text('Редактировать профиль'),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  onEditProfile();
                                },
                              ),
                              ListTile(
                                leading: const Icon(Icons.qr_code_rounded),
                                title: const Text('Мой контакт и QR-код'),
                                onTap: () {
                                  Navigator.pop(sheetContext);
                                  onOpenContact();
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  _DashboardAction(
                    width: cardWidth,
                    icon: Icons.palette_outlined,
                    title: 'Внешний вид',
                    subtitle: 'Темы и оформление',
                    onTap: onOpenAppearance,
                  ),
                  _DashboardAction(
                    width: cardWidth,
                    icon: Icons.shield_outlined,
                    title: 'Приватность',
                    subtitle: 'Защита общения',
                    onTap: onOpenPrivacy,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Container(
            key: const ValueKey('fenyvo-supporter-banner'),
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: SpartanPalette.gold.withValues(alpha: 0.55),
              ),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  SpartanPalette.surfaceRaised,
                  SpartanPalette.canvasDeep,
                ],
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: SpartanPalette.gold.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: SpartanPalette.gold,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'РАЗВИТИЕ FENYVO',
                        style: TextStyle(
                          color: SpartanPalette.gold,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.7,
                        ),
                      ),
                      SizedBox(height: 7),
                      Text(
                        'Вместе делаем Fenyvo лучше',
                        style: TextStyle(
                          color: SpartanPalette.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 6),
                      Text(
                        'В будущем: особые темы, рамки аватара '
                        'и фирменные значки. Основное общение '
                        'останется бесплатным.',
                        style: TextStyle(
                          color: SpartanPalette.secondary,
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                      SizedBox(height: 10),
                      Text(
                        'НОВЫЕ ВОЗМОЖНОСТИ — ВПЕРЕДИ',
                        style: TextStyle(
                          color: SpartanPalette.gold,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatBirthDate(String value) {
    final parsed = DateTime.tryParse(value.trim());
    if (parsed == null) return value.trim();
    final day = parsed.day.toString().padLeft(2, '0');
    final month = parsed.month.toString().padLeft(2, '0');
    return '$day.$month.${parsed.year}';
  }
}

class _ProfileFact extends StatelessWidget {
  const _ProfileFact({required this.icon, required this.value});

  final IconData icon;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: SpartanPalette.gold, size: 17),
        const SizedBox(width: 6),
        Text(
          value,
          style: const TextStyle(color: SpartanPalette.secondary, fontSize: 13),
        ),
      ],
    );
  }
}

class _DashboardAction extends StatelessWidget {
  const _DashboardAction({
    required this.width,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final double width;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 100,
      child: Material(
        color: SpartanPalette.surfaceRaised,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: SpartanPalette.line),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: SpartanPalette.gold, size: 27),
                const SizedBox(height: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SpartanPalette.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
