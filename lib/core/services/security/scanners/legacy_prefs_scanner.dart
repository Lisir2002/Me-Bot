import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../checkup_scanner.dart';
import '../secret_detector.dart';
import '../credential_audit_logger.dart';
import '../../logging/logger.dart';
import '../../logging/log_tags.dart';
import '../../secure_storage/credential_keys.dart';

// ════════════════════════════════════════════════════════════════════════════
// 分类约定（务必先读再改）：
//
// 【A. 仍在使用的配置 key —— 绝不能删】
// 下列 key 虽然以 `_v1` 结尾，但凭证字段已在 PR-2 / 凭证迁移 v1 阶段被剥离，
// 磁盘上只剩非敏感配置（供应商列表、搜索 / TTS 服务元数据、WebDAV 服务器地址等），
// 业务代码（SettingsProvider / tts_provider / 备份导入）仍持续读写。
//
// 历史 bug：本扫描器曾把 `provider_configs_v1` / `search_services_v1` /
// `tts_services_v1` 当成"旧明文残留"整体 remove，导致用户一键修复后
// 所有供应商 / 搜索 / TTS 配置全部丢失。`webdav_config_v1` 同理
// （迁移 v1 步骤 `_purgeLegacy` 明确注释"不能整个删除"）。
//
// 这些 key 现在统一迁移到 `_v2` 命名空间（见 SettingsProvider），
// 但迁移期间 v1 副本仍可能存在，因此 v1 / v2 都进白名单。
//
// 【B. 迁移后应删除的纯明文残留 —— 才允许一键删除】
// 凭证已被搬进安全存储、prefs 里这份明文副本不再有任何业务读取路径：
// 仅全局代理用户名 / 密码（迁移 v1 `_purgeLegacy` 本就负责删除它们，
// 这里是漏删兜底）。
// ════════════════════════════════════════════════════════════════════════════

/// 【B 类】真正可被一键删除的旧明文 key。
const List<String> _legacyKeyNames = [
  CredentialKeys.legacyGlobalProxyUsername,
  CredentialKeys.legacyGlobalProxyPassword,
];

/// 【A 类】仍在使用的配置 key 白名单。
///
/// autoFix 删除前会做白名单校验：命中即拒绝删除并记 error 审计。
/// 这是双保险——即使未来有人误把 active key 加回 [_legacyKeyNames]，
/// 也不会再发生"一键修复误删配置"的数据丢失。
const Set<String> _activeKeysWhitelist = {
  'provider_configs_v1',
  'provider_configs_v2',
  'search_services_v1',
  'search_services_v2',
  'tts_services_v1',
  'tts_services_v2',
  'webdav_config_v1',
  'mcp_servers_v1',
};

/// 遗留明文 SharedPreferences 扫描器（PR-5）。
///
/// 检测两类问题：
/// 1. 🔴 迁移后本应删除的旧明文 key（[CredentialKeys] 的 legacy_* 常量）仍然存在——
///    说明一次性迁移漏删，明文 Key 仍躺在 SharedPreferences 里；
/// 2. 🟡 任意 SharedPreferences 值里出现疑似明文 Key 模式（[SecretDetector]）。
///
/// 注：PR-2 之后配置 JSON 已剥离凭证字段，正常配置值不会命中；若命中说明有残留或迁移异常。
class LegacyPrefsScanner extends CheckupScanner {
  LegacyPrefsScanner(this._prefs, {List<String>? deletableKeys})
      : _deletableKeys = deletableKeys ?? _legacyKeyNames;
  final SharedPreferences _prefs;

  /// 本次扫描 / 修复认定为"可删残留"的 key。生产用 [_legacyKeyNames]；
  /// 测试可注入自定义列表，用于验证白名单拦截（P2-3）。
  final List<String> _deletableKeys;

  @override
  String get id => 'legacy_prefs';

  @override
  String get title => '遗留明文配置';

