import 'dart:convert';
import 'dart:io';

import '../../backup/backup_encryptor.dart';
import '../checkup_scanner.dart';
import '../secret_detector.dart';

/// 本机备份文件扫描器（PR-5）。
///
/// 检查「导出到本机」的备份文件：
/// - 明文备份（v1，无 `format` 信封）含 apiKey / apiKeys / serviceAccount / password → 🟡；
/// - JWE 加密备份（v2 信封）→ 安全，不报；
/// - 脱敏备份（v2 但 crypto=null）→ 安全，不报。
///
/// 这是「体检前/后」对比的关键输入：迁移前若用户手头有明文备份，体检应提示其作废。
class BackupFileScanner extends CheckupScanner {
  BackupFileScanner(this._backupFiles);
  final Future<List<File>> _backupFiles;

  @override
  String get id => 'backup_file';

  @override
  String get title => '本机备份文件';

  @override
  CheckupSeverity get severity => CheckupSeverity.warn;

  @override
  Future<List<CheckupFinding>> scan(CheckupStrings strings) async {
    final files = await _backupFiles;
    final plaintext = <String>[];

    for (final f in files) {
      if (!await f.exists()) continue;
      final content = await _safeRead(f);
      if (content == null) continue;
      if (_isEnvelope(content)) continue; // v2 加密/脱敏，安全
      if (_containsPlaintextKeys(content)) plaintext.add(f.path.split(RegExp(r'[/\\]')).last);
    }

    if (plaintext.isEmpty) return const [];
    return [
      CheckupFinding(
        id: '$id:plaintext',
        scannerId: id,
        title: strings.backupPlaintextTitle(plaintext.length),
        detail: strings.backupPlaintextDetail(plaintext),
        severity: CheckupSeverity.warn,
        autoFixable: false,
      )
    ];
  }

  static bool _isEnvelope(String content) {
    try {
      final m = jsonDecode(content);
      if (m is! Map) return false;
      final fmt = m['format'];
      return (fmt == BackupEncryptor.format || fmt == BackupEncryptor.legacyFormat) &&
          m['version'] == BackupEncryptor.version;
    } catch (_) {
      return false;
    }
  }

  /// 明文 v1 备份是否含凭证字段（apiKey / apiKeys / serviceAccount / password 等）。
  ///
  /// 递归查找：旧明文备份的凭证字段往往嵌套在 `provider_configs_v1` / `apiKeys` 之下，
  /// 不能只看顶层；命中字段名即判为明文。非 JSON 时退化为模式探测兜底。
  static bool _containsPlaintextKeys(String content) {
    const fields = {
      'apiKey',
      'apiKeys',
      'serviceAccountJson',
      'serviceAccount',
      'password',
      'proxyPassword',
      'globalProxyPassword',
    };
    try {
      final m = jsonDecode(content);
      if (m is Map && _containsCredentialKey(m, fields)) return true;
    } catch (_) {
      // 非 JSON：退化为模式探测
    }
    return SecretDetector.detect(content) != null;
  }

  static bool _containsCredentialKey(dynamic node, Set<String> fields) {
    if (node is Map) {
      for (final k in node.keys) {
        if (fields.contains(k)) return true;
        if (_containsCredentialKey(node[k], fields)) return true;
      }
    } else if (node is List) {
      for (final e in node) {
        if (_containsCredentialKey(e, fields)) return true;
      }
    }
    return false;
  }

  static Future<String?> _safeRead(File f) async {
    try {
      return await f.readAsString();
    } catch (_) {
      return null;
    }
  }
}
