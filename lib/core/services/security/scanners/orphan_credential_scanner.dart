import '../checkup_scanner.dart';
import '../../secure_storage/credential_keys.dart';
import '../../secure_storage/secure_storage_service.dart';

/// 孤儿凭证扫描器（PR-5）。
///
/// 安全存储里可能存在「已无对应配置的凭证条目」：
/// - 用户删了某个 provider / 搜索服务，但迁移 / 删除时漏清它的凭证；
/// - 迁移中途异常留下的残留。
///
/// 这类孤儿既不随配置展示，也无从使用，却长期躺在安全存储里——
/// 体检发现后应支持一键删除（安全可逆，[autoFix] 开放）。
class OrphanCredentialScanner extends CheckupScanner {
  OrphanCredentialScanner(
    this._secure, {
    required this.knownProviderIds,
    required this.knownServiceIds,
  });

  final SecureStorageService _secure;

  /// 当前仍存在的 provider id 集合。
  final Set<String> knownProviderIds;

  /// 当前仍存在的扁平服务 id 集合（搜索 / TTS 等）。
  final Set<String> knownServiceIds;

  @override
  String get id => 'orphan_credential';

  @override
  String get title => '孤儿凭证';

  @override
  CheckupSeverity get severity => CheckupSeverity.warn;

  @override
  Future<List<CheckupFinding>> scan(CheckupStrings strings) async {
    final all = await _secure.readAll();
    final orphans = <String>[];

    for (final key in all.keys) {
      final pid = CredentialKeys.tryParseProviderId(key);
      if (pid != null) {
        if (!knownProviderIds.contains(pid)) orphans.add(key);
        continue;
      }
      final sid = CredentialKeys.tryParseServiceId(key);
      if (sid != null) {
        if (!knownServiceIds.contains(sid)) orphans.add(key);
        continue;
      }
    }

    if (orphans.isEmpty) return const [];
    return [
      CheckupFinding(
        id: '$id:found',
        scannerId: id,
        title: strings.orphanTitle(orphans.length),
        detail: strings.orphanDetail(),
        severity: CheckupSeverity.warn,
        autoFixable: true,
        fixHint: strings.orphanFixHint(),
      )
    ];
  }

  @override
  Future<bool> autoFix(CheckupFinding finding) async {
    if (finding.id != '$id:found') return false;
    final all = await _secure.readAll();
    var removed = 0;
    for (final key in all.keys) {
      final pid = CredentialKeys.tryParseProviderId(key);
      if (pid != null && !knownProviderIds.contains(pid)) {
        await _secure.delete(key);
        removed++;
        continue;
      }
      final sid = CredentialKeys.tryParseServiceId(key);
      if (sid != null && !knownServiceIds.contains(sid)) {
        await _secure.delete(key);
        removed++;
      }
    }
    return removed > 0;
  }
}
