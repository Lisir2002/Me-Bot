import 'dart:convert';

/// 凭证类型。
///
/// 新增类型时在此扩展即可（预留接口①）。反序列化遇到未知类型时回落为
/// [CredentialType.custom]，保证「新版本写入的凭证」不会让旧版本崩溃。
enum CredentialType {
  apiKey,
  serviceAccount,
  password,
  token,
  custom;

  static CredentialType parse(String? name) {
    switch (name) {
      case 'apiKey':
        return apiKey;
      case 'serviceAccount':
        return serviceAccount;
      case 'password':
        return password;
      case 'token':
        return token;
      default:
        return custom;
    }
  }
}

/// 凭证记录信封（预留接口①）。
///
/// 取代「裸字符串」存储：除密文值本身，还携带类型与生命周期元数据，
/// 为以下未来能力留门：
/// - 更多凭证类型（OAuth token、云厂商临时凭证）→ [type]
/// - 密钥健康面板（PR-7 最近使用 / 轮换提醒）→ [lastUsedAt]、[lastRotatedAt]
/// - 企业级密钥管理（租户、标签、计费信息）→ [ext]
///
/// ⚠️ 本对象仅在内存中存在，序列化结果只写入安全存储，永不落入
/// SharedPreferences、备份文件或日志。
class CredentialRecord {
  const CredentialRecord({
    required this.type,
    required this.value,
    this.id,
    this.createdAt,
    this.lastUsedAt,
    this.lastRotatedAt,
    this.ext = const <String, dynamic>{},
  });

  final CredentialType type;

  /// 凭证明文值（仅在内存中；落盘由安全存储后端加密）。
  final String value;

  /// 可选业务标识（如 providerId、keyId）。
  final String? id;

  final DateTime? createdAt;
  final DateTime? lastUsedAt;
  final DateTime? lastRotatedAt;

  /// 扩展位：租户/标签/计费等自定义元数据。
  final Map<String, dynamic> ext;

  /// 便捷构造：新建凭证（自动填充 createdAt）。
  factory CredentialRecord.create({
    required CredentialType type,
    required String value,
    String? id,
    Map<String, dynamic> ext = const <String, dynamic>{},
  }) {
    return CredentialRecord(
      type: type,
      value: value,
      id: id,
      createdAt: DateTime.now(),
      ext: ext,
    );
  }

  /// 记录一次使用（供 PR-7 健康面板展示「最近使用」）。
  CredentialRecord touch() => copyWith(lastUsedAt: DateTime.now());

  /// 记录一次轮换（供 PR-7 计算「距上次轮换天数」）。
  CredentialRecord markRotated() => copyWith(lastRotatedAt: DateTime.now());

  CredentialRecord copyWith({
    CredentialType? type,
    String? value,
    String? id,
    DateTime? createdAt,
    DateTime? lastUsedAt,
    DateTime? lastRotatedAt,
    Map<String, dynamic>? ext,
  }) {
    return CredentialRecord(
      type: type ?? this.type,
      value: value ?? this.value,
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      lastRotatedAt: lastRotatedAt ?? this.lastRotatedAt,
      ext: ext ?? this.ext,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'type': type.name,
        'value': value,
        if (id != null) 'id': id,
        if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
        if (lastUsedAt != null) 'lastUsedAt': lastUsedAt!.toIso8601String(),
        if (lastRotatedAt != null)
          'lastRotatedAt': lastRotatedAt!.toIso8601String(),
        if (ext.isNotEmpty) 'ext': ext,
      };

  static CredentialRecord? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final value = raw['value'];
    if (value is! String || value.isEmpty) return null;
    return CredentialRecord(
      type: CredentialType.parse(raw['type'] as String?),
      value: value,
      id: raw['id'] as String?,
      createdAt: DateTime.tryParse(raw['createdAt'] as String? ?? ''),
      lastUsedAt: DateTime.tryParse(raw['lastUsedAt'] as String? ?? ''),
      lastRotatedAt: DateTime.tryParse(raw['lastRotatedAt'] as String? ?? ''),
      ext: Map<String, dynamic>.from(
        (raw['ext'] as Map?) ?? const <String, dynamic>{},
      ),
    );
  }

  /// 编码为写入安全存储的字符串。
  String encode() => jsonEncode(toJson());

  /// 从安全存储读出的字符串解码；损坏或为空返回 null（不抛异常，便于 fail-soft）。
  static CredentialRecord? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return fromJson(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }
}
