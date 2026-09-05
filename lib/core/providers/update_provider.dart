import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// App 发布仓库（GitHub Releases API 来源）
const String _repoOwner = 'Lisir2002';
const String _repoName = 'Me-Bot';
const String _ghApi = 'https://api.github.com/repos/$_repoOwner/$_repoName/releases';

class UpdateInfo {
  final String app;
  final String version;
  final int? build;
  final DateTime? releasedAt;
  final String? notes;
  final bool mandatory;
  final Map<String, String> downloads;

  const UpdateInfo({
    required this.app,
    required this.version,
    this.build,
    this.releasedAt,
    this.notes,
    this.mandatory = false,
    this.downloads = const {},
  });

  String? bestDownloadUrl() {
    if (Platform.isIOS) return downloads['ios'] ?? downloads['iosAppStore'] ?? downloads['universal'];
    if (Platform.isAndroid) {
      // CI 按 ABI 拆分产物，优先匹配最常见的 arm64
      for (final key in const ['android-arm64', 'android', 'android-armv7', 'android-x86_64', 'universal']) {
        if (downloads[key] != null && downloads[key]!.isNotEmpty) return downloads[key];
      }
      return null;
    }
    if (Platform.isMacOS) return downloads['macos'] ?? downloads['mac'] ?? downloads['darwin'] ?? downloads['universal'];
    if (Platform.isWindows) return downloads['windows'] ?? downloads['win'] ?? downloads['universal'];
    if (Platform.isLinux) return downloads['linux'] ?? downloads['universal'];
    return downloads['universal'] ?? downloads['android'] ?? downloads['ios'];
  }

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    final latest = (json['latest'] as Map?) ?? const {};
    final downloads = (latest['downloads'] as Map?)?.map((k, v) => MapEntry(k.toString(), v.toString())) ?? const {};
    DateTime? released;
    final releasedRaw = latest['releasedAt']?.toString();
    if (releasedRaw != null && releasedRaw.isNotEmpty) {
      try { released = DateTime.parse(releasedRaw); } catch (_) {}
    }
    return UpdateInfo(
      app: (json['app'] ?? '').toString(),
      version: (latest['version'] ?? '').toString(),
      build: int.tryParse((latest['build'] ?? '').toString()),
      releasedAt: released,
      notes: (latest['notes'] ?? '').toString(),
      mandatory: (latest['mandatory'] as bool?) ?? false,
      downloads: downloads,
    );
  }

  /// 从 GitHub Releases API 的 JSON response 解析
  factory UpdateInfo.fromGhRelease(Map<String, dynamic> release) {
    final tag = (release['tag_name'] as String? ?? '').replaceAll(RegExp(r'^v'), ''); // strip leading v
    final name = (release['name'] as String?) ?? tag;
    final body = (release['body'] as String?) ?? '';
    final publishedAt = release['published_at'] as String?;

    // 从 assets 里按文件名推断平台
    final downloads = <String, String>{};
    final assets = (release['assets'] as List?) ?? const [];
    for (final asset in assets) {
      if (asset is! Map<String, dynamic>) continue;
      final fileName = (asset['name'] as String? ?? '').toLowerCase();
      final url = asset['browser_download_url'] as String? ?? '';
      if (url.isEmpty) continue;

      if (fileName.endsWith('.apk')) {
        if (fileName.contains('arm64')) downloads['android-arm64'] = url;
        else if (fileName.contains('armv7')) downloads['android-armv7'] = url;
        else if (fileName.contains('x86_64')) downloads['android-x86_64'] = url;
        else downloads['android'] = url; // universal / fat apk
      } else if (fileName.endsWith('.aab')) {
        downloads['android-aab'] = url;
      } else if (fileName.endsWith('.dmg')) {
        downloads['macos'] = url;
      } else if (fileName.endsWith('.app')) {
        downloads['macos-app'] = url;
      } else if (fileName.endsWith('.exe') || fileName.endsWith('.msi')) {
        downloads['windows'] = url;
      } else if (fileName.endsWith('.deb') || fileName.endsWith('.rpm') || fileName.endsWith('.AppImage') || fileName.endsWith('.tar.gz')) {
        downloads['linux'] = url;
      } else if (fileName.endsWith('.ipa')) {
        downloads['ios'] = url;
      }
    }

    DateTime? released;
    if (publishedAt != null) {
      try { released = DateTime.parse(publishedAt); } catch (_) {}
    }

    return UpdateInfo(
      app: 'MiniMe-Core',
      version: tag.isNotEmpty ? tag : name,
      releasedAt: released,
      notes: body,
      mandatory: false,
      downloads: downloads,
    );
  }
}

class UpdateProvider extends ChangeNotifier {
  UpdateInfo? _available;
  UpdateInfo? get available => _available;
  bool _checking = false;
  bool get checking => _checking;
  String? _error;
  String? get error => _error;

  Future<void> checkForUpdates() async {
    if (_checking) return;
    _checking = true;
    _error = null;
    notifyListeners();
    try {
      final info = await _fetchLatestRelease();

      final pkg = await PackageInfo.fromPlatform();
      final currentVer = pkg.version; // e.g., 1.0.0

      final hasNew = _isRemoteNewer(remoteVersion: info.version, currentVersion: currentVer);
      _available = hasNew ? info : null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _checking = false;
      notifyListeners();
    }
  }

  /// 从 GitHub Releases API 拉取最新非 draft、非 prerelease 的版本
  Future<UpdateInfo> _fetchLatestRelease() async {
    // GitHub API: /repos/{owner}/{repo}/releases/latest
    final url = Uri.parse('$_ghApi/latest');
    final resp = await http.get(url, headers: {
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
      'User-Agent': 'MiniMe-Core',
    });

    if (resp.statusCode == 404) {
      // 没有 release —— 把 available 设 null 即可
      throw Exception('No release found');
    }
    if (resp.statusCode != 200) {
      throw Exception('GitHub API ${resp.statusCode}');
    }

    final data = jsonDecode(utf8.decode(resp.bodyBytes)) as Map<String, dynamic>;
    return UpdateInfo.fromGhRelease(data);
  }

  bool _isRemoteNewer({
    required String remoteVersion,
    required String currentVersion,
  }) {
    List<int> parseVer(String v) {
      final cleaned = v.replaceAll(RegExp(r'^[vV]'), '');
      final parts = cleaned.split('.');
      final nums = <int>[];
      for (int i = 0; i < 3; i++) {
        nums.add(i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0);
      }
      return nums;
    }
    final a = parseVer(remoteVersion);
    final b = parseVer(currentVersion);
    if (a[0] != b[0]) return a[0] > b[0];
    if (a[1] != b[1]) return a[1] > b[1];
    if (a[2] != b[2]) return a[2] > b[2];
    return false;
  }
}
