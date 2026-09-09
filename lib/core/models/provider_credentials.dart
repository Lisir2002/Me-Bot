import '../services/secure_storage/credential_record.dart';

/// 一个 provider 的全部敏感字段集合。
///
/// 存在的意义：把「provider 配置」拆成两半——
/// - 非敏感部分（baseUrl / models / 开关 ...）继续留在 SharedPreferences；
/// - 敏感部分（本类）只进安全存储，永不落明文。
///
/// 这里刻意**操作 Map 而不是 ProviderConfig 对象**：
/// `ProviderConfig` 定义在 1900 行的 `settings_provider.dart` 中，直接引用会让
/// 模型层与 provider 层互相 import 形成环。改为纯 JSON 出入后，
/// 迁移器（拿到的是原始 JSON）和 provider（拿到的是对象）都能复用同一套规则。
class ProviderCredentials {
  const ProviderCredentials({
    this.apiKey = '',
    this.serviceAccountJson,
    this.proxyUsername,
    this.proxyPassword,
    this.apiKeys = const <String, String>{},
  });

  /// 主 API Key。
  final String apiKey;

  /// Google Vertex AI 服务账号 JSON。
  final String? serviceAccountJson;

  /// 该 provider 专属代理用户名。
  final String? proxyUsername;

  /// 该 provider 专属代理密码。
  final String? proxyPassword;

  /// 多 Key 模式：keyId -> key 明文。
  final Map<String, String> apiKeys;

  static const ProviderCredentials empty = ProviderCredentials();

  bool get isEmpty =>
      apiKey.isEmpty &&
      (serviceAccountJson == null || serviceAccountJson!.isEmpty) &&
      (proxyUsername == null || proxyUsername!.isEmpty) &&
      (proxyPassword == null || proxyPassword!.isEmpty) &&
      apiKeys.isEmpty;

  // ------------------------------------------------------------ JSON 抽取 / 回填

  /// 从 provider 配置 JSON 中抽取全部凭证字段。
  factory ProviderCredentials.fromConfigJson(Map<String, dynamic> json) {
    final multiKeys = <String, String>{};
    final rawKeys = json['apiKeys'];
    if (rawKeys is List) {
      for (final e in rawKeys) {
        if (e is! Map) continue;
        final m = e.cast<String, dynamic>();
        final id = m['id']?.toString();
        final key = m['key']?.toString();
        if (id == null || key == null || key.isEmpty) continue;
        multiKeys[id] = key;
      }
    }
    return ProviderCredentials(
      apiKey: (json['apiKey'] as String?) ?? '',
      serviceAccountJson: json['serviceAccountJson'] as String?,
      proxyUsername: json['proxyUsername'] as String?,
      proxyPassword: json['proxyPassword'] as String?,
      apiKeys: multiKeys,
    );
  }

  /// 返回剥离全部凭证字段后的配置 JSON（可直接写入 SharedPreferences）。
  ///
  /// 注意：`apiKeys` 列表本身保留（id / usage / status 等是非敏感元数据），
  /// 只把每个条目里的 `key` 置空——避免多 Key 模式的统计信息在迁移中丢失。
  static Map<String, dynamic> stripCredentials(Map<String, dynamic> json) {
    final out = <String, dynamic>{
      for (final e in json.entries)
        if (!_sensitiveTopLevelKeys.contains(e.key)) e.key: e.value,
    };
    final rawKeys = out['apiKeys'];
    if (rawKeys is List) {
      out['apiKeys'] = [
        for (final e in rawKeys)
          if (e is Map)
            <String, dynamic>{
              for (final kv in e.entries)
                if (kv.key != 'key') kv.key: kv.value,
            }
          else
            e,
      ];
    }
    return out;
  }

  static const Set<String> _sensitiveTopLevelKeys = <String>{
    'apiKey',
    'serviceAccountJson',
    'proxyUsername',
    'proxyPassword',
  };

  /// 把凭证回填进已剥离的配置 JSON，得到内存态完整 JSON。
  Map<String, dynamic> mergeInto(Map<String, dynamic> stripped) {
    final out = Map<String, dynamic>.from(stripped);
    if (apiKey.isNotEmpty) out['apiKey'] = apiKey;
    if (serviceAccountJson != null) {
      out['serviceAccountJson'] = serviceAccountJson;
    }
    if (proxyUsername != null) out['proxyUsername'] = proxyUsername;
    if (proxyPassword != null) out['proxyPassword'] = proxyPassword;

    if (apiKeys.isNotEmpty) {
      final rawKeys = out['apiKeys'];
      if (rawKeys is List) {
        out['apiKeys'] = [
          for (final e in rawKeys)
            if (e is Map)
              <String, dynamic>{
                ...Map<String, dynamic>.from(e),
                'key': apiKeys[e['id']?.toString()] ?? '',
              }
            else
              e,
        ];
      }
    }
    return out;
  }

  // ------------------------------------------------------------ CredentialRecord

  /// 打包成一条 [CredentialRecord]（预留接口①）。
  ///
  /// 主 key 放在 `value`；其余字段放进 `ext`，
  /// 这样未来新增凭证字段（企业 KMS 引用、OAuth refresh token ...）无需改存储结构。
  CredentialRecord toRecord(String providerId) => CredentialRecord(
        type: CredentialType.apiKey,
        value: apiKey,
        id: providerId,
        ext: <String, dynamic>{
          if (serviceAccountJson != null && serviceAccountJson!.isNotEmpty)
            'serviceAccount': serviceAccountJson,
          if (proxyUsername != null && proxyUsername!.isNotEmpty)
            'proxyUser': proxyUsername,
          if (proxyPassword != null && proxyPassword!.isNotEmpty)
            'proxyPass': proxyPassword,
          if (apiKeys.isNotEmpty) 'apiKeys': apiKeys,
        },
      );

  factory ProviderCredentials.fromRecord(CredentialRecord? record) {
    if (record == null) return ProviderCredentials.empty;
    final ext = record.ext ?? const <String, dynamic>{};
    final rawKeys = ext['apiKeys'];
    final multiKeys = <String, String>{};
    if (rawKeys is Map) {
      for (final e in rawKeys.entries) {
        multiKeys[e.key.toString()] = e.value.toString();
      }
    }
    return ProviderCredentials(
      apiKey: record.value,
      serviceAccountJson: ext['serviceAccount'] as String?,
      proxyUsername: ext['proxyUser'] as String?,
      proxyPassword: ext['proxyPass'] as String?,
      apiKeys: multiKeys,
    );
  }

  @override
  String toString() =>
      'ProviderCredentials(apiKey: <${apiKey.length} chars>, keys: ${apiKeys.length})';
}
