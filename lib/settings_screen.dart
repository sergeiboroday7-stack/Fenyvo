import 'theme/spartan_theme.dart';

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'services/socket_service.dart';
import 'services/storage_service.dart';
import 'services/app_language_service.dart';
import 'services/e2ee_settings_service.dart';

class SettingsScreen extends StatefulWidget {
  final String username;
  final VoidCallback onLogout;

  const SettingsScreen({
    super.key,
    required this.username,
    required this.onLogout,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String? _avatarPath;

  bool _isUploadingAvatar = false;

  String? _backgroundPath;
  bool _lightWallpaperEnabled = false;

  double _backgroundOpacity = 0.35;

  int _selectedTextColor = 0xFFFFFFFF;
  bool _e2eeEnabled = false;
  bool _changingE2ee = false;
  String _profileAbout = '';
  String _profileRegion = '';
  String _profileStatus = '';

  void _showSupportDialog() {
    final language = AppLanguageService.instance;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(language.text('supportSpartan')),
        content: SizedBox(
          width: 420,
          height: MediaQuery.sizeOf(context).height * 0.68,
          child: _SupportPaymentCard(language: language),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(language.text('close')),
          ),
        ],
      ),
    );
  }

  Future<void> _showLanguagePicker() async {
    final language = AppLanguageService.instance;
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(language.text('language')),
        children: [
          RadioGroup<String>(
            groupValue: language.code.value,
            onChanged: (value) {
              if (value != null) {
                Navigator.pop(context, value);
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: AppLanguageService.languages
                  .map(
                    (item) => RadioListTile<String>(
                      value: item.code,
                      title: Text('${item.flag}  ${item.label}'),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
    if (selected != null) {
      await language.select(selected);
      if (mounted) setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();

    _loadAvatar();
    _loadBackground();
    _loadBackgroundOpacity();
    _loadTextColor();
    _loadE2ee();
    SocketService.instance.addMessageHandler(_handleProfileMessage);
    SocketService.instance.getUserProfile(widget.username);
  }

  @override
  void dispose() {
    SocketService.instance.removeMessageHandler(_handleProfileMessage);
    super.dispose();
  }

  void _handleProfileMessage(Map<String, dynamic> packet) {
    final type = packet['type']?.toString() ?? '';
    if (type != 'user_profile' && type != 'user_profile_updated') return;
    final raw = packet['data'];
    if (raw is! Map) return;
    final data = Map<String, dynamic>.from(raw);
    if ((data['username']?.toString() ?? '') != widget.username || !mounted) {
      return;
    }
    setState(() {
      _profileAbout = data['about']?.toString() ?? '';
      _profileRegion = data['region']?.toString() ?? '';
      _profileStatus = data['statusText']?.toString() ?? '';
    });
  }

  Future<void> _editProfile() async {
    final status = TextEditingController(text: _profileStatus);
    final about = TextEditingController(text: _profileAbout);
    final region = TextEditingController(text: _profileRegion);
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Профиль'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: status,
                maxLength: 80,
                decoration: const InputDecoration(
                  labelText: 'Статус',
                  hintText: 'Например: Сила в людях',
                ),
              ),
              TextField(
                controller: about,
                maxLength: 160,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'О себе'),
              ),
              TextField(
                controller: region,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Регион'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (save == true) {
      SocketService.instance.updateUserProfile(
        about: about.text,
        region: region.text,
        statusText: status.text,
      );
    }
    status.dispose();
    about.dispose();
    region.dispose();
  }

  Future<void> _loadE2ee() async {
    final enabled = await E2eeSettingsService.instance.isEnabled();
    if (mounted) setState(() => _e2eeEnabled = enabled);
  }

  Future<void> _changeE2ee(bool enabled) async {
    final t = AppLanguageService.instance.text;
    if (enabled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(t('e2eeTitle')),
          content: Text(t('e2eeExplanation')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('e2eeEnable')),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    if (!mounted) return;
    setState(() => _changingE2ee = true);
    final changed = await SocketService.instance.setE2eeEnabled(enabled);
    if (!mounted) return;
    setState(() {
      _changingE2ee = false;
      if (changed) _e2eeEnabled = enabled;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          changed
              ? enabled
                    ? t('e2eeEnabledNotice')
                    : t('e2eeDisabledNotice')
              : t('e2eeEnableError'),
        ),
      ),
    );
  }

  // ========================================
  // АВАТАР
  // ========================================

  Future<void> _loadAvatar() async {
    final avatar = StorageService.getAvatar(widget.username);

    if (!mounted) {
      return;
    }

    setState(() {
      _avatarPath = avatar;
    });
  }

  Future<void> _pickAvatar() async {
    try {
      final picker = ImagePicker();

      final XFile? image = await picker.pickImage(source: ImageSource.gallery);

      if (image == null) {
        return;
      }

      setState(() {
        _isUploadingAvatar = true;
      });

      StorageService.saveAvatar(widget.username, image.path);

      await SocketService.instance.setAvatarFromPath(image.path);

      if (!mounted) {
        return;
      }

      setState(() {
        _avatarPath = image.path;

        _isUploadingAvatar = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Аватарка обновлена'),
          backgroundColor: SpartanPalette.blue,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      setState(() {
        _isUploadingAvatar = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _deleteAvatar() async {
    try {
      StorageService.saveAvatar(widget.username, '');

      await SocketService.instance.deleteAvatar();

      if (!mounted) {
        return;
      }

      setState(() {
        _avatarPath = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Аватарка удалена'),
          backgroundColor: Colors.red,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка удаления: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _showAvatarActions() async {
    final language = AppLanguageService.instance;
    final hasAvatar = _avatarPath?.isNotEmpty == true;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(language.text('changeAvatar')),
              onTap: () => Navigator.pop(context, 'change'),
            ),
            if (hasAvatar)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: Text(
                  language.text('deleteAvatar'),
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
            ListTile(
              leading: const Icon(Icons.close),
              title: Text(language.text('cancel')),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
    if (action == 'change') await _pickAvatar();
    if (action == 'delete') await _deleteAvatar();
  }

  // ========================================
  // ФОН
  // ========================================

  Future<void> _loadBackground() async {
    final bg = await StorageService.getBackground();
    final enabled = await StorageService.isLightWallpaperEnabled();

    if (!mounted) {
      return;
    }

    String? validBackground;

    if (bg != null && bg.isNotEmpty) {
      final file = File(bg);

      if (file.existsSync()) {
        validBackground = bg;
      }
    }

    setState(() {
      _backgroundPath = validBackground;
      _lightWallpaperEnabled = enabled;
    });
  }

  Future<void> _loadBackgroundOpacity() async {
    final opacity = await StorageService.getBackgroundOpacity();

    if (!mounted) {
      return;
    }

    setState(() {
      _backgroundOpacity = opacity;
    });
  }

  Future<String> _copyBackgroundToAppStorage(String sourcePath) async {
    final sourceFile = File(sourcePath);

    final directory = await getApplicationDocumentsDirectory();

    final mediaDirectory = Directory(
      '${directory.path}${Platform.pathSeparator}spartan_media',
    );

    if (!await mediaDirectory.exists()) {
      await mediaDirectory.create(recursive: true);
    }

    String extension = '';

    final fileName = sourceFile.uri.pathSegments.isNotEmpty
        ? sourceFile.uri.pathSegments.last
        : '';

    final dotIndex = fileName.lastIndexOf('.');

    if (dotIndex >= 0 && dotIndex < fileName.length - 1) {
      extension = fileName.substring(dotIndex);
    }

    if (extension.isEmpty || extension.length > 6) {
      extension = '.jpg';
    }

    final destinationPath =
        '${mediaDirectory.path}'
        '${Platform.pathSeparator}'
        'chat_background$extension';

    // Удаляем старые варианты нашего
    // пользовательского фона.
    if (await mediaDirectory.exists()) {
      final files = mediaDirectory.listSync();

      for (final entity in files) {
        if (entity is File) {
          final name = entity.uri.pathSegments.isNotEmpty
              ? entity.uri.pathSegments.last
              : '';

          if (name.startsWith('chat_background.')) {
            try {
              await entity.delete();
            } catch (_) {}
          }
        }
      }
    }

    final copiedFile = await sourceFile.copy(destinationPath);

    return copiedFile.path;
  }

  Future<void> _pickBackground() async {
    try {
      final picker = ImagePicker();

      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 2000,
        maxHeight: 2000,
      );

      if (image == null) {
        return;
      }

      final persistentPath = await _copyBackgroundToAppStorage(image.path);

      await StorageService.saveBackground(persistentPath);

      if (!mounted) {
        return;
      }

      setState(() {
        _backgroundPath = persistentPath;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Фон обновлён'),
          backgroundColor: SpartanPalette.blue,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка выбора фона: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _removeBackground() async {
    final oldBackground = _backgroundPath;

    await StorageService.removeBackground();

    if (oldBackground != null && oldBackground.isNotEmpty) {
      try {
        final file = File(oldBackground);

        if (file.existsSync()) {
          await file.delete();
        }
      } catch (_) {}
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _backgroundPath = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Включён стандартный фон'),
        backgroundColor: SpartanPalette.blue,
      ),
    );
  }

  Future<void> _saveBackgroundOpacity(double value) async {
    await StorageService.saveBackgroundOpacity(value);
  }

  // ========================================
  // ЦВЕТ ТЕКСТА
  // ========================================

  Future<void> _loadTextColor() async {
    final color = await StorageService.getTextColor();

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedTextColor = color;
    });
  }

  void _showTextColorPicker() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SpartanPalette.surface,
        title: const Text(
          'Выберите цвет текста',
          style: TextStyle(color: SpartanPalette.ink),
        ),
        content: SizedBox(
          width: double.infinity,
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _colorTile(Colors.white),
              _colorTile(Colors.grey),
              _colorTile(Colors.black),
              _colorTile(Colors.red),
              _colorTile(Colors.green),
              _colorTile(Colors.blue),
              _colorTile(Colors.yellow),
              _colorTile(Colors.orange),
              _colorTile(Colors.purple),
              _colorTile(Colors.pink),
              _colorTile(Colors.teal),
              _colorTile(Colors.cyan),
            ],
          ),
        ),
      ),
    );
  }

  Widget _colorTile(Color color) {
    final colorValue = color.toARGB32();

    final isSelected = _selectedTextColor == colorValue;

    return GestureDetector(
      onTap: () async {
        await StorageService.saveTextColor(colorValue);

        if (!mounted) {
          return;
        }

        setState(() {
          _selectedTextColor = colorValue;
        });

        Navigator.pop(context);
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? SpartanPalette.ink : Colors.transparent,
            width: 3,
          ),
        ),
        child: isSelected
            ? const Icon(Icons.check, color: SpartanPalette.ink, size: 20)
            : null,
      ),
    );
  }

  // ========================================
  // АВАТАР В НАСТРОЙКАХ
  // ========================================

  Widget _buildAvatar() {
    if (_avatarPath != null && _avatarPath!.isNotEmpty) {
      ImageProvider? avatarImage;
      final file = File(_avatarPath!);

      if (file.existsSync()) {
        avatarImage = FileImage(file);
      } else {
        try {
          final encoded = _avatarPath!.contains(',')
              ? _avatarPath!.split(',').last
              : _avatarPath!;
          avatarImage = MemoryImage(base64Decode(encoded));
        } catch (_) {
          avatarImage = null;
        }
      }

      if (avatarImage != null) {
        return CircleAvatar(
          radius: 48,
          backgroundColor: SpartanPalette.blue,
          backgroundImage: avatarImage,
        );
      }
    }

    return CircleAvatar(
      radius: 48,
      backgroundColor: SpartanPalette.blue,
      child: Text(
        widget.username.isNotEmpty ? widget.username[0].toUpperCase() : '?',
        style: const TextStyle(
          color: SpartanPalette.ink,
          fontSize: 32,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ========================================
  // СЕКЦИИ
  // ========================================

  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text(
            title,
            style: const TextStyle(
              color: SpartanPalette.ink,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  Widget _buildSectionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color iconColor = SpartanPalette.ink,
    Color titleColor = SpartanPalette.ink,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title, style: TextStyle(color: titleColor)),
      subtitle: Text(
        subtitle,
        style: const TextStyle(color: SpartanPalette.secondary, fontSize: 12),
      ),
      onTap: onTap,
    );
  }

  // ========================================
  // ПРЕДПРОСМОТР ФОНА
  // ========================================

  Widget _buildBackgroundPreview() {
    final language = AppLanguageService.instance;
    final backgroundPath = _backgroundPath;

    if (backgroundPath == null || backgroundPath.isEmpty) {
      return Container(
        height: 90,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Color(0x55171B20)),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [SpartanPalette.surface, SpartanPalette.canvas],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.local_fire_department,
                color: SpartanPalette.ink,
              ),
              const SizedBox(height: 5),
              Text(
                language.text('blueGoldTheme'),
                style: const TextStyle(
                  color: SpartanPalette.ink,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final file = File(backgroundPath);

    if (!file.existsSync()) {
      return const SizedBox.shrink();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        children: [
          SizedBox(
            height: 110,
            width: double.infinity,
            child: ColoredBox(
              color: SpartanPalette.canvas,
              child: Opacity(
                opacity: _backgroundOpacity,
                child: Image.file(
                  file,
                  width: double.infinity,
                  height: 110,
                  fit: BoxFit.cover,
                  alignment: Alignment.center,
                  gaplessPlayback: true,
                ),
              ),
            ),
          ),

          Positioned(
            left: 10,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: SpartanPalette.surface.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                AppLanguageService.instance.text('preview'),
                style: const TextStyle(color: SpartanPalette.ink, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackgroundOpacityControl() {
    final percent = (_backgroundOpacity * 100).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
        decoration: BoxDecoration(
          color: SpartanPalette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Color(0x33171B20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.opacity, color: SpartanPalette.ink, size: 21),

                const SizedBox(width: 10),

                Expanded(
                  child: Text(
                    AppLanguageService.instance.text('backgroundVisibility'),
                    style: const TextStyle(
                      color: SpartanPalette.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),

                Text(
                  '$percent%',
                  style: const TextStyle(
                    color: SpartanPalette.ink,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),

            Slider(
              value: _backgroundOpacity,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              activeColor: SpartanPalette.blue,
              inactiveColor: SpartanPalette.surface,
              label: '$percent%',
              onChanged: (value) {
                setState(() {
                  _backgroundOpacity = value;
                });
              },
              onChangeEnd: (value) {
                _saveBackgroundOpacity(value);
              },
            ),

            Text(
              AppLanguageService.instance.text('backgroundScale'),
              style: const TextStyle(
                color: SpartanPalette.secondary,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ========================================
  // ЭКРАН
  // ========================================

  @override
  Widget build(BuildContext context) {
    final language = AppLanguageService.instance;
    String t(String key) => language.text(key);
    return Scaffold(
      backgroundColor: SpartanPalette.canvas,

      appBar: AppBar(
        backgroundColor: SpartanPalette.canvas,
        title: Text(
          t('settings'),
          style: const TextStyle(
            color: SpartanPalette.ink,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: SpartanPalette.ink),
      ),

      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [SpartanPalette.canvas, SpartanPalette.surface],
          ),
        ),

        child: ListView(
          children: [
            const SizedBox(height: 24),

            Center(
              child: GestureDetector(
                onTap: _showAvatarActions,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    _buildAvatar(),

                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: SpartanPalette.blue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: SpartanPalette.ink,
                          size: 18,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (_isUploadingAvatar)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Center(
                  child: Text(
                    'Загрузка аватарки...',
                    style: TextStyle(color: SpartanPalette.ink, fontSize: 12),
                  ),
                ),
              ),

            const SizedBox(height: 12),

            Center(
              child: Text(
                widget.username,
                style: const TextStyle(
                  color: SpartanPalette.ink,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            const SizedBox(height: 4),

            Center(
              child: Text(
                t('changePhoto'),
                style: const TextStyle(
                  color: SpartanPalette.secondary,
                  fontSize: 12,
                ),
              ),
            ),

            _buildSection('Профиль', [
              _buildSectionTile(
                icon: Icons.manage_accounts_rounded,
                title: 'Заполнить профиль',
                subtitle: [
                  if (_profileStatus.isNotEmpty) _profileStatus,
                  if (_profileRegion.isNotEmpty) _profileRegion,
                  if (_profileStatus.isEmpty && _profileRegion.isEmpty)
                    'Статус, о себе и регион',
                ].join(' · '),
                onTap: _editProfile,
              ),
            ]),

            _buildSection(t('supportSection'), [
              _SpartanSupportTile(
                title: t('supportSpartan'),
                subtitle: t('supportSubtitle'),
                onTap: _showSupportDialog,
              ),
            ]),

            _buildSection(t('languageSection'), [
              _buildSectionTile(
                icon: Icons.language_rounded,
                title: t('language'),
                subtitle: AppLanguageService.languages
                    .firstWhere(
                      (item) =>
                          item.code == AppLanguageService.instance.code.value,
                    )
                    .label,
                onTap: _showLanguagePicker,
              ),
            ]),

            _buildSection(t('securitySection'), [
              SwitchListTile.adaptive(
                secondary: const Icon(Icons.lock_outline_rounded),
                title: Text(t('e2eeTitle')),
                subtitle: Text(
                  _e2eeEnabled ? t('e2eeOnSubtitle') : t('e2eeOffSubtitle'),
                ),
                value: _e2eeEnabled,
                onChanged: _changingE2ee ? null : _changeE2ee,
              ),
              if (_changingE2ee)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: LinearProgressIndicator(),
                ),
            ]),

            const SizedBox(height: 12),

            // =================================
            // ВНЕШНИЙ ВИД
            // =================================
            _buildSection(t('appearance'), [
              ListTile(
                leading: const Icon(Icons.light_mode_outlined),
                title: const Text('FENYVO · BLUE GOLD'),
                subtitle: Text(t('themeSubtitle')),
              ),
              SwitchListTile.adaptive(
                title: Text(t('wallpaperToggle')),
                subtitle: Text(t('wallpaperToggleSubtitle')),
                value: _lightWallpaperEnabled,
                onChanged: (value) async {
                  await StorageService.setLightWallpaperEnabled(value);
                  if (mounted) setState(() => _lightWallpaperEnabled = value);
                },
              ),
              _buildSectionTile(
                icon: Icons.wallpaper,
                title: t('chatBackground'),
                subtitle: _backgroundPath == null
                    ? t('blueGoldTheme')
                    : t('galleryPhoto'),
                onTap: _pickBackground,
              ),

              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: _buildBackgroundPreview(),
              ),

              _buildBackgroundOpacityControl(),

              if (_backgroundPath != null)
                _buildSectionTile(
                  icon: Icons.restart_alt,
                  title: t('defaultBackground'),
                  subtitle: t('restoreBlueBackground'),
                  onTap: _removeBackground,
                  iconColor: SpartanPalette.ink,
                  titleColor: SpartanPalette.ink,
                ),

              _buildSectionTile(
                icon: Icons.format_color_text,
                title: t('textColor'),
                subtitle: t('chooseTextColor'),
                onTap: _showTextColorPicker,
              ),
            ]),

            const Divider(color: SpartanPalette.ink, height: 30),

            // =================================
            // АККАУНТ
            // =================================
            _buildSection(t('account'), [
              ListTile(
                leading: const Icon(Icons.person, color: SpartanPalette.ink),
                title: Text(
                  widget.username,
                  style: const TextStyle(
                    color: SpartanPalette.ink,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  t('currentAccount'),
                  style: const TextStyle(color: SpartanPalette.secondary),
                ),
              ),

              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.red),
                title: Text(
                  t('logout'),
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () {
                  widget.onLogout();
                },
              ),
            ]),

            const SizedBox(height: 30),
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

class _SupportPaymentCard extends StatefulWidget {
  const _SupportPaymentCard({required this.language});

  final AppLanguageService language;

  @override
  State<_SupportPaymentCard> createState() => _SupportPaymentCardState();
}

class _SupportPaymentCardState extends State<_SupportPaymentCard> {
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
      SnackBar(content: Text(widget.language.text('addressCopied'))),
    );
  }

  Future<void> _showQr(BuildContext context, _CryptoNetwork network) async {
    String t(String key) => widget.language.text(key);
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
                'Account 1 / ${network.name}',
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
                  eyeStyle: const QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: Colors.black,
                  ),
                  dataModuleStyle: const QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: Colors.black,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                '${t('cryptoAddress')} · ${network.name}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              SelectableText(
                network.address,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, height: 1.35),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: SpartanPalette.gold,
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
                onPressed: () async {
                  await launchUrl(
                    network.explorerUri,
                    mode: LaunchMode.externalApplication,
                  );
                },
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
    String t(String key) => widget.language.text(key);

    return Column(
      children: [
        Text(
          t('cryptoInstruction'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: ListView.separated(
            itemCount: _networks.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final network = _networks[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 2,
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
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: t('copyAddress'),
                      onPressed: () => _copyAddress(context, network),
                      icon: const Icon(Icons.copy_rounded),
                    ),
                    IconButton(
                      tooltip: 'QR · ${network.name}',
                      onPressed: () => _showQr(context, network),
                      icon: const Icon(Icons.qr_code_rounded),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Text(
          t('cryptoWarning'),
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: Colors.orange,
            fontSize: 11,
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _SpartanSupportTile extends StatefulWidget {
  const _SpartanSupportTile({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  State<_SpartanSupportTile> createState() => _SpartanSupportTileState();
}

class _SpartanSupportTileState extends State<_SpartanSupportTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: widget.onTap,
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              gradient: const LinearGradient(
                colors: [Color(0xFF263D57), Color(0xFF162B43)],
              ),
              border: Border.all(color: SpartanPalette.gold, width: 1.2),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x44D4AF37),
                  blurRadius: 18,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) => Transform.scale(
                    scale: 0.96 + (_controller.value * 0.08),
                    child: Container(
                      width: 62,
                      height: 62,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: const Color(0xFF091B2D),
                        border: Border.all(
                          color: SpartanPalette.gold.withValues(
                            alpha: 0.55 + (_controller.value * 0.45),
                          ),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: SpartanPalette.gold.withValues(
                              alpha: 0.12 + (_controller.value * 0.25),
                            ),
                            blurRadius: 10 + (_controller.value * 12),
                          ),
                        ],
                      ),
                      child: child,
                    ),
                  ),
                  child: Image.asset('assets/images/spartan_brand.png'),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: const TextStyle(
                          color: SpartanPalette.ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.subtitle,
                        style: const TextStyle(
                          color: SpartanPalette.secondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: SpartanPalette.gold,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
