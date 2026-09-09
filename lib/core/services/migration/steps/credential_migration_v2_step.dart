import 'dart:convert';

import '../../../models/service_credentials.dart';
import '../../secure_storage/credential_keys.dart';
import '../migration_context.dart';
import '../migration_step.dart';

/// v2：把搜索 / TTS 服务配置里明文的 API Key 搬进安全存储。
///
/// 与 v1 的差异：
/// - v1 处理 provider / 全局代理 / WebDAV；
/// - v2 处理 `search_services_v1`、`tts_services_v1` 两个数组。
///
/// 这些配置是扁平 JSON（`{'id':..,'apiKey':..}`），凭证按
/// [ServiceCredentials.sensitiveKeys] 的字段名规则识别，
/// 因此新增服务商无需改迁移代码。
///
/// 语义与备份恢复不同：迁移遵循「**本地已有值优先**」——
/// 安全存储里已有非空凭证时跳过，不用旧明文覆盖较新的值。
class CredentialMigrationV2Step extends MigrationStep {
  CredentialMigrationV2Step();

  @override
  String get id => 'credential_v2';

  @override
  int get version => 2;

  /// 与 v1 一致：除首次迁移外，也要防旧备份恢复导致的明文回流。
  @override
  Future<bool> shouldRun(MigrationContext ctx) async {
    if (!ctx.isDone(id)) return true;
    return _hasLegacyPlaintext(ctx);
  }

  bool _hasLegacyPlaintext(MigrationContext ctx) {
    for (final key in <String>[
      CredentialKeys.legacySearchServices,
      CredentialKeys.legacyTtsServices,
    ]) {
      final raw = ctx.prefs.getString(key);
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! List) continue;
        for (final item in decoded) {
          if (item is! Map) continue;
          if (ServiceCredentials.extract(Map<String, dynamic>.from(item))
              .isNotEmpty) {
            return true;
          }
        }
      } catch (_) {}
    }
    return false;
  }

  @override
  Future<void> run(MigrationContext ctx) async {
    await _migrateServices(ctx, CredentialKeys.legacySearchServices);
    await _migrateServices(ctx, CredentialKeys.legacyTtsServices);
  }

  Future<void> _migrateServices(MigrationContext ctx, String key) async {
    final raw = ctx.prefs.getString(key);
    if (raw == null || raw.isEmpty) return;

    final dynamic decoded = _tryDecode(raw);
    if (decoded is! List) return;

    final cleaned = <dynamic>[];
    var changed = false;

    for (final item in decoded) {
      if (item is! Map) {
        cleaned.add(item);
        continue;
      }
      final json = Map<String, dynamic>.from(item);
      final secrets = ServiceCredentials.extract(json);
      final id = json['id']?.toString();
      if (secrets.isEmpty || id == null || id.isEmpty) {
        cleaned.add(json);
        continue;
      }

      final storageKey = CredentialKeys.service(id);
      final existing = await ctx.secureStorage.readCredential(storageKey);
      // 断点续跑 / 本地值优先：已有非空凭证就不回写旧明文
      if (existing == null ||
          ServiceCredentials.fromRecord(existing).isEmpty) {
        await ctx.secureStorage.writeCredential(
          storageKey,
          ServiceCredentials.toRecord(id, secrets),
        );
      }
      cleaned.add(ServiceCredentials.strip(json));
      changed = true;
    }

    if (changed) {
      await ctx.prefs.setString(key, jsonEncode(cleaned));
    }
  }

  /// 解析 legacy JSON；损坏时返回 null 而不是抛 [FormatException]。
  ///
  /// `search_services_v1` / `tts_services_v1` 的内容同样可能来自旧版本或
  /// 半截的备份恢复，格式不合法是预期内输入；迁移跑在启动路径上，
  /// 抛出会打断后续步骤，所以吞掉并保持原值，交给下次启动重试。
  static dynamic _tryDecode(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }
}
