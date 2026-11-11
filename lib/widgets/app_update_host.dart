import 'dart:async';
import 'dart:io';

import '../services/windows_update_preparation_service.dart';
import '../services/windows_update_installation_service.dart';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/app_language_service.dart';
import '../services/app_update_service.dart';
import '../services/call_service.dart';
import '../services/group_call_service.dart';
import '../theme/fenyvo_theme.dart';

/// Presents trusted Fenyvo releases without interrupting active calls.
class AppUpdateHost extends StatefulWidget {
  const AppUpdateHost({
    super.key,
    required this.navigatorKey,
    required this.child,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  State<AppUpdateHost> createState() => _AppUpdateHostState();
}

class _AppUpdateHostState extends State<AppUpdateHost>
    with WidgetsBindingObserver {
  static const _installedBuildKey = 'fenyvo_installed_build_seen_v1';
  static const _notesBuildKey = 'fenyvo_release_notes_seen_v1';
  static const _skippedBuildKey = 'fenyvo_update_skipped_build_v1';
  static const _skippedAtKey = 'fenyvo_update_skipped_at_v1';
  static const _remindAfter = Duration(hours: 24);

  bool _busy = false;
  bool _dialogOpen = false;
  Timer? _startupTimer;
  StreamSubscription<void>? _releaseSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _releaseSubscription = AppUpdateService.instance.releaseSignals.listen(
      (_) => _check(force: true),
    );
    _startupTimer = Timer(const Duration(seconds: 4), _check);
  }

  @override
  void dispose() {
    _startupTimer?.cancel();
    _releaseSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startupTimer?.cancel();
      _startupTimer = Timer(const Duration(seconds: 2), _check);
    }
  }

  String get _languageCode {
    final selected = AppLanguageService.instance.code.value;
    if (selected != 'system') return selected;
    return WidgetsBinding.instance.platformDispatcher.locale.languageCode;
  }

  Future<void> _check({bool force = false}) async {
    if (_busy ||
        _dialogOpen ||
        CallService.instance.hasCall ||
        GroupCallService.instance.hasCall) {
      return;
    }
    _busy = true;
    try {
      final check = await AppUpdateService.instance.check(force: force);
      if (!mounted || check == null || check.installedBuild <= 0) return;
      final preferences = await SharedPreferences.getInstance();

      if (check.updateAvailable) {
        if (!check.updateRequired &&
            !_shouldRemind(preferences, check.release.build)) {
          return;
        }
        await _showUpdate(check, preferences);
        return;
      }

      await preferences.setInt(_installedBuildKey, check.installedBuild);
      final notesAlreadySeen =
          preferences.getInt(_notesBuildKey) == check.installedBuild;
      if (check.describesInstalledBuild && !notesAlreadySeen) {
        await _showWhatsNew(check.installedRelease!, preferences);
      }
    } finally {
      _busy = false;
    }
  }

  bool _shouldRemind(SharedPreferences preferences, int build) {
    if (preferences.getInt(_skippedBuildKey) != build) return true;
    final skippedAt = preferences.getInt(_skippedAtKey) ?? 0;
    return DateTime.now().millisecondsSinceEpoch - skippedAt >=
        _remindAfter.inMilliseconds;
  }

  Future<void> _showUpdate(
    AppUpdateCheck check,
    SharedPreferences preferences,
  ) async {
    final context = widget.navigatorKey.currentContext;
    if (context == null || _dialogOpen) return;
    _dialogOpen = true;
    final copy = _UpdateCopy.forLanguage(_languageCode);
    final required = check.updateRequired;
    final action = await showModalBottomSheet<_UpdateAction>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      isDismissible: !required,
      enableDrag: !required,
      backgroundColor: Colors.transparent,
      builder: (_) => PopScope(
        canPop: !required,
        child: _ReleaseSheet(
          title: required ? copy.requiredTitle : copy.updateTitle,
          subtitle: copy.versionLabel(
            check.release.version,
            check.release.build,
          ),
          notesTitle: copy.changes,
          notes: check.release.notesFor(_languageCode),
          primaryLabel: copy.updateNow,
          secondaryLabel: required ? null : copy.later,
          requiredNotice: required ? copy.requiredNotice : null,
        ),
      ),
    );
    _dialogOpen = false;

