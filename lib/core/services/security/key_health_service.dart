import '../../models/provider_credentials.dart';
import '../secure_storage/credential_keys.dart';
import '../secure_storage/credential_record.dart';
import '../secure_storage/secure_storage_service.dart';

/// 单个 provider 的密钥健康快照（PR-7）。
///
/// 数据全部来自 [CredentialRecord.meta]（① 预留接口的数据结构）+ 实时统计，
/// 不读取任何明文值。状态徽章直接由这些字段推导。
class KeyHealthInfo {
  const KeyHealthInfo({
    required this.providerId,
    required this.keyCount,
    this.hasServiceAccount = false,
    this.createdAt,
    this.lastUsedAt,
    this.lastRotatedAt,
    this.needsRotation = false,
  });

  final String providerId;
  final int keyCount;
  final bool hasServiceAccount;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;
  final DateTime? lastRotatedAt;

  /// 距上次轮换是否超过阈值（未轮换过也视为需要）。
  final bool needsRotation;

  int? get daysSinceRotation {
    if (lastRotatedAt == null) return null;
    return DateTime.now().difference(lastRotatedAt!).inDays;
  }

  int? get daysSinceUsed {
    if (lastUsedAt == null) return null;
    return DateTime.now().difference(lastUsedAt!).inDays;
  }
}

/// 密钥健康服务（PR-7）。
///
/// 把密钥管理从「配置项」升级为「可观测能力」：扫描安全存储里每个 provider 的凭证，
/// 聚合出健康快照（Key 数量、最近使用、距上次轮换、是否需要轮换提醒）。
///
/// 与 ApiKeyManager 的「熔断/恢复」是两条互补信息：本服务看**密钥年龄**，
/// ApiKeyManager 看**实时可用性**。面板可二者并排展示。
class KeyHealthService {
  KeyHealthService(
    this._secure, {
    this.rotationThresholdDays = _defaultThresholdDays,
  });

  final SecureStorageService _secure;

  /// 距上次轮换超过该天数即提示「建议轮换」。
  final int rotationThresholdDays;

  static const int _defaultThresholdDays = 90;

  /// 扫描全部 provider 凭证，返回健康快照（按 providerId 排序）。
  Future<List<KeyHealthInfo>> scan() async {
    final all = await _secure.readAll();
    final infos = <KeyHealthInfo>[];

    for (final entry in all.entries) {
      final providerId = CredentialKeys.tryParseProviderId(entry.key);
      if (providerId == null) continue;

      final record = CredentialRecord.decode(entry.value);
      if (record == null) continue;
      final creds = ProviderCredentials.fromRecord(record);

      final keyCount = (creds.apiKey.isNotEmpty ? 1 : 0) +
          creds.apiKeys.length +
          (creds.serviceAccountJson != null &&
                  creds.serviceAccountJson!.isNotEmpty
              ? 1
              : 0);

      final needsRotation = _needsRotation(record.lastRotatedAt);

      infos.add(KeyHealthInfo(
        providerId: providerId,
        keyCount: keyCount,
        hasServiceAccount: creds.serviceAccountJson != null &&
            creds.serviceAccountJson!.isNotEmpty,
        createdAt: record.createdAt,
        lastUsedAt: record.lastUsedAt,
        lastRotatedAt: record.lastRotatedAt,
        needsRotation: needsRotation,
      ));
    }

    infos.sort((a, b) => a.providerId.compareTo(b.providerId));
    return infos;
  }

  bool _needsRotation(DateTime? lastRotatedAt) {
    if (lastRotatedAt == null) return true; // 从未轮换过
    return DateTime.now().difference(lastRotatedAt).inDays >=
        rotationThresholdDays;
  }

  /// 需要轮换提醒的 provider 数量（面板顶栏轻提示用）。
  Future<int> countNeedsRotation() async =>
      (await scan()).where((i) => i.needsRotation).length;
}
