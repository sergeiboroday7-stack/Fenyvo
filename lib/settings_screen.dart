import 'theme/spartan_theme.dart';

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'services/socket_service.dart';
import 'services/storage_service.dart';

class SettingsScreen extends StatefulWidget {
  final String username;
  final VoidCallback onLogout;
  final VoidCallback onDeleteAccount;

  const SettingsScreen({
    super.key,
    required this.username,
    required this.onLogout,
    required this.onDeleteAccount,
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

  String _selectedMode = 'random';

  final List<String> _customStatuses = [];

  final TextEditingController _newStatusController = TextEditingController();

  @override
  void initState() {
    super.initState();

    _loadAvatar();
    _loadBackground();
    _loadBackgroundOpacity();
    _loadTextColor();
    _loadStatuses();
  }

  @override
  void dispose() {
    _newStatusController.dispose();

    super.dispose();
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
      final file = File(_avatarPath!);

      if (file.existsSync()) {
        return CircleAvatar(
          radius: 48,
          backgroundColor: SpartanPalette.blue,
          backgroundImage: FileImage(file),
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
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_fire_department, color: SpartanPalette.ink),
              SizedBox(height: 5),
              Text(
                'Сине-золотая тема',
                style: TextStyle(
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
              child: const Text(
                'Предпросмотр',
                style: TextStyle(color: SpartanPalette.ink, fontSize: 11),
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

                const Expanded(
                  child: Text(
                    'Видимость фона',
                    style: TextStyle(
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

            const Text(
              '0% — фон почти не виден, 100% — максимальная видимость.',
              style: TextStyle(color: SpartanPalette.secondary, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  // ========================================
  // СТАТУСЫ
  // ========================================

  Widget _buildModeTile({
    required String title,
    required String value,
    required String icon,
  }) {
    final isSelected = _selectedMode == value;

    return ListTile(
      leading: Text(icon, style: const TextStyle(fontSize: 24)),
      title: Text(title, style: const TextStyle(color: SpartanPalette.ink)),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: SpartanPalette.ink)
          : null,
      onTap: () {
        setState(() {
          _selectedMode = value;
        });
      },
    );
  }

  void _loadStatuses() {
    // Пока статусы хранятся
    // только во время работы приложения.
  }

  void _addCustomStatus() {
    final text = _newStatusController.text.trim();

    if (text.isEmpty) {
      return;
    }

    setState(() {
      _customStatuses.add(text);

      _newStatusController.clear();
    });
  }

  void _removeCustomStatus(int index) {
    setState(() {
      _customStatuses.removeAt(index);
    });
  }

  // ========================================
  // УДАЛЕНИЕ АККАУНТА
  // ========================================

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: SpartanPalette.surface,
        title: const Text(
          'Удалить аккаунт?',
          style: TextStyle(color: SpartanPalette.ink),
        ),
        content: const Text(
          'Это действие необратимо. '
          'Все данные будут удалены.',
          style: TextStyle(color: SpartanPalette.secondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text(
              'Отмена',
              style: TextStyle(color: SpartanPalette.secondary),
            ),
          ),

          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);

              widget.onDeleteAccount();
            },
            child: const Text('Удалить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // ========================================
  // ЭКРАН
  // ========================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SpartanPalette.canvas,

      appBar: AppBar(
        backgroundColor: SpartanPalette.canvas,
        title: const Text(
          'НАСТРОЙКИ',
          style: TextStyle(
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
                onTap: _pickAvatar,
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

            const Center(
              child: Text(
                'Нажмите на фото, чтобы изменить',
                style: TextStyle(color: SpartanPalette.secondary, fontSize: 12),
              ),
            ),

            if (_avatarPath != null && _avatarPath!.isNotEmpty)
              Center(
                child: TextButton.icon(
                  onPressed: _deleteAvatar,
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  label: const Text(
                    'Удалить аватарку',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ),

            const SizedBox(height: 12),

            // =================================
            // ВНЕШНИЙ ВИД
            // =================================
            _buildSection('ВНЕШНИЙ ВИД', [
              const ListTile(
                leading: Icon(Icons.light_mode_outlined),
                title: Text('SPARTAN · BLUE GOLD'),
                subtitle: Text(
                  'Глубокий синий фон и спокойные золотые акценты',
                ),
              ),
              SwitchListTile.adaptive(
                title: const Text('Показывать фото на фоне чата'),
                subtitle: const Text(
                  'Выключено — спокойный синий фон. Сохранённое фото не удаляется.',
                ),
                value: _lightWallpaperEnabled,
                onChanged: (value) async {
                  await StorageService.setLightWallpaperEnabled(value);
                  if (mounted) setState(() => _lightWallpaperEnabled = value);
                },
              ),
              _buildSectionTile(
                icon: Icons.wallpaper,
                title: 'Фон переписки',
                subtitle: _backgroundPath == null
                    ? 'Сине-золотая тема'
                    : 'Фото из галереи',
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
                  title: 'Стандартный фон',
                  subtitle: 'Вернуть синий фон',
                  onTap: _removeBackground,
                  iconColor: SpartanPalette.ink,
                  titleColor: SpartanPalette.ink,
                ),

              _buildSectionTile(
                icon: Icons.format_color_text,
                title: 'Цвет текста',
                subtitle: 'Выберите цвет сообщений',
                onTap: _showTextColorPicker,
              ),
            ]),

            // =================================
            // СТАТУСЫ
            // =================================
            _buildSection('СТАТУСЫ', [
              _buildModeTile(
                title: 'Случайные статусы',
                value: 'random',
                icon: '🎲',
              ),
              _buildModeTile(
                title: 'Статусы по дням',
                value: 'day',
                icon: '📅',
              ),
              _buildModeTile(
                title: 'Свои статусы',
                value: 'custom',
                icon: '✏️',
              ),
            ]),

            if (_selectedMode == 'custom')
              _buildSection('МОИ СТАТУСЫ', [
                ..._customStatuses.asMap().entries.map((entry) {
                  return ListTile(
                    leading: const Icon(
                      Icons.format_quote,
                      color: SpartanPalette.ink,
                    ),
                    title: Text(
                      entry.value,
                      style: const TextStyle(color: SpartanPalette.ink),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      onPressed: () => _removeCustomStatus(entry.key),
                    ),
                  );
                }),

                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _newStatusController,
                          style: const TextStyle(color: SpartanPalette.ink),
                          decoration: InputDecoration(
                            hintText: 'Новый статус...',
                            hintStyle: const TextStyle(
                              color: SpartanPalette.secondary,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: const BorderSide(
                                color: SpartanPalette.surface,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(30),
                              borderSide: const BorderSide(
                                color: SpartanPalette.ink,
                              ),
                            ),
                          ),
                          onSubmitted: (_) => _addCustomStatus(),
                        ),
                      ),

                      const SizedBox(width: 8),

                      Container(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              SpartanPalette.blue,
                              SpartanPalette.blueDeep,
                            ],
                          ),
                        ),
                        child: IconButton(
                          icon: const Icon(
                            Icons.add,
                            color: SpartanPalette.ink,
                          ),
                          onPressed: _addCustomStatus,
                        ),
                      ),
                    ],
                  ),
                ),
              ]),

            const Divider(color: SpartanPalette.ink, height: 30),

            // =================================
            // АККАУНТ
            // =================================
            _buildSection('АККАУНТ', [
              ListTile(
                leading: const Icon(Icons.person, color: SpartanPalette.ink),
                title: Text(
                  widget.username,
                  style: const TextStyle(
                    color: SpartanPalette.ink,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  'Текущий аккаунт',
                  style: TextStyle(color: SpartanPalette.secondary),
                ),
              ),

              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.red),
                title: const Text('Выйти', style: TextStyle(color: Colors.red)),
                onTap: () {
                  widget.onLogout();
                },
              ),

              ListTile(
                leading: const Icon(Icons.delete_forever, color: Colors.red),
                title: const Text(
                  'Удалить аккаунт',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: _showDeleteAccountDialog,
              ),
            ]),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}
