import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart' show Hmac, sha256;

import '../../backup/backup_encryptor.dart';
import '../../backup/credential_bridge.dart';
import '../../backup/data_sync.dart' show SharedPreferencesAsync;
import '../../security/key_health_service.dart';
import '../../secure_storage/secure_storage_bootstrap.dart';
import '../../../../utils/app_directories.dart';
import '../jsonrpc_engine_base.dart';

/// MiniMe-Data — 内置 MCP 服务器引擎。
///
/// 提供两类工具：
/// 1. 加密密钥工具：派生密钥 / 加密数据 / 解密数据 / 密钥健康查询；
/// 2. 备份导入导出工具：导出备份 / 导入备份 / 校验备份 / 列出本地备份。
///
/// 加密/解密直接复用 [BackupEncryptor]，不重复实现加密算法；
/// 凭证桥接复用 [BackupCredentialBridge]，保证导出/导入与 WebDAV 备份一致。
class MiniMeDataMcpServerEngine extends BaseJsonRpcMcpEngine {
  @override
  String get serverName => 'MiniMe-Data';

  @override
  String get serverVersion => '0.1.0';

  // ---------------------------------------------------------------- tools/list

  @override
  List<Map<String, dynamic>> toolDefinitions() {
    return [
      // ============ 加密密钥工具（4 个） ============
      {
        'name': 'derive_key',
        'description':
            '从口令派生加密密钥（PBKDF2-HMAC-SHA256）。返回派生密钥的 base64 编码与使用的 salt。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'passphrase': {
              'type': 'string',
              'description': '用于派生密钥的口令。',
            },
            'salt': {
              'type': 'string',
              'description': '可选，base64 编码的 salt；不传则随机生成 16 字节。',
            },
            'iterations': {
              'type': 'integer',
              'default': 310000,
              'description': 'PBKDF2 迭代次数，默认 310000（OWASP 推荐下限）。',
            },
            'key_length': {
              'type': 'integer',
              'default': 32,
              'description': '派生密钥长度（字节），默认 32（AES-256）。',
            },
          },
          'required': ['passphrase'],
        },
      },
      {
        'name': 'encrypt_data',
        'description':
            '用口令加密一段文本。内部调用 BackupEncryptor.seal()，返回 v2 信封 JSON 字符串。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'plaintext': {
              'type': 'string',
              'description': '待加密的明文文本。',
            },
            'passphrase': {
              'type': 'string',
              'description': '加密口令，至少 8 位。',
            },
          },
          'required': ['plaintext', 'passphrase'],
        },
      },
      {
        'name': 'decrypt_data',
        'description':
            '用口令解密一段 v2 信封 JSON。返回明文；口令错误或格式不支持时返回 isError。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'envelope_json': {
              'type': 'string',
              'description': 'encrypt_data 返回的 v2 信封 JSON 字符串。',
            },
            'passphrase': {
              'type': 'string',
              'description': '解密口令。',
            },
          },
          'required': ['envelope_json', 'passphrase'],
        },
      },
      {
        'name': 'key_health',
        'description':
            '查询密钥健康状态。返回每个 provider 的 keyCount、lastRotatedAt、needsRotation 等；不传 provider_id 则返回全部。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'provider_id': {
              'type': 'string',
              'description': '可选，只查询该 provider；不传则返回全部。',
            },
          },
          'required': <String>[],
        },
      },

      // ============ 备份导入导出工具（4 个） ============
      {
        'name': 'export_backup',
        'description':
            '导出当前配置备份（SharedPreferences 快照）。提供 passphrase 时返回加密 v2 信封；否则返回明文 JSON。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'passphrase': {
              'type': 'string',
              'description': '可选；提供后对整包备份加密（至少 8 位）。',
            },
            'include_credentials': {
              'type': 'boolean',
              'default': true,
              'description': '是否把安全存储中的凭证注入备份。默认 true。',
            },
          },
          'required': <String>[],
        },
      },
      {
        'name': 'import_backup',
        'description':
            '导入备份。解析备份 JSON 并写回 SharedPreferences；加密备份需提供 passphrase。返回导入结果摘要。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'backup_json': {
              'type': 'string',
              'description': 'export_backup 返回的备份 JSON 字符串（明文或 v2 信封）。',
            },
            'passphrase': {
              'type': 'string',
              'description': '加密备份所需的口令；明文备份可省略。',
            },
          },
          'required': ['backup_json'],
        },
      },
      {
        'name': 'verify_backup',
        'description':
            '校验备份文件。检查格式/版本/完整性，返回是否有效、格式版本、是否加密、条目数量。',
        'inputSchema': {
          'type': 'object',
          'properties': {
            'backup_json': {
              'type': 'string',
              'description': '待校验的备份 JSON 字符串。',
            },
          },
          'required': ['backup_json'],
        },
      },
      {
        'name': 'list_backups',
        'description':
            '列出本地应用文档目录下的备份文件。返回文件名、大小、创建时间列表。',
        'inputSchema': {
          'type': 'object',
          'properties': <String, dynamic>{},
          'required': <String>[],
        },
      },
    ];
  }

  // ---------------------------------------------------------------- tools/call

  @override
  Future<Map<String, dynamic>> callTool(
      String name, Map<String, dynamic> arguments) async {
    try {
      switch (name) {
        case 'derive_key':
          return await _deriveKey(arguments);
        case 'encrypt_data':
          return await _encryptData(arguments);
        case 'decrypt_data':
          return await _decryptData(arguments);
        case 'key_health':
          return await _keyHealth(arguments);
        case 'export_backup':
          return await _exportBackup(arguments);
        case 'import_backup':
          return await _importBackup(arguments);
        case 'verify_backup':
          return _verifyBackup(arguments);
        case 'list_backups':
          return await _listBackups(arguments);
        default:
          return BaseJsonRpcMcpEngine.errorResult('Tool not found: $name');
      }
    } catch (e) {
      return BaseJsonRpcMcpEngine.errorResult('工具执行失败: $e');
    }
  }

  // ---------------------------------------------------- 加密密钥工具实现

  Future<Map<String, dynamic>> _deriveKey(Map<String, dynamic> args) async {
    final passphrase = (args['passphrase'] ?? '').toString();
    if (passphrase.isEmpty) {
      return BaseJsonRpcMcpEngine.errorResult('参数 passphrase 不能为空');
    }
    // salt：可选 base64；不传则随机生成 16 字节
    List<int> salt;
    final saltB64 = args['salt'];
    if (saltB64 is String && saltB64.isNotEmpty) {
      try {
        salt = base64Decode(saltB64);
      } catch (_) {
        return BaseJsonRpcMcpEngine.errorResult('参数 salt 不是合法的 base64');
      }
    } else {
      salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    }
    final iterations = (args['iterations'] as num?)?.toInt() ?? 310000;
    final keyLength = (args['key_length'] as num?)?.toInt() ?? 32;
    if (iterations < 1) {
      return BaseJsonRpcMcpEngine.errorResult('iterations 必须 >= 1');
    }
    if (keyLength < 1 || keyLength > 1024) {
      return BaseJsonRpcMcpEngine.errorResult('key_length 必须在 1..1024 之间');
    }

    final dk = _pbkdf2(utf8.encode(passphrase), salt, iterations, keyLength);
    return BaseJsonRpcMcpEngine.jsonResult({
      'key': base64Encode(dk),
      'salt': base64Encode(salt),
      'iterations': iterations,
      'key_length': keyLength,
      'kdf': 'PBKDF2-HMAC-SHA256',
    });
  }

  Future<Map<String, dynamic>> _encryptData(Map<String, dynamic> args) async {
    final plaintext = (args['plaintext'] ?? '').toString();
    final passphrase = (args['passphrase'] ?? '').toString();
    if (plaintext.isEmpty) {
      return BaseJsonRpcMcpEngine.errorResult('参数 plaintext 不能为空');
    }
    if (passphrase.length < BackupEncryptor.minPassphraseLength) {
      return BaseJsonRpcMcpEngine.errorResult(
          'passphrase 至少需要 ${BackupEncryptor.minPassphraseLength} 位');
    }
    // 把明文包一层，便于解密时还原原始字符串
    final envelope = await BackupEncryptor.seal(
      {'data': plaintext},
      passphrase: passphrase,
    );
    return BaseJsonRpcMcpEngine.textResult(jsonEncode(envelope));
  }

  Future<Map<String, dynamic>> _decryptData(Map<String, dynamic> args) async {
    final envelopeJson = (args['envelope_json'] ?? '').toString();
    final passphrase = (args['passphrase'] ?? '').toString();
    if (envelopeJson.isEmpty) {
      return BaseJsonRpcMcpEngine.errorResult('参数 envelope_json 不能为空');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(envelopeJson);
    } catch (_) {
      return BaseJsonRpcMcpEngine.errorResult('envelope_json 不是合法 JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      return BaseJsonRpcMcpEngine.errorResult('envelope_json 顶层必须是对象');
    }
    try {
      final settings = await BackupEncryptor.open(decoded, passphrase: passphrase);
      final data = settings['data'];
      if (data is! String) {
        return BaseJsonRpcMcpEngine.errorResult('解密结果中未找到 data 字段');
      }
      return BaseJsonRpcMcpEngine.textResult(data);
    } on BackupCryptoError catch (e) {
      return BaseJsonRpcMcpEngine.errorResult('解密失败: ${e.message} (${e.kind.name})');
    } catch (e) {
      return BaseJsonRpcMcpEngine.errorResult('解密失败: $e');
    }
  }

  Future<Map<String, dynamic>> _keyHealth(Map<String, dynamic> args) async {
    if (!SecureStorage.isInitialized) {
      return BaseJsonRpcMcpEngine.errorResult(
          '安全存储尚未初始化，无法查询密钥健康状态');
    }
    final providerIdFilter = (args['provider_id'] as String?)?.trim();
    final service = KeyHealthService(SecureStorage.instance);
    final infos = await service.scan();
    final list = infos
        .where((i) =>
            providerIdFilter == null ||
            providerIdFilter.isEmpty ||
            i.providerId == providerIdFilter)
        .map((i) => {
              'provider_id': i.providerId,
              'key_count': i.keyCount,
              'has_service_account': i.hasServiceAccount,
              'created_at': i.createdAt?.toUtc().toIso8601String(),
              'last_used_at': i.lastUsedAt?.toUtc().toIso8601String(),
              'last_rotated_at': i.lastRotatedAt?.toUtc().toIso8601String(),
              'needs_rotation': i.needsRotation,
              'days_since_rotation': i.daysSinceRotation,
            })
        .toList(growable: false);
    return BaseJsonRpcMcpEngine.jsonResult({
      'providers': list,
      'total': list.length,
      'needs_rotation_count': list.where((e) => e['needs_rotation'] == true).length,
      'rotation_threshold_days': service.rotationThresholdDays,
    });
  }

  // ---------------------------------------------------- 备份导入导出实现

  Future<Map<String, dynamic>> _exportBackup(Map<String, dynamic> args) async {
    final passphrase = (args['passphrase'] as String?)?.trim();
    final includeCredentials = (args['include_credentials'] as bool?) ?? true;

    final prefs = await SharedPreferencesAsync.instance;
    final snapshot = await prefs.snapshot();

    final bool hasPassphrase = passphrase != null && passphrase.isNotEmpty;
    if (hasPassphrase && passphrase.length < BackupEncryptor.minPassphraseLength) {
      return BaseJsonRpcMcpEngine.errorResult(
          'passphrase 至少需要 ${BackupEncryptor.minPassphraseLength} 位');
    }

    Map<String, dynamic> prepared = Map<String, dynamic>.from(snapshot);
    if (SecureStorage.isInitialized) {
      final bridge = BackupCredentialBridge(SecureStorage.instance);
      final policy = hasPassphrase
          ? BackupCredentialPolicy.encrypted
          : (includeCredentials
              ? BackupCredentialPolicy.include
              : BackupCredentialPolicy.redacted);
      prepared = await bridge.prepareForExport(prepared, policy: policy);
    }

    if (hasPassphrase) {
      final envelope = await BackupEncryptor.seal(prepared, passphrase: passphrase);
      return BaseJsonRpcMcpEngine.jsonResult({
        'encrypted': true,
        'format': envelope['format'],
        'version': envelope['version'],
        'json': jsonEncode(envelope),
      });
    }
    return BaseJsonRpcMcpEngine.jsonResult({
      'encrypted': false,
      'format': 'settings-snapshot',
      'version': 1,
      'entry_count': prepared.length,
      'json': jsonEncode(prepared),
    });
  }

  Future<Map<String, dynamic>> _importBackup(Map<String, dynamic> args) async {
    final backupJson = (args['backup_json'] ?? '').toString();
    final passphrase = (args['passphrase'] as String?)?.trim();
    if (backupJson.isEmpty) {
      return BaseJsonRpcMcpEngine.errorResult('参数 backup_json 不能为空');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(backupJson);
    } catch (_) {
      return BaseJsonRpcMcpEngine.errorResult('backup_json 不是合法 JSON');
    }
    Map<String, dynamic> settings;
    bool encrypted = false;
    if (decoded is Map<String, dynamic> && BackupEncryptor.isEnvelope(decoded)) {
      encrypted = true;
      try {
        settings = await BackupEncryptor.open(decoded, passphrase: passphrase);
      } on BackupCryptoError catch (e) {
        return BaseJsonRpcMcpEngine.errorResult('解密备份失败: ${e.message} (${e.kind.name})');
      }
    } else if (decoded is Map<String, dynamic>) {
      settings = decoded;
    } else {
      return BaseJsonRpcMcpEngine.errorResult('备份 JSON 顶层必须是对象');
    }

    // 抽走凭证写进安全存储，剩下的写回 prefs
    if (SecureStorage.isInitialized) {
      settings = await BackupCredentialBridge(SecureStorage.instance)
          .absorbOnRestore(settings);
    }

    final prefs = await SharedPreferencesAsync.instance;
    await prefs.restore(settings);

    return BaseJsonRpcMcpEngine.jsonResult({
      'imported': true,
      'encrypted': encrypted,
      'entry_count': settings.length,
      'keys': settings.keys.toList()..sort(),
    });
  }

  Map<String, dynamic> _verifyBackup(Map<String, dynamic> args) {
    final backupJson = (args['backup_json'] ?? '').toString();
    if (backupJson.isEmpty) {
      return BaseJsonRpcMcpEngine.errorResult('参数 backup_json 不能为空');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(backupJson);
    } catch (_) {
      return BaseJsonRpcMcpEngine.jsonResult({
        'valid': false,
        'reason': 'JSON 解析失败',
      });
    }
    if (decoded is Map<String, dynamic> && BackupEncryptor.isEnvelope(decoded)) {
      final crypto = decoded['crypto'];
      return BaseJsonRpcMcpEngine.jsonResult({
        'valid': true,
        'format': decoded['format'],
        'version': decoded['version'],
        'encrypted': true,
        'entries': null, // 加密备份需口令才能统计条目
        'algorithm': crypto is Map ? crypto['alg'] : null,
        'kdf': crypto is Map ? crypto['kdf'] : null,
      });
    }
    if (decoded is Map<String, dynamic>) {
      return BaseJsonRpcMcpEngine.jsonResult({
        'valid': true,
        'format': 'settings-snapshot',
        'version': 1,
        'encrypted': false,
        'entries': decoded.length,
      });
    }
    return BaseJsonRpcMcpEngine.jsonResult({
      'valid': false,
      'reason': '备份顶层不是对象',
    });
  }

  Future<Map<String, dynamic>> _listBackups(Map<String, dynamic> args) async {
    try {
      final root = await AppDirectories.getAppDataDirectory();
      if (!await root.exists()) {
        return BaseJsonRpcMcpEngine.jsonResult({'files': <dynamic>[]});
      }
      final pattern = RegExp(r'^minime-core_backup_.*\.(zip|json)$');
      final files = <Map<String, dynamic>>[];
      await for (final ent in root.list(recursive: false, followLinks: false)) {
        if (ent is! File) continue;
        final name = ent.uri.pathSegments.last;
        if (!pattern.hasMatch(name)) continue;
        final stat = await ent.stat();
        files.add({
          'name': name,
          'path': ent.path,
          'size_bytes': stat.size,
          'created_at': stat.modified.toUtc().toIso8601String(),
        });
      }
      files.sort((a, b) =>
          (b['created_at'] as String).compareTo(a['created_at'] as String));
      return BaseJsonRpcMcpEngine.jsonResult({
        'directory': root.path,
        'files': files,
        'total': files.length,
      });
    } catch (e) {
      return BaseJsonRpcMcpEngine.errorResult('扫描备份目录失败: $e');
    }
  }

  // ---------------------------------------------------- PBKDF2（与 BackupEncryptor 同算法）

  /// PBKDF2-HMAC-SHA256 自实现（与 BackupEncryptor._pbkdf2 对齐）。
  static List<int> _pbkdf2(
      List<int> password, List<int> salt, int iterations, int dkLen) {
    final hmac = Hmac(sha256, password);
    final dk = <int>[];
    final blocks = (dkLen + 31) ~/ 32; // SHA-256 输出 32 字节
    for (var i = 1; i <= blocks; i++) {
      final saltBlock = <int>[
        ...salt,
        (i >> 24) & 0xff,
        (i >> 16) & 0xff,
        (i >> 8) & 0xff,
        i & 0xff,
      ];
      var u = hmac.convert(saltBlock).bytes;
      final t = List<int>.from(u);
      for (var j = 1; j < iterations; j++) {
        u = hmac.convert(u).bytes;
        for (var k = 0; k < t.length; k++) {
          t[k] ^= u[k];
        }
      }
      dk.addAll(t);
    }
    return dk.take(dkLen).toList();
  }
}
