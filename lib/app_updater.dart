import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

const _gold = Color(0xFFF3CF3C);
const _releaseApi = 'https://api.github.com/repos/trademonarchcodes/monarch-codex-android/releases/tags/latest-apk';

class AppUpdaterPage extends StatefulWidget {
  const AppUpdaterPage({super.key});

  @override
  State<AppUpdaterPage> createState() => _AppUpdaterPageState();
}

class _AppUpdaterPageState extends State<AppUpdaterPage> {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 60),
    headers: const {'Accept': 'application/vnd.github+json'},
  ));
  bool _checking = false;
  bool _downloading = false;
  double _progress = 0;
  String _status = 'Check whether a newer Monarch Codex version is available.';
  String? _error;
  String? _latestVersion;
  String? _apkUrl;
  String? _checksumUrl;
  String? _releaseNotes;
  bool _mandatoryUpdate = false;

  @override
  void initState() {
    super.initState();
    checkForUpdates();
  }

  List<int> _versionParts(String value) {
    final pieces = value.split('+');
    final version = (pieces.isNotEmpty ? pieces.first : value).split('.');
    final parts = version.map((p) => int.tryParse(p) ?? 0).toList();
    parts.add(int.tryParse(pieces.length > 1 ? pieces[1] : '0') ?? 0);
    while (parts.length < 4) {
      parts.insert(parts.length - 1, 0);
    }
    return parts;
  }

  bool _isNewer(String candidate, String installed) {
    final a = _versionParts(candidate);
    final b = _versionParts(installed);
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  Future<void> checkForUpdates() async {
    if (_checking || _downloading) return;
    setState(() {
      _checking = true;
      _error = null;
      _status = 'Checking the official Monarch Codex release…';
    });
    try {
      final info = await PackageInfo.fromPlatform();
      final response = await _dio.get<dynamic>(_releaseApi);
      if (response.data is! Map) throw Exception('The release information is not valid.');
      final release = Map<String, dynamic>.from(response.data as Map);
      final body = (release['body'] ?? '').toString();
      final match = RegExp(r'Version:\s*([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+)', caseSensitive: false).firstMatch(body);
      if (match == null) throw Exception('The release has no version information yet. Please try again later.');
      final version = match.group(1)!;
      final mandatoryMatch = RegExp(r'Mandatory:\\s*(true|yes|1)', caseSensitive: false).firstMatch(body);
      final mandatory = mandatoryMatch != null;
      final assets = (release['assets'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      Map<String, dynamic>? apk;
      Map<String, dynamic>? checksum;
      for (final asset in assets) {
        if (asset['name'] == 'app-release.apk') apk = asset;
        if (asset['name'] == 'app-release.apk.sha256') checksum = asset;
      }
      if (apk == null || checksum == null) {
        throw Exception('The official APK or its checksum is not published yet.');
      }
      if (!mounted) return;
      setState(() {
        _latestVersion = version;
        _apkUrl = apk!['browser_download_url']?.toString();
        _checksumUrl = checksum!['browser_download_url']?.toString();
        _mandatoryUpdate = mandatory;
        _releaseNotes = body.replaceFirst(match.group(0)!, '').replaceFirst(RegExp(r'Mandatory:\\s*(true|yes|1)', caseSensitive: false), '').trim();
        final newer = _isNewer(version, '${info.version}+${info.buildNumber}');
        _status = newer
            ? 'Version $version is available.${mandatory ? ' This release is marked mandatory; install it as soon as possible.' : ''}'
            : 'You are using the latest version (${info.version}+${info.buildNumber}).';
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e is DioException
              ? 'Could not reach the official update service. Check your internet and try again.'
              : e.toString().replaceFirst('Exception: ', '');
          _status = 'Update check could not be completed.';
        });
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> downloadAndInstall() async {
    final apkUrl = _apkUrl;
    final checksumUrl = _checksumUrl;
    final version = _latestVersion;
    if (apkUrl == null || checksumUrl == null || version == null || _downloading) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
      _status = 'Downloading version $version…';
    });
    try {
      final directory = await getTemporaryDirectory();
      final apkFile = File('${directory.path}/monarch-codex-update.apk');
      final checksumResponse = await _dio.get<String>(
        checksumUrl,
        options: Options(responseType: ResponseType.plain),
      );
      final expected = (checksumResponse.data ?? '').trim().split(RegExp(r'\s+')).first.toLowerCase();
      if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expected)) {
        throw Exception('The official APK checksum is invalid. Installation was stopped.');
      }
      await _dio.download(
        apkUrl,
        apkFile.path,
        deleteOnError: true,
        onReceiveProgress: (received, total) {
          if (mounted && total > 0) setState(() => _progress = received / total);
        },
      );
      final digest = sha256.convert(await apkFile.readAsBytes()).toString();
      if (digest != expected) {
        await apkFile.delete().catchError((_) => apkFile);
        throw Exception('The downloaded APK failed its security check. It was not opened.');
      }
      if (!mounted) return;
      setState(() => _status = 'Download verified. Opening Android installer…');
      final result = await OpenFilex.open(apkFile.path, type: 'application/vnd.android.package-archive');
      if (result.type != ResultType.done && mounted) {
        setState(() => _error = 'Android could not open the installer. You can download the APK from monarchcodex.online instead.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e is DioException
          ? 'Download failed. Check your connection and try again.'
          : e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUpdate = _latestVersion != null && _apkUrl != null && _checksumUrl != null &&
        _status.startsWith('Version ');
    return Scaffold(
      appBar: AppBar(title: const Text('App updates')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Icon(Icons.system_update_alt_rounded, color: _gold, size: 58),
          const SizedBox(height: 16),
          const Text('MONARCH CODEX UPDATER',
              textAlign: TextAlign.center,
              style: TextStyle(color: _gold, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_status, style: const TextStyle(fontWeight: FontWeight.w800)),
                if (_releaseNotes != null && _releaseNotes!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text('Release notes', style: TextStyle(color: _gold, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(_releaseNotes!),
                ],
                if (_downloading) ...[
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: _progress > 0 ? _progress : null, color: _gold),
                  const SizedBox(height: 6),
                  Text(_progress > 0 ? '${(_progress * 100).round()}%' : 'Preparing download…'),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                ],
              ]),
            ),
          ),
          const SizedBox(height: 14),
          if (hasUpdate)
            FilledButton.icon(
              onPressed: _downloading ? null : downloadAndInstall,
              icon: const Icon(Icons.download_rounded),
              label: Text(_downloading ? 'Downloading…' : 'Download and install update'),
            ),
          OutlinedButton.icon(
            onPressed: _checking || _downloading ? null : checkForUpdates,
            icon: const Icon(Icons.refresh),
            label: const Text('Check again'),
          ),
          const SizedBox(height: 12),
          const Text(
            'Updates are downloaded from the official Monarch Codex release and checked against its SHA-256 checksum before the Android installer opens. Android may ask you to allow installation from Monarch Codex.',
            style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.5),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