    if (action == _UpdateAction.primary) {
      if (Platform.isWindows) {
        if (CallService.instance.hasCall || GroupCallService.instance.hasCall) {
          return;
        }

        try {
          final archive = await const WindowsUpdatePreparationService().prepare(
            check.release,
          );

          await const WindowsUpdateInstallationService().stageAndStart(archive);

          if (!mounted) return;

          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.showSnackBar(
            SnackBar(
              content: Text(copy.restartingForUpdate),
              duration: const Duration(seconds: 3),
            ),
          );

          await Future<void>.delayed(const Duration(milliseconds: 250));
          exit(0);
        } catch (error) {
          if (!mounted) return;

          ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(
              content: Text('Не удалось подготовить обновление FENYVO: $error'),
              duration: const Duration(seconds: 8),
            ),
          );
        }
      } else {
        await launchUrl(
          check.release.downloadUrl,
          mode: LaunchMode.externalApplication,
        );
      }
    } else if (!required) {
      await preferences.setInt(_skippedBuildKey, check.release.build);
      await preferences.setInt(
        _skippedAtKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  Future<void> _showWhatsNew(
    AppRelease release,
    SharedPreferences preferences,
  ) async {
    final context = widget.navigatorKey.currentContext;
    if (context == null || _dialogOpen) return;
    _dialogOpen = true;
    final copy = _UpdateCopy.forLanguage(_languageCode);
    await showModalBottomSheet<_UpdateAction>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReleaseSheet(
        title: copy.whatsNew,
        subtitle: copy.versionLabel(release.version, release.build),
        notesTitle: copy.newInFenyvo,
        notes: release.notesFor(_languageCode),
        primaryLabel: copy.continueLabel,
        primaryIcon: Icons.arrow_forward_rounded,
      ),
    );
    _dialogOpen = false;
    await preferences.setInt(_notesBuildKey, release.build);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

enum _UpdateAction { primary }

class _ReleaseSheet extends StatelessWidget {
  const _ReleaseSheet({
    required this.title,
    required this.subtitle,
    required this.notesTitle,
    required this.notes,
    required this.primaryLabel,
    this.secondaryLabel,
    this.requiredNotice,
    this.primaryIcon = Icons.download_rounded,
  });

  final String title;
  final String subtitle;
  final String notesTitle;
  final List<String> notes;
  final String primaryLabel;
  final String? secondaryLabel;
  final String? requiredNotice;
  final IconData primaryIcon;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 22),
        decoration: BoxDecoration(
          color: FenyvoPalette.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: FenyvoPalette.gold.withValues(alpha: .7)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 30,
              offset: Offset(0, -8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: FenyvoPalette.secondary.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: FenyvoPalette.gold.withValues(alpha: .14),
                      border: Border.all(color: FenyvoPalette.gold),
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: FenyvoPalette.gold,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: FenyvoPalette.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                notesTitle.toUpperCase(),
                style: const TextStyle(
                  color: FenyvoPalette.gold,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 12),
              if (notes.isEmpty)
                const Text('Fenyvo is now more stable and convenient.')
              else
                ...notes.map(
                  (note) => Padding(
                    padding: const EdgeInsets.only(bottom: 11),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 3),
                          child: Icon(
                            Icons.check_circle_rounded,
                            color: FenyvoPalette.online,
                            size: 19,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            note,
                            style: const TextStyle(fontSize: 16, height: 1.35),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (requiredNotice != null) ...[
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                    color: FenyvoPalette.gold.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    requiredNotice!,
                    style: const TextStyle(color: FenyvoPalette.secondary),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context).pop(_UpdateAction.primary),
                  icon: Icon(primaryIcon),
                  label: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      primaryLabel,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ),
              if (secondaryLabel != null)
                Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(secondaryLabel!),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateCopy {
  const _UpdateCopy({
    required this.updateTitle,
    required this.requiredTitle,
    required this.whatsNew,
    required this.changes,
    required this.newInFenyvo,
    required this.updateNow,
    required this.later,
    required this.continueLabel,
    required this.requiredNotice,
    required this.restartingForUpdate,
    required this.versionWord,
    required this.buildWord,
  });

  final String updateTitle;
  final String requiredTitle;
  final String whatsNew;
  final String changes;
  final String newInFenyvo;
  final String updateNow;
  final String later;
  final String continueLabel;
  final String requiredNotice;
  final String restartingForUpdate;
  final String versionWord;
  final String buildWord;

  String versionLabel(String version, int build) =>
      '$versionWord $version · $buildWord $build';

  static _UpdateCopy forLanguage(String code) {
    switch (code.toLowerCase().split('-').first) {
      case 'uk':
        return const _UpdateCopy(
          updateTitle: 'Доступне оновлення',
          requiredTitle: 'Потрібне оновлення',
          whatsNew: 'Що нового',
          changes: 'Що змінилося',
          newInFenyvo: 'Нове у Fenyvo',
          updateNow: 'Оновити зараз',
          later: 'Нагадати пізніше',
          continueLabel: 'Продовжити',
          requiredNotice: 'Ця версія більше не сумісна із сервісом. Оновіть Fenyvo, щоб продовжити.',
          restartingForUpdate:
              'FENYVO перезапускається для встановлення оновлення…',
          versionWord: 'Версія',
          buildWord: 'збірка',
        );
      case 'ru':
        return const _UpdateCopy(
          updateTitle: 'Доступно обновление',
          requiredTitle: 'Требуется обновление',
          whatsNew: 'Что нового',
          changes: 'Что изменилось',
          newInFenyvo: 'Новое в Fenyvo',
          updateNow: 'Обновить сейчас',
          later: 'Напомнить позже',
          continueLabel: 'Продолжить',
          requiredNotice: 'Эта версия больше не совместима с сервисом. Обновите Fenyvo, чтобы продолжить.',
          restartingForUpdate:
              'FENYVO перезапускается для установки обновления…',
          versionWord: 'Версия',
          buildWord: 'сборка',
        );
      case 'de':
        return const _UpdateCopy(
          updateTitle: 'Update verfügbar',
          requiredTitle: 'Update erforderlich',
          whatsNew: 'Was ist neu?',
          changes: 'Was wurde geändert?',
          newInFenyvo: 'Neu in Fenyvo',
          updateNow: 'Jetzt aktualisieren',
          later: 'Später erinnern',
          continueLabel: 'Weiter',
          requiredNotice: 'Diese Version ist nicht mehr mit dem Dienst kompatibel. Aktualisiere Fenyvo, um fortzufahren.',
          restartingForUpdate:
              'FENYVO wird neu gestartet, um das Update zu installieren…',
          versionWord: 'Version',
          buildWord: 'Build',
        );
      case 'fr':
        return const _UpdateCopy(
          updateTitle: 'Mise à jour disponible',
          requiredTitle: 'Mise à jour requise',
          whatsNew: 'Nouveautés',
          changes: 'Modifications',
          newInFenyvo: 'Nouveau dans Fenyvo',
          updateNow: 'Mettre à jour',
          later: 'Me le rappeler plus tard',
          continueLabel: 'Continuer',
          requiredNotice: 'Cette version n’est plus compatible avec le service. Mettez Fenyvo à jour pour continuer.',
          restartingForUpdate:
              'FENYVO redémarre pour installer la mise à jour…',
          versionWord: 'Version',
          buildWord: 'build',
        );
      case 'es':
        return const _UpdateCopy(
          updateTitle: 'Actualización disponible',
          requiredTitle: 'Actualización obligatoria',
          whatsNew: 'Novedades',
          changes: 'Qué ha cambiado',
          newInFenyvo: 'Novedades de Fenyvo',
          updateNow: 'Actualizar ahora',
          later: 'Recordar más tarde',
          continueLabel: 'Continuar',
          requiredNotice: 'Esta versión ya no es compatible con el servicio. Actualiza Fenyvo para continuar.',
          restartingForUpdate:
              'FENYVO se reiniciará para instalar la actualización…',
          versionWord: 'Versión',
          buildWord: 'compilación',
        );
      case 'pt':
        return const _UpdateCopy(
          updateTitle: 'Atualização disponível',
          requiredTitle: 'Atualização obrigatória',
          whatsNew: 'Novidades',
          changes: 'O que mudou',
          newInFenyvo: 'Novidades no Fenyvo',
          updateNow: 'Atualizar agora',
          later: 'Lembrar mais tarde',
          continueLabel: 'Continuar',
          requiredNotice: 'Esta versão já não é compatível com o serviço. Atualize o Fenyvo para continuar.',
          restartingForUpdate:
              'O FENYVO será reiniciado para instalar a atualização…',
          versionWord: 'Versão',
          buildWord: 'compilação',
        );
      case 'pl':
        return const _UpdateCopy(
          updateTitle: 'Dostępna aktualizacja',
          requiredTitle: 'Wymagana aktualizacja',
          whatsNew: 'Co nowego',
          changes: 'Co się zmieniło',
          newInFenyvo: 'Nowości w Fenyvo',
          updateNow: 'Aktualizuj teraz',
          later: 'Przypomnij później',
          continueLabel: 'Kontynuuj',
          requiredNotice: 'Ta wersja nie jest już zgodna z usługą. Zaktualizuj Fenyvo, aby kontynuować.',
          restartingForUpdate:
              'FENYVO uruchomi się ponownie, aby zainstalować aktualizację…',
          versionWord: 'Wersja',
          buildWord: 'kompilacja',
        );
      case 'tr':
        return const _UpdateCopy(
          updateTitle: 'Güncelleme mevcut',
          requiredTitle: 'Güncelleme gerekli',
          whatsNew: 'Yenilikler',
          changes: 'Neler değişti',
          newInFenyvo: 'Fenyvo’daki yenilikler',
          updateNow: 'Şimdi güncelle',
          later: 'Daha sonra hatırlat',
          continueLabel: 'Devam et',
          requiredNotice: 'Bu sürüm artık hizmetle uyumlu değil. Devam etmek için Fenyvo’yu güncelleyin.',
          restartingForUpdate:
              'FENYVO güncellemeyi yüklemek için yeniden başlatılıyor…',
          versionWord: 'Sürüm',
          buildWord: 'derleme',
        );
      case 'ar':
        return const _UpdateCopy(
          updateTitle: 'يتوفر تحديث',
          requiredTitle: 'التحديث مطلوب',
          whatsNew: 'ما الجديد',
          changes: 'ما الذي تغير',
          newInFenyvo: 'الجديد في Fenyvo',
          updateNow: 'التحديث الآن',
          later: 'ذكّرني لاحقًا',
          continueLabel: 'متابعة',
          requiredNotice:
              'لم يعد هذا الإصدار متوافقًا مع الخدمة. حدّث Fenyvo للمتابعة.',
          restartingForUpdate: 'تتم إعادة تشغيل FENYVO لتثبيت التحديث…',
          versionWord: 'الإصدار',
          buildWord: 'البنية',
        );
      case 'hi':
        return const _UpdateCopy(
          updateTitle: 'अपडेट उपलब्ध है',
          requiredTitle: 'अपडेट आवश्यक है',
          whatsNew: 'नया क्या है',
          changes: 'क्या बदला',
          newInFenyvo: 'Fenyvo में नया',
          updateNow: 'अभी अपडेट करें',
          later: 'बाद में याद दिलाएँ',
          continueLabel: 'जारी रखें',
          requiredNotice: 'यह संस्करण अब सेवा के अनुकूल नहीं है। जारी रखने के लिए Fenyvo अपडेट करें।',
          restartingForUpdate:
              'अपडेट इंस्टॉल करने के लिए FENYVO फिर से शुरू हो रहा है…',
          versionWord: 'संस्करण',
          buildWord: 'बिल्ड',
        );
      case 'zh':
        return const _UpdateCopy(
          updateTitle: '有可用更新',
          requiredTitle: '需要更新',
          whatsNew: '更新内容',
          changes: '已更改内容',
          newInFenyvo: 'Fenyvo 新功能',
          updateNow: '立即更新',
          later: '稍后提醒',
          continueLabel: '继续',
          requiredNotice: '此版本已不再兼容服务。请更新 Fenyvo 以继续。',
          restartingForUpdate: 'FENYVO 正在重启以安装更新…',
          versionWord: '版本',
          buildWord: '构建',
        );
      case 'ja':
        return const _UpdateCopy(
          updateTitle: 'アップデートがあります',
          requiredTitle: 'アップデートが必要です',
          whatsNew: '新機能',
          changes: '変更内容',
          newInFenyvo: 'Fenyvo の新機能',
          updateNow: '今すぐ更新',
          later: '後で通知',
          continueLabel: '続ける',
          requiredNotice: 'このバージョンはサービスとの互換性がありません。続行するには Fenyvo を更新してください。',
          restartingForUpdate: 'アップデートをインストールするため FENYVO を再起動しています…',
          versionWord: 'バージョン',
          buildWord: 'ビルド',
        );
      default:
        return const _UpdateCopy(
          updateTitle: 'Update available',
          requiredTitle: 'Update required',
          whatsNew: "What's new",
          changes: 'What changed',
          newInFenyvo: 'New in Fenyvo',
          updateNow: 'Update now',
          later: 'Remind me later',
          continueLabel: 'Continue',
          requiredNotice: 'This version is no longer compatible with the service. Update Fenyvo to continue.',
          restartingForUpdate: 'FENYVO is restarting to install the update…',
          versionWord: 'Version',
          buildWord: 'build',
        );
    }
  }
}
