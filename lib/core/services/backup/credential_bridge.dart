import 'dart:convert';

import '../../models/provider_credentials.dart';
import '../../models/service_credentials.dart';
import '../secure_storage/credential_keys.dart';
import '../secure_storage/secure_storage_service.dart';

/// 备份导出 / 恢复时的凭证处理策略。
enum BackupCredentialPolicy {
  /// 默认（拍板②）：备份文件里不含任何凭证明文。
  redacted,

  /// 显式选择「包含密钥」：把安全存储里的凭证注入备份内容。
  ///
  /// 仅用于加密备份（PR-4 的 JWE）或同账号设备迁移等用户明确知情场景。
  include,
}

/// 备份内容与安全存储之间的凭证桥接。
///
/// 为什么需要它：备份是「整个 SharedPreferences 快照」，
/// 而凭证在 PR-2 之后已经不在 SharedPreferences 里了。
/// 没有这层桥接会出现两个后果：
/// - 导出：备份里没有 Key，恢复后配置还在但 Key 全丢；
/// - 恢复：老备份（含明文）被整体写回，明文又回到磁盘。
///
/// 因此导出时按策略决定「脱敏」还是「注入」，恢复时一律
/// 「先抽走写进安全存储，再把干净内容交给 prefs」。
class BackupCredentialBridge {
  BackupCredentialBridge(this._secure);

  final SecureStorageService _secure;

  // ---------------------------------------------------------------------- 导出

  /// 按 [policy] 处理一份 prefs 快照，返回可直接写入备份文件的内容。
  Future<Map<String, dynamic>> prepareForExport(
    Map<String, dynamic> snapshot, {
    BackupCredentialPolicy policy = BackupCredentialPolicy.redacted,
  }) async {
    final out = <String, dynamic>{...snapshot};
    switch (policy) {
      case BackupCredentialPolicy.redacted:
        _redact(out);
        break;
      case BackupCredentialPolicy.include:
        await _inject(out);
        break;
    }
    return out;
  }

  void _redact(Map<String, dynamic> out) {
    _redactProviderConfigs(out);
    _redactServiceList(out, CredentialKeys.legacySearchServices);
    _redactServiceList(out, CredentialKeys.legacyTtsServices);
    _redactWebDav(out);
    out.remove(CredentialKeys.legacyGlobalProxyUsername);
    out.remove(CredentialKeys.legacyGlobalProxyPassword);
  }

  Future<void> _inject(Map<String, dynamic> out) async {
    await _injectProviderConfigs(out);
    await _injectServiceList(out, CredentialKeys.legacySearchServices);
    await _injectServiceList(out, CredentialKeys.legacyTtsServices);

    final davRaw = out[CredentialKeys.legacyWebDavConfig];
    final dav = _decode(davRaw);
    if (dav is Map<String, dynamic>) {
      final pwd = await _secure.read(CredentialKeys.webDavPassword);
      if (pwd != null && pwd.isNotEmpty) {
        _writeBack(out, CredentialKeys.legacyWebDavConfig,
            <String, dynamic>{...dav, 'password': pwd}, davRaw);
      }
    }

    for (final entry in <String, String>{
      CredentialKeys.legacyGlobalProxyUsername:
          CredentialKeys.globalProxyUsername,
      CredentialKeys.legacyGlobalProxyPassword:
          CredentialKeys.globalProxyPassword,
    }.entries) {
      final v = await _secure.read(entry.value);
      if (v != null && v.isNotEmpty) out[entry.key] = v;
    }
  }

  // ---------------------------------------------------------------------- 恢复

  /// 从备份内容中抽走全部凭证并写入安全存储；返回可安全写回 prefs 的内容。
  ///
  /// 兼容三种来源：
  /// 1. 新版脱敏备份（无凭证，直接放行）；
  /// 2. 老版明文备份（抽走 → 进安全存储）；
  /// 3. 含凭证的加密备份解密后（同上）。
  Future<Map<String, dynamic>> absorbOnRestore(
      Map<String, dynamic> incoming) async {
    final out = <String, dynamic>{...incoming};

    await _absorbProviderConfigs(out);
    await _absorbServiceList(out, CredentialKeys.legacySearchServices);
    await _absorbServiceList(out, CredentialKeys.legacyTtsServices);
    await _absorbWebDav(out);
    await _absorbProxy(out);

    return out;
  }

