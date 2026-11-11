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
              .map((item) => repairMojibake(item.toString().trim()))
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

  /// Repairs UTF-8 release notes that were accidentally decoded as Windows-1251
  /// before being placed in the update manifest.
  ///
  /// Correct text is returned unchanged. The repair is accepted only when the
  /// source strongly resembles mojibake and the decoded result contains fewer
  /// corruption markers.
  static String repairMojibake(String value) {
    final sourceScore = _mojibakeScore(value);
    if (sourceScore < 2) return value;

    final bytes = <int>[];
    for (final rune in value.runes) {
      final byte = _windows1251Byte(rune);
      if (byte == null) return value;
      bytes.add(byte);
    }

    try {
      final repaired = utf8.decode(bytes);
      return _mojibakeScore(repaired) < sourceScore ? repaired : value;
    } on FormatException {
      return value;
    }
  }

  static int _mojibakeScore(String value) {
    var score = 0;
    for (final rune in value.runes) {
      if (rune >= 0x80 && rune <= 0x9f) score += 3;
      if (_windows1251SpecialRunes.contains(rune)) score += 2;
    }
    score += RegExp(r'[РС][\u0080-\u00ffА-Яа-яЁёІіЇїЄєҐґ]')
        .allMatches(value)
        .length;
    return score;
  }

  static int? _windows1251Byte(int rune) {
    if (rune <= 0x7f || (rune >= 0x80 && rune <= 0x9f)) return rune;
    if (rune >= 0x0410 && rune <= 0x044f) return rune - 0x0410 + 0xc0;
    return _windows1251SpecialBytes[rune];
  }

  static const Map<int, int> _windows1251SpecialBytes = {
    0x0402: 0x80,
    0x0403: 0x81,
    0x201a: 0x82,
    0x0453: 0x83,
    0x201e: 0x84,
    0x2026: 0x85,
    0x2020: 0x86,
    0x2021: 0x87,
    0x20ac: 0x88,
    0x2030: 0x89,
    0x0409: 0x8a,
    0x2039: 0x8b,
    0x040a: 0x8c,
    0x040c: 0x8d,
    0x040b: 0x8e,
    0x040f: 0x8f,
    0x0452: 0x90,
    0x2018: 0x91,
    0x2019: 0x92,
    0x201c: 0x93,
    0x201d: 0x94,
    0x2022: 0x95,
    0x2013: 0x96,
    0x2014: 0x97,
    0x2122: 0x99,
    0x0459: 0x9a,
    0x203a: 0x9b,
    0x045a: 0x9c,
    0x045c: 0x9d,
    0x045b: 0x9e,
    0x045f: 0x9f,
    0x00a0: 0xa0,
    0x040e: 0xa1,
    0x045e: 0xa2,
    0x0408: 0xa3,
    0x00a4: 0xa4,
    0x0490: 0xa5,
    0x00a6: 0xa6,
    0x00a7: 0xa7,
    0x0401: 0xa8,
    0x00a9: 0xa9,
    0x0404: 0xaa,
    0x00ab: 0xab,
    0x00ac: 0xac,
    0x00ad: 0xad,
    0x00ae: 0xae,
    0x0407: 0xaf,
    0x00b0: 0xb0,
    0x00b1: 0xb1,
    0x0406: 0xb2,
    0x0456: 0xb3,
    0x0491: 0xb4,
    0x00b5: 0xb5,
    0x00b6: 0xb6,
    0x00b7: 0xb7,
    0x0451: 0xb8,
    0x2116: 0xb9,
    0x0454: 0xba,
    0x00bb: 0xbb,
    0x0458: 0xbc,
    0x0405: 0xbd,
    0x0455: 0xbe,
    0x0457: 0xbf,
  };

  static const Set<int> _windows1251SpecialRunes = {
    0x0402,
    0x0403,
    0x0453,
    0x0409,
    0x040a,
    0x040c,
    0x040b,
    0x040f,
    0x0452,
    0x0459,
    0x045a,
    0x045c,
    0x045b,
    0x045f,
    0x040e,
    0x045e,
    0x0408,
    0x0490,
    0x0401,
    0x0404,
    0x0407,
    0x0406,
    0x0456,
    0x0491,
    0x0451,
    0x2116,
    0x0454,
    0x0458,
    0x0405,
    0x0455,
    0x0457,
  };
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

  final StreamController<void> _releaseSignals =
      StreamController<void>.broadcast();

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
    final cacheIsFresh =
        DateTime.now().millisecondsSinceEpoch - lastCheck <
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
    if (build != 4236 && build != 4237 && build != 4238) return null;
    final isGroupCallFix = build == 4237 || build == 4238;
    final isSerializedGroupCallFix = build == 4238;
    return AppRelease(
      platform: platform,
      version: version,
      build: build,
      minimumSupportedBuild: 0,
      downloadUrl: Uri.parse(
        platform == 'windows'
            ? 'https://fenyvo.com/download/Fenyvo-${isGroupCallFix ? '1.8.2' : '1.8.1'}-windows-x64.zip'
            : 'https://fenyvo.com/download/Fenyvo-${isGroupCallFix ? '1.8.2' : '1.8.1'}-arm64.apk',
      ),
      publishedAt: isSerializedGroupCallFix
          ? DateTime.utc(2026, 10, 17)
          : isGroupCallFix
          ? DateTime.utc(2026, 10, 15)
          : DateTime.utc(2026, 10, 12),
      notes: isSerializedGroupCallFix
          ? const {
              'ru': [
                'Состояния группового звонка теперь обрабатываются последовательно.',
                'Старое соединение полностью освобождается перед созданием нового.',
                'Исправлен вылет при одобрении запроса участника ведущим.',
              ],
              'uk': [
                'Стани групового дзвінка тепер обробляються послідовно.',
                'Старе з’єднання повністю звільняється перед створенням нового.',
                'Виправлено виліт після схвалення запиту учасника ведучим.',
              ],
              'en': [
                'Group-call state updates are now processed sequentially.',
                'The old peer is fully released before its replacement is created.',
                'Fixed a crash after the host approves a participant request.',
              ],
            }
          : isGroupCallFix
          ? const {
              'ru': [
                'Участники стабильнее подключаются к групповому звонку.',
                'Устаревшее состояние больше не выкидывает ведущего или участника.',
                'Ранние сигналы соединения не теряются во время одновременного входа.',
                'Групповые звонки используют защищённый TURN-сервер Fenyvo.',
              ],
              'uk': [
                'Учасники стабільніше підключаються до групового дзвінка.',
                'Застарілий стан більше не викидає ведучого або учасника.',
                'Ранні сигнали з’єднання не губляться під час одночасного входу.',
                'Групові дзвінки використовують захищений TURN-сервер Fenyvo.',
              ],
              'en': [
                'Participants now join group calls more reliably.',
                'Stale state no longer removes a host or participant.',
                'Early connection signals survive simultaneous joins.',
                'Group calls now use the authenticated Fenyvo TURN service.',
              ],
            }
          : const {
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
        queryParameters: {
          't': DateTime.now().millisecondsSinceEpoch.toString(),
        },
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
