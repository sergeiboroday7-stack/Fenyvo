import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppRelease {
  const AppRelease({
    required this.platform,
    required this.version,
    required this.build,
    required this.minimumSupportedBuild,
    required this.downloadUrl,
    required this.publishedAt,
    required this.notes,
    this.sha256,
    this.sizeBytes,
  });

  final String platform;
  final String version;
  final int build;
  final int minimumSupportedBuild;
  final Uri downloadUrl;
  final DateTime? publishedAt;
  final Map<String, List<String>> notes;
  final String? sha256;
  final int? sizeBytes;

  bool isNewerThan(int installedBuild) => build > installedBuild;

  bool isRequiredFor(int installedBuild) =>
      minimumSupportedBuild > 0 && installedBuild < minimumSupportedBuild;

  List<String> notesFor(String languageCode) {
    final normalized = languageCode.toLowerCase().split('-').first;
    return notes[normalized] ?? notes['en'] ?? notes['ru'] ?? const [];
  }

  factory AppRelease.fromManifest(
    Map<String, dynamic> manifest,
    String platform,
  ) {
    final platforms = manifest['platforms'];
    if (platforms is! Map || platforms[platform] is! Map) {
      throw const FormatException('Release platform is missing');
    }
    final data = Map<String, dynamic>.from(platforms[platform] as Map);
    final version = data['version']?.toString().trim() ?? '';
    final build = _asInt(data['build']);
    final minimumSupportedBuild = _asInt(data['minimumSupportedBuild']);
    final downloadUrl = Uri.tryParse(data['downloadUrl']?.toString() ?? '');
    if (version.isEmpty || build <= 0 || downloadUrl == null) {
      throw const FormatException('Release metadata is invalid');
    }
    if (downloadUrl.scheme != 'https' || downloadUrl.host != 'fenyvo.com') {
      throw const FormatException('Release download must use fenyvo.com HTTPS');
    }

    final notes = <String, List<String>>{};
    final rawNotes = data['notes'];
    if (rawNotes is Map) {
      for (final entry in rawNotes.entries) {
        final value = entry.value;
        if (value is List) {
          notes[entry.key.toString().toLowerCase()] = value
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .take(8)
              .toList(growable: false);
        }
      }
    }

    return AppRelease(
      platform: platform,
      version: version,
      build: build,
      minimumSupportedBuild: minimumSupportedBuild,
      downloadUrl: downloadUrl,
      publishedAt: DateTime.tryParse(
        data['publishedAt']?.toString() ??
            manifest['publishedAt']?.toString() ??
            '',
      ),
      notes: notes,
      sha256: data['sha256']?.toString(),
      sizeBytes: data['sizeBytes'] == null ? null : _asInt(data['sizeBytes']),
    );
  }

  static int _asInt(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class AppUpdateCheck {
  const AppUpdateCheck({
    required this.installedVersion,
    required this.installedBuild,
    required this.release,
    this.installedRelease,
  });

  final String installedVersion;
  final int installedBuild;
  final AppRelease release;
  final AppRelease? installedRelease;

  bool get updateAvailable => release.isNewerThan(installedBuild);
  bool get updateRequired => release.isRequiredFor(installedBuild);
  bool get describesInstalledBuild => installedRelease != null;
}

class AppUpdateService {
  AppUpdateService._();

  static final instance = AppUpdateService._();

  final StreamController<void> _releaseSignals = StreamController<void>.broadcast();

  Stream<void> get releaseSignals => _releaseSignals.stream;

  void signalReleaseAvailable() => _releaseSignals.add(null);

  static const manifestUrl = String.fromEnvironment(
    'FENYVO_UPDATE_MANIFEST_URL',
    defaultValue: 'https://fenyvo.com/releases/appcast.json',
  );
  static const _cacheKey = 'fenyvo_update_manifest_cache_v1';
  static const _lastCheckKey = 'fenyvo_update_last_check_ms_v1';
  static const checkInterval = Duration(hours: 6);
  static const requestTimeout = Duration(seconds: 7);
  static const maximumManifestBytes = 256 * 1024;

  Future<AppUpdateCheck?> check({bool force = false}) async {
    final platform = Platform.isAndroid
        ? 'android'
        : Platform.isWindows
        ? 'windows'
        : null;
    if (platform == null) return null;

    final preferences = await SharedPreferences.getInstance();
    String? source;
    final lastCheck = preferences.getInt(_lastCheckKey) ?? 0;
    final cacheIsFresh = DateTime.now().millisecondsSinceEpoch - lastCheck <
        checkInterval.inMilliseconds;

    if (!force && cacheIsFresh) {
      source = preferences.getString(_cacheKey);
    }

    if (source == null) {
      try {
        source = await _downloadManifest();
        await preferences.setString(_cacheKey, source);
        await preferences.setInt(
          _lastCheckKey,
          DateTime.now().millisecondsSinceEpoch,
        );
      } catch (_) {
        source = preferences.getString(_cacheKey);
      }
    }
    if (source == null) return _localInstalledCheck(platform);

    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) return await _localInstalledCheck(platform);
      final manifest = Map<String, dynamic>.from(decoded);
      if (AppRelease._asInt(manifest['schemaVersion']) != 1) {
        return await _localInstalledCheck(platform);
      }
      final release = AppRelease.fromManifest(manifest, platform);
      final package = await PackageInfo.fromPlatform();
      final installedBuild = int.tryParse(package.buildNumber) ?? 0;
      return AppUpdateCheck(
        installedVersion: package.version,
        installedBuild: installedBuild,
        release: release,
        installedRelease: _installedRelease(
          platform,
          package.version,
          installedBuild,
          release,
        ),
      );
    } catch (_) {
      return await _localInstalledCheck(platform);
    }
  }

  Future<AppUpdateCheck?> _localInstalledCheck(String platform) async {
    try {
      final package = await PackageInfo.fromPlatform();
      final installedBuild = int.tryParse(package.buildNumber) ?? 0;
      final installedRelease = _installedRelease(
        platform,
        package.version,
        installedBuild,
        null,
      );
      if (installedRelease == null) return null;
      return AppUpdateCheck(
        installedVersion: package.version,
        installedBuild: installedBuild,
        release: installedRelease,
        installedRelease: installedRelease,
      );
    } catch (_) {
      return null;
    }
  }

  AppRelease? _installedRelease(
    String platform,
    String version,
    int build,
    AppRelease? remote,
  ) {
    if (remote?.build == build) return remote;
    if (build != 4236) return null;
    return AppRelease(
      platform: platform,
      version: version,
      build: build,
      minimumSupportedBuild: 0,
      downloadUrl: Uri.parse(
        platform == 'windows'
            ? 'https://fenyvo.com/download/Fenyvo-1.8.1-windows-x64.zip'
            : 'https://fenyvo.com/download/Fenyvo-1.8.1-arm64.apk',
      ),
      publishedAt: DateTime.utc(2026, 10, 12),
      notes: const {
        'ru': [
          'Fenyvo автоматически проверяет наличие новых версий.',
          'Обновление можно открыть прямо с экрана уведомления.',
          'После установки один раз показывается понятный список изменений.',
          'Проверка работает в фоне и не мешает входу, сообщениям и звонкам.',
        ],
        'uk': [
          'Fenyvo автоматично перевіряє наявність нових версій.',
          'Оновлення можна відкрити прямо з екрана сповіщення.',
          'Після встановлення один раз показується зрозумілий список змін.',
          'Перевірка працює у фоні й не заважає входу, повідомленням та дзвінкам.',
        ],
        'en': [
          'Fenyvo now checks for new versions automatically.',
          'Open the update directly from the release notification.',
          'A clear change summary appears once after installation.',
          'Background checks do not interrupt sign-in, messages, or calls.',
        ],
      },
    );
  }

  Future<String> _downloadManifest() async {
    final client = HttpClient()..connectionTimeout = requestTimeout;
    try {
      final uri = Uri.parse(manifestUrl).replace(
        queryParameters: {'t': DateTime.now().millisecondsSinceEpoch.toString()},
      );
      final request = await client.getUrl(uri).timeout(requestTimeout);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Fenyvo update checker');
      final response = await request.close().timeout(requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Update feed returned ${response.statusCode}');
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(requestTimeout)) {
        bytes.addAll(chunk);
        if (bytes.length > maximumManifestBytes) {
          throw const FormatException('Update feed is too large');
        }
      }
      return utf8.decode(bytes);
    } finally {
      client.close(force: true);
    }
  }
}