  Future<void> _absorbProviderConfigs(Map<String, dynamic> out) async {
    final raw = out[CredentialKeys.legacyProviderConfigs];
    final decoded = _decode(raw);
    if (decoded is! Map) return;

    final cleaned = <String, dynamic>{};
    for (final entry in decoded.entries) {
      final id = entry.key.toString();
      final value = entry.value;
      if (value is! Map) {
        cleaned[id] = value;
        continue;
      }
      final json = Map<String, dynamic>.from(value);
      final creds = ProviderCredentials.fromConfigJson(json);
      if (creds.isNotEmpty) {
        await _secure.writeCredential(
          CredentialKeys.provider(id),
          creds.toRecord(id),
        );
      }
      cleaned[id] = ProviderCredentials.stripCredentials(json);
    }
    _writeBack(out, CredentialKeys.legacyProviderConfigs, cleaned, raw);
  }

  Future<void> _absorbServiceList(Map<String, dynamic> out, String key) async {
    final raw = out[key];
    final decoded = _decode(raw);
    if (decoded is! List) return;

    final cleaned = <dynamic>[];
    for (final item in decoded) {
      if (item is! Map) {
        cleaned.add(item);
        continue;
      }
      final json = Map<String, dynamic>.from(item);
      final secrets = ServiceCredentials.extract(json);
      final id = json['id']?.toString();
      if (secrets.isNotEmpty && id != null && id.isNotEmpty) {
        await _secure.writeCredential(
          CredentialKeys.service(id),
          ServiceCredentials.toRecord(id, secrets),
        );
      }
      cleaned.add(ServiceCredentials.strip(json));
    }
    _writeBack(out, key, cleaned, raw);
  }

  Future<void> _absorbWebDav(Map<String, dynamic> out) async {
    final raw = out[CredentialKeys.legacyWebDavConfig];
    final decoded = _decode(raw);
    if (decoded is! Map) return;
    final json = Map<String, dynamic>.from(decoded);
    final pwd = (json['password'] as String?) ?? '';
    if (pwd.isNotEmpty) {
      await _secure.write(CredentialKeys.webDavPassword, pwd);
    }
    json.remove('password');
    _writeBack(out, CredentialKeys.legacyWebDavConfig, json, raw);
  }

  Future<void> _absorbProxy(Map<String, dynamic> out) async {
    for (final entry in <String, String>{
      CredentialKeys.legacyGlobalProxyUsername:
          CredentialKeys.globalProxyUsername,
      CredentialKeys.legacyGlobalProxyPassword:
          CredentialKeys.globalProxyPassword,
    }.entries) {
      final v = out[entry.key];
      if (v is String && v.isNotEmpty) {
        await _secure.write(entry.value, v);
      }
      out.remove(entry.key);
    }
  }

  // ---------------------------------------------------------------------- 核查

  /// 备份内容里是否还残留明文凭证。
  ///
  /// 用于导出前的自检与 UI 警示（例如生成分享二维码前先确认内容干净）。
  bool containsPlaintextCredentials(Map<String, dynamic> snapshot) {
    if (_scanProviderConfigs(snapshot)) return true;
    if (_scanServiceList(snapshot, CredentialKeys.legacySearchServices)) {
      return true;
    }
    if (_scanServiceList(snapshot, CredentialKeys.legacyTtsServices)) {
      return true;
    }
    final dav = _decode(snapshot[CredentialKeys.legacyWebDavConfig]);
    if (dav is Map && ((dav['password'] as String?) ?? '').isNotEmpty) {
      return true;
    }
    for (final key in <String>[
      CredentialKeys.legacyGlobalProxyUsername,
      CredentialKeys.legacyGlobalProxyPassword,
    ]) {
      final v = snapshot[key];
      if (v is String && v.isNotEmpty) return true;
    }
    return false;
  }

