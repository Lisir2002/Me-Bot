import '../services/secure_storage/credential_record.dart';

/// 搜索 / TTS 等「扁平服务配置」里的凭证处理。
///
/// 与 [ProviderCredentials] 的分工：
/// - provider 配置有嵌套结构（`apiKeys` 是数组，要按 keyId 逐个摘），单独一套；
/// - 搜索 / TTS 的服务配置是扁平 JSON（`{'id':..,'type':..,'apiKey':..}`），
///   用「按字段名剥离」这一条通用规则即可，无需为每个服务商写一套。
///
/// 新增服务商时只要凭证字段命中 [sensitiveKeys]，自动纳入保护范围，无需改代码。
class ServiceCredentials {
  const ServiceCredentials._();

  /// 被视为凭证的字段名。命中即剥离。
  static const Set<String> sensitiveKeys = <String>{
    'apiKey',
    'apiSecret',
    'accessKey',
    'secretKey',
    'token',
    'password',
    'username',
    'secret',
  };

  /// 从服务配置 JSON 中抽出凭证字段（空值忽略）。
  static Map<String, String> extract(Map<String, dynamic> json) =>
      <String, String>{
        for (final e in json.entries)
          if (sensitiveKeys.contains(e.key) &&
              e.value is String &&
              (e.value as String).isNotEmpty)
            e.key: e.value as String,
      };

  /// 剥离全部凭证字段后的配置（可安全落盘 / 进备份）。
  static Map<String, dynamic> strip(Map<String, dynamic> json) =>
      <String, dynamic>{
        for (final e in json.entries)
          if (!sensitiveKeys.contains(e.key)) e.key: e.value,
      };

  /// 把凭证回填进已剥离的配置。
  static Map<String, dynamic> merge(
    Map<String, dynamic> stripped,
    Map<String, String> secrets,
  ) =>
      <String, dynamic>{
        ...stripped,
        ...secrets,
      };

  // ------------------------------------------------------------ CredentialRecord

  /// 打包成一条 [CredentialRecord]（预留接口①）。
  ///
  /// 优先把 `apiKey` 放进 `value`（PR-7 健康面板主要关心它），
  /// 其余放进 `ext`；两者合起来就是完整的敏感字段集合，可无损还原。
  static CredentialRecord toRecord(String id, Map<String, String> secrets) {
    final primary = secrets['apiKey'] ??
        secrets['token'] ??
        secrets['password'] ??
        secrets['username'] ??
        '';
    return CredentialRecord(
      type: secrets.containsKey('apiKey')
          ? CredentialType.apiKey
          : (secrets.containsKey('password')
              ? CredentialType.password
              : CredentialType.custom),
      value: primary,
      id: id,
      ext: <String, dynamic>{
        for (final e in secrets.entries) e.key: e.value,
      },
    );
  }

  /// 从 record 还原凭证字段集合；record 为空返回空 map。
  static Map<String, String> fromRecord(CredentialRecord? record) {
    if (record == null) return const <String, String>{};
    // CredentialRecord.ext 是非空字段（默认 const {}），无需 ?? 兜底
    final ext = record.ext;
    final out = <String, String>{
      for (final e in ext.entries)
        if (e.value is String) e.key: e.value as String,
    };
    // value 是主凭证，ext 为空时（极小概率）用它兜底，避免丢 key
    if (out.isEmpty && record.value.isNotEmpty) {
      out['apiKey'] = record.value;
    }
    return out;
  }
}