  @override
  CheckupSeverity get severity => CheckupSeverity.danger;

  @override
  Future<List<CheckupFinding>> scan(CheckupStrings strings) async {
    final findings = <CheckupFinding>[];
    final keys = _prefs.getKeys();

    // 1) 旧明文 key 残留（高危）
    final legacyPresent = <String>[];
    for (final legacy in _deletableKeys) {
      if (keys.contains(legacy)) legacyPresent.add(legacy);
    }
    if (legacyPresent.isNotEmpty) {
      findings.add(CheckupFinding(
        id: '$id:legacy_keys',
        scannerId: id,
        title: strings.legacyKeysTitle(),
        detail: strings.legacyKeysDetail(legacyPresent.length, legacyPresent),
        severity: CheckupSeverity.danger,
        autoFixable: true,
        fixHint: strings.legacyKeysFixHint(),
      ));
    }

    // 2) 值里的明文 Key 模式（存疑）
    var suspectCount = 0;
    for (final key in keys) {
      final raw = _prefs.get(key);
      if (raw is! String) continue;
      if (SecretDetector.detect(raw) != null) suspectCount++;
    }
    if (suspectCount > 0) {
      findings.add(CheckupFinding(
        id: '$id:plaintext_values',
        scannerId: id,
        title: strings.legacyPlaintextTitle(),
        detail: strings.legacyPlaintextDetail(suspectCount),
        severity: CheckupSeverity.warn,
        autoFixable: false,
      ));
    }

    return findings;
  }

  @override
  Future<bool> autoFix(CheckupFinding finding) async {
    if (finding.id != '$id:legacy_keys') return false;

    // P2-1：删除前先把待删 key 的当前值备份成 JSON 文件，失败不阻断修复。
    await _backupBeforeDeleting(_deletableKeys);

    var removed = 0;
    var blocked = 0;
    for (final legacy in _deletableKeys) {
      if (!_prefs.containsKey(legacy)) continue;

      // P2-3：白名单双保险——active key 一律拒绝删除。
      if (_activeKeysWhitelist.contains(legacy)) {
        blocked++;
        CredentialAuditLogger.record(
          'autoFixBlocked',
          'prefs:$legacy',
          ok: false,
          detail: 'key in active whitelist, refused to delete',
        );
        continue;
      }

      await _prefs.remove(legacy);
      removed++;

      // P2-4：逐条审计删除动作（不携带值）。
      CredentialAuditLogger.record(
        'autoFixDelete',
        'prefs:$legacy',
        detail: 'removed by legacy_prefs scanner',
      );
    }

    CredentialAuditLogger.record(
      'autoFixComplete',
      'legacy_prefs',
      detail: 'removed $removed keys (blocked $blocked)',
    );
    return removed > 0;
  }

  /// P2-1：把即将删除的 prefs key 当前值备份到
  /// `<文档目录>/security_backups/autofix_<timestamp>.json`，便于误删后人工恢复。
  ///
  /// 备份内容不含新数据，仅本次会被删除的 key 的旧值；任何异常都不阻断修复。
  Future<void> _backupBeforeDeleting(List<String> keys) async {
    try {
      final toDelete = <String, dynamic>{};
      for (final k in keys) {
        if (_prefs.containsKey(k)) toDelete[k] = _prefs.get(k);
      }
      if (toDelete.isEmpty) return;

      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/security_backups');
      if (!await dir.exists()) await dir.create(recursive: true);
      final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
      final file = File('${dir.path}/autofix_$ts.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert({
        'timestamp': DateTime.now().toIso8601String(),
        'deleted_keys': toDelete,
      }));
      Logger.i(LogTags.security, 'legacy autofix backup -> ${file.path}');
    } catch (e, st) {
      // 备份失败不阻断修复，仅记 warn 便于事后排查。
      Logger.w(LogTags.security, 'legacy autofix backup failed: $e', e, st);
    }
  }
}