  bool _scanProviderConfigs(Map<String, dynamic> snapshot) {
    final decoded = _decode(snapshot[CredentialKeys.legacyProviderConfigs]);
    if (decoded is! Map) return false;
    for (final v in decoded.values) {
      if (v is! Map) continue;
      if (ProviderCredentials.fromConfigJson(Map<String, dynamic>.from(v))
          .isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  bool _scanServiceList(Map<String, dynamic> snapshot, String key) {
    final decoded = _decode(snapshot[key]);
    if (decoded is! List) return false;
    for (final item in decoded) {
      if (item is! Map) continue;
      if (ServiceCredentials.extract(Map<String, dynamic>.from(item))
          .isNotEmpty) {
        return true;
      }
    }
    return false;
  }

  // ------------------------------------------------------------------ 孤儿清理

  /// 删除安全存储中已经没有对应实体的凭证条目。
  ///
  /// 场景：provider / 服务被删除时理论上已同步清理，但崩溃、降级路径、
  /// 旧版本残留都可能留下孤儿。返回被清理的条目数。
  Future<int> purgeOrphans({
    required Set<String> providerIds,
    required Set<String> serviceIds,
  }) async {
    final all = await _secure.readAll();
    var removed = 0;
    for (final key in all.keys) {
      if (key.startsWith('${CredentialKeys.prefix}provider_')) {
        final id = key.substring('${CredentialKeys.prefix}provider_'.length);
        if (!providerIds.contains(id)) {
          await _secure.delete(key);
          removed++;
        }
      } else if (key.startsWith('${CredentialKeys.prefix}service_')) {
        final id = key.substring('${CredentialKeys.prefix}service_'.length);
        if (!serviceIds.contains(id)) {
          await _secure.delete(key);
          removed++;
        }
      }
    }
    return removed;
  }

  // ---------------------------------------------------------------------- 工具

  /// 兼容两种形态：prefs 里的 JSON 字符串，或已解码的对象。
  Object? _decode(Object? raw) {
    if (raw is String) {
      if (raw.isEmpty) return null;
      try {
        return jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }
    return raw;
  }

  /// 写回时保持原始形态（原本是字符串就重新编码），避免类型漂移。
  void _writeBack(
    Map<String, dynamic> out,
    String key,
    Object? decoded,
    Object? original,
  ) {
    out[key] = original is String ? jsonEncode(decoded) : decoded;
  }

  void _redactProviderConfigs(Map<String, dynamic> out) {
    final raw = out[CredentialKeys.legacyProviderConfigs];
    final decoded = _decode(raw);
    if (decoded is! Map) return;
    final cleaned = <String, dynamic>{
      for (final e in decoded.entries)
        e.key: e.value is Map
            ? ProviderCredentials.stripCredentials(
                Map<String, dynamic>.from(e.value as Map))
            : e.value,
    };
    _writeBack(out, CredentialKeys.legacyProviderConfigs, cleaned, raw);
  }

  void _redactServiceList(Map<String, dynamic> out, String key) {
    final raw = out[key];
    final decoded = _decode(raw);
    if (decoded is! List) return;
    final cleaned = <dynamic>[
      for (final item in decoded)
        item is Map
            ? ServiceCredentials.strip(Map<String, dynamic>.from(item))
            : item,
    ];
    _writeBack(out, key, cleaned, raw);
  }

  void _redactWebDav(Map<String, dynamic> out) {
    final raw = out[CredentialKeys.legacyWebDavConfig];
    final decoded = _decode(raw);
    if (decoded is! Map) return;
    final json = Map<String, dynamic>.from(decoded)..remove('password');
    _writeBack(out, CredentialKeys.legacyWebDavConfig, json, raw);
  }

  Future<void> _injectProviderConfigs(Map<String, dynamic> out) async {
    final raw = out[CredentialKeys.legacyProviderConfigs];
    final decoded = _decode(raw);
    if (decoded is! Map) return;
    final merged = <String, dynamic>{};
    for (final e in decoded.entries) {
      if (e.value is! Map) {
        merged[e.key] = e.value;
        continue;
      }
      final json = Map<String, dynamic>.from(e.value as Map);
      final record = await _secure
          .readCredential(CredentialKeys.provider(e.key.toString()));
      final creds = ProviderCredentials.fromRecord(record);
      merged[e.key] = creds.mergeInto(json);
    }
    _writeBack(out, CredentialKeys.legacyProviderConfigs, merged, raw);
  }

  Future<void> _injectServiceList(Map<String, dynamic> out, String key) async {
    final raw = out[key];
    final decoded = _decode(raw);
    if (decoded is! List) return;
    final merged = <dynamic>[];
    for (final item in decoded) {
      if (item is! Map) {
        merged.add(item);
        continue;
      }
      final json = Map<String, dynamic>.from(item);
      final id = json['id']?.toString();
      if (id == null || id.isEmpty) {
        merged.add(json);
        continue;
      }
      final record = await _secure.readCredential(CredentialKeys.service(id));
      final secrets = ServiceCredentials.fromRecord(record);
      merged.add(ServiceCredentials.merge(json, secrets));
    }
    _writeBack(out, key, merged, raw);
  }
}
