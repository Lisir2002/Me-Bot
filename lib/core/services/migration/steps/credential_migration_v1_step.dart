import 'dart:convert';

import '../../../models/provider_credentials.dart';
import '../../secure_storage/credential_keys.dart';
import '../migration_context.dart';
import '../migration_step.dart';

/// v1：把散落在 SharedPreferences 里的明文凭证搬进安全存储，并清除明文。
///
/// 覆盖三类来源：
/// 1. `provider_configs_v1` —— apiKey / apiKeys[].key / serviceAccountJson / 代理口令
/// 2. `global_proxy_username_v1` / `global_proxy_password_v1`
/// 3. `webdav_config_v1` 里的 password
///
/// **两阶段**：
/// - A 阶段只「写入安全存储」，不动明文。任一步失败即整步失败，明文保留；
/// - B 阶段（A 全绿后才到）才清理明文。
///
/// 因此中断在任意位置都可以安全重跑：A 阶段重跑时若安全存储已有值则跳过覆盖，
/// B 阶段重跑时删除不存在的 key 是无害的空操作。
class CredentialMigrationV1Step extends MigrationStep {
  CredentialMigrationV1Step();

  @override
  String get id => 'credential_v1';

  @override
  int get version => 1;

  /// 除了首次迁移，还要防「明文回流」。
  ///
  /// 典型场景：用户从一份旧备份恢复（`data_sync` 会整体写回 SharedPreferences），
  /// 明文凭证又出现在磁盘上。此时完成标记已经在，但必须再清理一次，
  /// 否则 P0-01 的成果会被一次恢复操作抹掉。
  @override
  Future<bool> shouldRun(MigrationContext ctx) async {
    if (!ctx.isDone(id)) return true;
    return _hasLegacyPlaintext(ctx);
  }

  /// 检测 SharedPreferences 里是否仍残留明文凭证。
  bool _hasLegacyPlaintext(MigrationContext ctx) {
    final prefs = ctx.prefs;
    for (final key in <String>[
      CredentialKeys.legacyGlobalProxyUsername,
      CredentialKeys.legacyGlobalProxyPassword,
    ]) {
      final v = prefs.getString(key);
      if (v != null && v.isNotEmpty) return true;
    }

    final raw = prefs.getString(CredentialKeys.legacyProviderConfigs);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          for (final v in decoded.values) {
            if (v is! Map) continue;
            if (ProviderCredentials.fromConfigJson(Map<String, dynamic>.from(v))
                .isNotEmpty) {
              return true;
            }
          }
        }
      } catch (_) {
        // 解析不了就当作没有残留，交给 run() 里的容错处理
      }
    }

    final dav = prefs.getString(CredentialKeys.legacyWebDavConfig);
    if (dav != null && dav.isNotEmpty) {
      try {
        final decoded = jsonDecode(dav);
        if (decoded is Map &&
            ((decoded['password'] as String?) ?? '').isNotEmpty) {
          return true;
        }
      } catch (_) {}
    }
    return false;
  }

  @override
  Future<void> run(MigrationContext ctx) async {
    // ── A 阶段：明文 → 安全存储 ──
    await _migrateProviderConfigs(ctx);
    await _migrateGlobalProxy(ctx);
    await _migrateWebDav(ctx);

    // ── B 阶段：清理明文（拍板①：立即删除）──
    await _purgeLegacy(ctx);

    // 在安全存储里留一个审计锚点：PR-5 安全体检可用它判断「这台设备迁移过」。
    await ctx.secureStorage.write(CredentialKeys.migrationV1Done, '1');
  }

  // ------------------------------------------------------------ provider 配置

  Future<void> _migrateProviderConfigs(MigrationContext ctx) async {
    final raw = ctx.prefs.getString(CredentialKeys.legacyProviderConfigs);
    if (raw == null || raw.isEmpty) return;

    final dynamic decoded = jsonDecode(raw);
    if (decoded is! Map) return;

    final out = <String, dynamic>{};
    var changed = false;

    for (final entry in decoded.entries) {
      final id = entry.key.toString();
      final value = entry.value;
      if (value is! Map) {
        out[id] = value;
        continue;
      }
      final json = Map<String, dynamic>.from(value);
      final creds = ProviderCredentials.fromConfigJson(json);
      if (creds.isEmpty) {
        out[id] = json;
        continue;
      }

      final storageKey = CredentialKeys.provider(id);
      final existing = await ctx.secureStorage.readCredential(storageKey);
      // 断点续跑：安全存储里已有非空凭证则以它为准，不回写旧明文覆盖。
      if (existing == null ||
          ProviderCredentials.fromRecord(existing).isEmpty) {
        await ctx.secureStorage.writeCredential(storageKey, creds.toRecord(id));
      }
      out[id] = ProviderCredentials.stripCredentials(json);
      changed = true;
    }

    if (changed) {
      await ctx.prefs.setString(
        CredentialKeys.legacyProviderConfigs,
        jsonEncode(out),
      );
    }
  }

  // ---------------------------------------------------------------- 全局代理

  Future<void> _migrateGlobalProxy(MigrationContext ctx) async {
    await _moveString(
      ctx,
      legacyKey: CredentialKeys.legacyGlobalProxyUsername,
      secureKey: CredentialKeys.globalProxyUsername,
    );
    await _moveString(
      ctx,
      legacyKey: CredentialKeys.legacyGlobalProxyPassword,
      secureKey: CredentialKeys.globalProxyPassword,
    );
  }

  Future<void> _moveString(
    MigrationContext ctx, {
    required String legacyKey,
    required String secureKey,
  }) async {
    final value = ctx.prefs.getString(legacyKey);
    if (value == null || value.isEmpty) return;
    final existing = await ctx.secureStorage.read(secureKey);
    if (existing == null || existing.isEmpty) {
      await ctx.secureStorage.write(secureKey, value);
    }
  }

  // ------------------------------------------------------------------- WebDAV

  Future<void> _migrateWebDav(MigrationContext ctx) async {
    final raw = ctx.prefs.getString(CredentialKeys.legacyWebDavConfig);
    if (raw == null || raw.isEmpty) return;

    final dynamic decoded = jsonDecode(raw);
    if (decoded is! Map) return;

    final json = Map<String, dynamic>.from(decoded);
    final password = (json['password'] as String?) ?? '';
    if (password.isEmpty) return;

    final existing =
        await ctx.secureStorage.read(CredentialKeys.webDavPassword);
    if (existing == null || existing.isEmpty) {
      await ctx.secureStorage.write(CredentialKeys.webDavPassword, password);
    }
    json.remove('password');
    await ctx.prefs.setString(
      CredentialKeys.legacyWebDavConfig,
      jsonEncode(json),
    );
  }

  // ------------------------------------------------------------------ 清理明文

  Future<void> _purgeLegacy(MigrationContext ctx) async {
    await ctx.prefs.remove(CredentialKeys.legacyGlobalProxyUsername);
    await ctx.prefs.remove(CredentialKeys.legacyGlobalProxyPassword);
    // provider_configs_v1 / webdav_config_v1 已在 A 阶段重写为剥离版，
    // 它们仍承载非敏感配置，不能整个删除。
  }
}
