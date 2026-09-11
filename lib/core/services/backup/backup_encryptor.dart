import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart' show Hmac, sha256;
import 'package:jose/jose.dart';

import '../security/credential_audit_logger.dart';

/// 备份加解密失败的错误类型。
enum BackupCryptoErrorKind {
  /// 备份已加密，但调用方未提供口令。
  needPassphrase,

  /// 提供了口令，但校验失败（口令错误或被篡改）。
  wrongPassphrase,

  /// 不支持的备份格式 / 版本 / 算法。
  unsupported,

  /// 备份内容损坏，无法解析。
  corrupt,
}

/// 备份加密相关错误。
///
/// 通过 [kind] 让 UI 精确分流：缺失口令时弹输入、口令错误时提示重试、
/// 不支持/损坏时报错。
class BackupCryptoError implements Exception {
  const BackupCryptoError(this.message, this.kind);

  final String message;
  final BackupCryptoErrorKind kind;

  @override
  String toString() => message;
}

/// 加密备份工具（PR-4）。
///
/// 方案：口令经 PBKDF2-HMAC-SHA256（310k 迭代，OWASP 推荐下限）派生 256-bit KEK，
/// 再用 AES-256-GCM（jose 的 `dir` 密钥管理 + `A256GCM` 内容加密）对**整包
/// settings 快照**加密，输出 v2 信封。
///
/// 口令**只在内存中参与派生与加密，不落盘、不进入任何日志**。
/// 口令一旦遗忘不可恢复（仅影响该备份文件），由 UI 明示。
///
/// v2 信封：
/// ```json
/// {
///   "format": "minime-core-backup",
///   "version": 2,
///   "crypto": {
///     "alg": "A256GCM",
///     "kdf": "PBKDF2-SHA256",
///     "iterations": 310000,
///     "salt": "<base64>",
///     "jwe": "<compact jwe>"
///   }
/// }
/// ```
class BackupEncryptor {
  BackupEncryptor._();

  /// 当前输出格式。0.0.51 起从旧名 `kelivo-backup` 迁移至此。
  static const String format = 'minime-core-backup';

  /// 旧格式名（0.0.47–0.0.50 使用），仅用于导入兼容，不再用于输出。
  static const String legacyFormat = 'kelivo-backup';

  static const int version = 2;
  static const String contentAlg = 'A256GCM';
  static const String kdf = 'PBKDF2-SHA256';
  static const int kdfIterations = 310000;
  static const int saltBytes = 16;

  /// 口令最短长度（至少 8 位，避免弱口令被暴力破解）。
  static const int minPassphraseLength = 8;

  /// 是否是 v2 加密信封（兼容旧格式名 `kelivo-backup`）。
  static bool isEnvelope(Object? data) {
    if (data is! Map<String, dynamic>) return false;
    final fmt = data['format'];
    return (fmt == format || fmt == legacyFormat) &&
        data['version'] == version &&
        data['crypto'] is Map<String, dynamic>;
  }

  /// 加密整包 settings 快照（应已含凭证，见 [BackupCredentialPolicy.encrypted]）。
  ///
  /// [passphrase] 至少 [minPassphraseLength] 位；太短抛 [BackupCryptoErrorKind.unsupported]。
  static Future<Map<String, dynamic>> seal(
    Map<String, dynamic> settings, {
    required String passphrase,
  }) async {
    _checkPassphrase(passphrase);
    final salt = _randomBytes(saltBytes);
    final kek = _deriveKek(passphrase, salt);
    final payload = utf8.encode(jsonEncode(settings));
    final jwe = _encrypt(payload, kek);
    // 审计：加密备份生成成功（仅记算法/迭代次数，不含口令与明文）
    CredentialAuditLogger.record('export', 'backup:jwe', detail: 'seal alg=$contentAlg kdf=$kdf iters=$kdfIterations');
    return <String, dynamic>{
      'format': format,
      'version': version,
      'crypto': <String, dynamic>{
        'alg': contentAlg,
        'kdf': kdf,
        'iterations': kdfIterations,
        'salt': base64Encode(salt),
        'jwe': jwe,
      },
    };
  }

