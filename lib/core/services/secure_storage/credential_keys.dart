/// 凭证在安全存储中的 key 常量（单一事实来源）。
///
/// 所有 key 统一 `credential_` 前缀，与 SharedPreferences 中的旧明文 key
/// （如 `provider_configs_v1`）物理隔离，便于迁移后的孤儿清理与扫描。
///
/// 新增凭证类型时在此追加常量即可，无需改动存储层实现。
class CredentialKeys {
  const CredentialKeys._();

  /// 统一前缀。
  static const String prefix = 'credential_';

  /// v1 迁移完成标记。
  static const String migrationV1Done = '${prefix}migration_v1_done';

  /// 单个 provider 的凭证包（内含 apiKey / apiKeys / serviceAccount）。
  static String provider(String providerId) => '${prefix}provider_$providerId';

  /// 全局代理密码。
  static const String globalProxyPassword = '${prefix}global_proxy_password';

  /// 全局代理用户名。
  static const String globalProxyUsername = '${prefix}global_proxy_username';

  /// WebDAV 密码。
  static const String webDavPassword = '${prefix}webdav_password';

  /// 单个「扁平服务配置」（搜索 / TTS 等）的凭证包，按服务 id 索引。
  ///
  /// 这些配置是扁平 JSON，凭证统一按 [ServiceCredentials] 的字段名规则处理，
  /// 因此新增服务商无需再改这里。
  static String service(String serviceId) => '${prefix}service_$serviceId';

  // ------------------------------------------------------------------ 解析

  /// 若 [key] 形如 `credential_provider_<id>` 则返回 `<id>`，否则 null。
  /// 用于体检 / 孤儿扫描时反向解析存储 key。
  static String? tryParseProviderId(String key) {
    const p = '${prefix}provider_';
    if (key.startsWith(p)) {
      final id = key.substring(p.length);
      return id.isEmpty ? null : id;
    }
    return null;
  }

  /// 若 [key] 形如 `credential_service_<id>` 则返回 `<id>`，否则 null。
  static String? tryParseServiceId(String key) {
    const p = '${prefix}service_';
    if (key.startsWith(p)) {
      final id = key.substring(p.length);
      return id.isEmpty ? null : id;
    }
    return null;
  }

  // ------------------------------------------------------------------ 旧明文 key

  // 以下常量仅作为迁移的「读取源」使用。迁移完成后这些 key
  // 会被立即清除（拍板①），之后不应再被任何业务代码引用。
  // 保留在此处是为了让「孤儿凭证扫描」有一个可对照的清单。

  /// 旧：provider 配置（明文内含 apiKey / apiKeys / serviceAccountJson / 代理口令）。
  static const String legacyProviderConfigs = 'provider_configs_v1';

  /// 旧：全局代理用户名。
  static const String legacyGlobalProxyUsername = 'global_proxy_username_v1';

  /// 旧：全局代理密码。
  static const String legacyGlobalProxyPassword = 'global_proxy_password_v1';

  /// 旧：WebDAV 配置（明文内含 password）。
  static const String legacyWebDavConfig = 'webdav_config_v1';

  /// 旧：搜索服务列表（数组，每项明文含 apiKey / username / password）。
  static const String legacySearchServices = 'search_services_v1';

  /// 旧：网络 TTS 服务列表（数组，每项明文含 apiKey）。
  static const String legacyTtsServices = 'tts_services_v1';
}
