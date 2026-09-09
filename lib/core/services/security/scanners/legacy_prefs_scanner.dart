import 'package:shared_preferences/shared_preferences.dart';

import '../checkup_scanner.dart';
import '../secret_detector.dart';
import '../../secure_storage/credential_keys.dart';

/// 旧明文 key 名称清单（单一事实来源来自 [CredentialKeys] 的 legacy_* 常量）。
const List<String> _legacyKeyNames = [
  CredentialKeys.legacyProviderConfigs,
  CredentialKeys.legacyGlobalProxyUsername,
  CredentialKeys.legacyGlobalProxyPassword,
  CredentialKeys.legacyWebDavConfig,
  CredentialKeys.legacySearchServices,
  CredentialKeys.legacyTtsServices,
];

/// 遗留明文 SharedPreferences 扫描器（PR-5）。
///
/// 检测两类问题：
/// 1. 🔴 迁移后本应删除的旧明文 key（[CredentialKeys] 的 legacy_* 常量）仍然存在——
///    说明一次性迁移漏删，明文 Key 仍躺在 SharedPreferences 里；
/// 2. 🟡 任意 SharedPreferences 值里出现疑似明文 Key 模式（[SecretDetector]）。
///
/// 注：PR-2 之后配置 JSON 已剥离凭证字段，正常配置值不会命中；若命中说明有残留或迁移异常。
class LegacyPrefsScanner extends CheckupScanner {
  LegacyPrefsScanner(this._prefs);
  final SharedPreferences _prefs;

  @override
  String get id => 'legacy_prefs';

  @override
  String get title => '遗留明文配置';

  @override
  CheckupSeverity get severity => CheckupSeverity.danger;

  @override
  Future<List<CheckupFinding>> scan() async {
    final findings = <CheckupFinding>[];
    final keys = _prefs.getKeys();

    // 1) 旧明文 key 残留（高危）
    final legacyPresent = <String>[];
    for (final legacy in _legacyKeyNames) {
      if (keys.contains(legacy)) legacyPresent.add(legacy);
    }
    if (legacyPresent.isNotEmpty) {
      findings.add(CheckupFinding(
        id: '$id:legacy_keys',
        scannerId: id,
        title: '发现未清理的旧明文凭证 Key',
        detail: '${legacyPresent.length} 个旧 key 仍存在于本地配置：'
            '${legacyPresent.join('、')}（应为空）',
        severity: CheckupSeverity.danger,
        autoFixable: true,
        fixHint: '重新执行孤儿清理',
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
        title: '本地配置中存在疑似明文 Key',
        detail: '在 $suspectCount 个配置项中发现疑似明文 Key 模式，建议核查是否为迁移遗漏',
        severity: CheckupSeverity.warn,
        autoFixable: false,
      ));
    }

    return findings;
  }

  @override
  Future<bool> autoFix(CheckupFinding finding) async {
    if (finding.id != '$id:legacy_keys') return false;
    var removed = 0;
    for (final legacy in _legacyKeyNames) {
      if (_prefs.containsKey(legacy)) {
        await _prefs.remove(legacy);
        removed++;
      }
    }
    return removed > 0;
  }
}