  /// 解密 v2 信封，返回 settings 快照。
  ///
  /// - [passphrase] 为空 → [BackupCryptoErrorKind.needPassphrase]
  /// - 口令错误/被篡改 → [BackupCryptoErrorKind.wrongPassphrase]
  /// - 版本/算法不支持 → [BackupCryptoErrorKind.unsupported]
  /// - 结构损坏 → [BackupCryptoErrorKind.corrupt]
  static Future<Map<String, dynamic>> open(
    Map<String, dynamic> envelope, {
    String? passphrase,
  }) async {
    final fmt = envelope['format'];
    if (fmt != format && fmt != legacyFormat) {
      throw const BackupCryptoError('不支持的备份格式', BackupCryptoErrorKind.unsupported);
    }
    if (envelope['version'] != version) {
      throw BackupCryptoError(
        '不支持的备份版本：${envelope['version']}（仅支持 v$version）',
        BackupCryptoErrorKind.unsupported,
      );
    }
    final crypto = envelope['crypto'];
    if (crypto is! Map<String, dynamic>) {
      throw const BackupCryptoError('备份缺少加密信息', BackupCryptoErrorKind.corrupt);
    }
    if (crypto['alg'] != contentAlg) {
      throw BackupCryptoError(
        '不支持的加密算法：${crypto['alg']}',
        BackupCryptoErrorKind.unsupported,
      );
    }
    final saltB64 = crypto['salt'];
    final jwe = crypto['jwe'];
    if (saltB64 is! String || jwe is! String) {
      throw const BackupCryptoError('加密信息不完整', BackupCryptoErrorKind.corrupt);
    }

    final p = passphrase ?? '';
    if (p.isEmpty) {
      throw const BackupCryptoError('该备份已加密，需要提供口令', BackupCryptoErrorKind.needPassphrase);
    }
    _checkPassphrase(p);

    final salt = base64Decode(saltB64);
    final kek = _deriveKek(p, salt);
    try {
      final decoded = await _decrypt(jwe, kek);
      // 审计：加密备份解密成功（不含口令与明文）
      CredentialAuditLogger.record('restore', 'backup:jwe', detail: 'open ok');
      return decoded;
    } on BackupCryptoError {
      rethrow;
    } on Exception catch (e, st) {
      // 审计：解密失败（口令错误或被篡改，不含口令）
      CredentialAuditLogger.record('restore', 'backup:jwe', ok: false, detail: 'wrongPassphrase', error: e, stack: st);
      throw const BackupCryptoError('口令错误，无法解密备份', BackupCryptoErrorKind.wrongPassphrase);
    }
  }

  // ------------------------------------------------------------------ 内部

  static void _checkPassphrase(String passphrase) {
    if (passphrase.length < minPassphraseLength) {
      throw BackupCryptoError(
        '备份口令至少需要 $minPassphraseLength 位',
        BackupCryptoErrorKind.unsupported,
      );
    }
  }

  static List<int> _randomBytes(int n) =>
      List<int>.generate(n, (_) => Random.secure().nextInt(256));

  /// PBKDF2-HMAC-SHA256 派生 256-bit KEK（自实现，避免额外依赖）。
  static List<int> _deriveKek(String passphrase, List<int> salt) {
    return _pbkdf2(utf8.encode(passphrase), salt, kdfIterations, 32);
  }

  static List<int> _pbkdf2(List<int> password, List<int> salt, int iterations, int dkLen) {
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

  static String _encrypt(List<int> payload, List<int> kek) {
    final key = JsonWebKey.fromJson({'kty': 'oct', 'k': base64UrlEncode(kek)});
    final builder = JsonWebEncryptionBuilder()
      ..encryptionAlgorithm = contentAlg
      ..addRecipient(key, algorithm: 'dir')
      ..content = payload;
    return builder.build().toCompactSerialization();
  }

  static Future<Map<String, dynamic>> _decrypt(String jwe, List<int> kek) async {
    final key = JsonWebKey.fromJson({'kty': 'oct', 'k': base64UrlEncode(kek)});
    final parsed = JsonWebEncryption.fromCompactSerialization(jwe);
    final payload = await parsed.getPayload(JsonWebKeyStore()..addKey(key));
    final decoded = jsonDecode(String.fromCharCodes(payload.data));
    if (decoded is! Map<String, dynamic>) {
      throw const BackupCryptoError('解密结果不是有效的配置', BackupCryptoErrorKind.corrupt);
    }
    return decoded;
  }
}
