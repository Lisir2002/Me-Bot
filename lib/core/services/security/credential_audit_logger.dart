import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../logging/logger.dart';
import '../logging/log_tags.dart';
import '../logging/log_context.dart';

/// 凭证操作审计（PR-5）。
///
/// 把「查看 / 复制 / 导出 / 迁移 / 解密」等敏感操作统一记到独立 [LogTags.security]
/// 通道，带 [LogContext.zone] 的 traceId，在既有日志查看器里可直接按标签过滤。
///
/// **同时**维护一份结构化审计事件（内存 ring buffer + SharedPreferences 持久化，
/// 上限 [maxEvents] 条），供「安全中心 → 最近安全事件」直接展示——
/// 审计日志如果只能去日志文件里翻，对用户来说等于不存在。
///
/// 铁律：任何审计事件都**不携带凭证明文值**——只记录操作名、对象类别、结果。
/// 因此这里的方法签名里永远看不到 value。
class CredentialAuditLogger {
  CredentialAuditLogger._();

  /// 凭证相关操作的类别（仅用于日志归类，不泄露内容）。
  static const String _scope = 'credential';

  static const String _kEvents = 'audit_events';
  static const int maxEvents = 100;

  /// 创世哈希：链上第一条事件的 [prevHash] 固定为 64 个 0（SHA-256 位宽）。
  static const String _genesisPrevHash = '00000000000000000000000000000000'
      '00000000000000000000000000000000';

  static List<Map<String, String>> _buffer = <Map<String, String>>[];
  static bool _hydrated = false;

  /// 记录一次凭证操作（成功或失败都记，便于审计与排障）。
  ///
  /// [action] 见 [CredentialAuditAction]；[target] 是对象类别（如 'provider:openai'、
  /// 'backup:encrypted'、'migration:v1'），**不是明文值**；[ok]=false 时记 warn。
  static void record(
    String action,
    String target, {
    bool ok = true,
    String? detail,
    Object? error,
    StackTrace? stack,
  }) {
    final msg = '[$_scope] $action target=$target'
        '${ok ? '' : ' FAILED'}${detail != null ? ' ($detail)' : ''}';
    if (ok) {
      Logger.i(LogTags.security, msg, error, stack);
    } else {
      Logger.w(LogTags.security, msg, error, stack);
    }
    _appendEvent(action: action, target: target, ok: ok, detail: detail);
  }

  // ── 结构化事件（供安全中心展示）──

  static void _appendEvent({
    required String action,
    required String target,
    required bool ok,
    String? detail,
  }) {
    final t = DateTime.now().toIso8601String();
    final okStr = ok ? '1' : '0';
    // 链式哈希（P3-31）：新事件的 prevHash = 当前链头（_buffer.first，时间上的上一条）的哈希。
    // 旧数据没有 'h' 字段时视为空串，此时回落到创世哈希——旧事件本来就被 verifyChain 跳过。
    final prevHash = _buffer.isNotEmpty
        ? (_buffer.first['h']?.isNotEmpty == true ? _buffer.first['h']! : _genesisPrevHash)
        : _genesisPrevHash;
    final hash = _computeHash(t, action, target, okStr, detail, prevHash);

    final event = <String, String>{
      't': t,
      'a': action,
      'g': target,
      'ok': okStr,
      if (detail != null) 'd': detail,
      'p': prevHash, // prevHash
      'h': hash, // 当前事件哈希
    };
    _buffer = <Map<String, String>>[event, ..._buffer];
    if (_buffer.length > maxEvents) {
      _buffer = _buffer.sublist(0, maxEvents);
    }
    // 持久化失败不致命（审计主通道是 Logger 日志），但不能静默——
    // 否则 SharedPreferences 写入异常会被完全吞掉，无法排障。
    () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(
            _kEvents, _buffer.map(jsonEncode).toList());
      } catch (e, st) {
        Logger.e(LogTags.security, 'audit event persist failed action=$action target=$target', e, st);
      }
    }();
  }

  /// 对审计事件关键字段做 SHA-256，形成链式哈希（P3-31）。
  /// 输入固定为 `t|a|g|ok|d|prevHash` 的拼接串，字段缺失时 d 用空串占位，保证可复算。
  static String _computeHash(
    String t,
    String a,
    String g,
    String ok,
    String? d,
    String prevHash,
  ) {
    final input = '$t|$a|$g|$ok|${d ?? ''}|$prevHash';
    return sha256.convert(utf8.encode(input)).toString();
  }

  /// 校验整条审计链是否完整、未被篡改（P3-31）。
  ///
  /// 从最旧到最新遍历：
  /// - 跳过没有 `h` 字段的旧事件（兼容历史数据，不参与校验）；
  /// - 第一条带哈希的事件要求 prevHash 等于创世哈希；
  /// - 后续事件要求 prevHash 等于上一条带哈希事件的 h，且按字段重算的哈希与存值一致。
  /// 任一不满足即返回 false。空链 / 无任何带哈希事件时返回 true（无可校验内容）。
  static Future<bool> verifyChain() async {
    if (!_hydrated) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getStringList(_kEvents) ?? const [];
        _buffer = raw
            .map((s) {
              try {
                final m = jsonDecode(s) as Map<String, dynamic>;
                return m.map((k, v) => MapEntry(k, v?.toString() ?? ''));
              } catch (_) {
                return <String, String>{};
              }
            })
            .where((m) => m.isNotEmpty)
            .toList();
      } catch (_) {
        _buffer = <Map<String, String>>[];
      }
      _hydrated = true;
    }

    String? lastHash; // 上一条带哈希事件的 h（从旧到新推进）
    for (final m in _buffer.reversed) {
      final h = m['h'] ?? '';
      if (h.isEmpty) continue; // 旧数据：跳过，不参与链校验
      final prevHash = m['p'] ?? '';
      // prevHash 必须衔接：第一条带哈希的事件对创世哈希，否则接上一条的 h
      final expectedPrev = lastHash ?? _genesisPrevHash;
      if (prevHash != expectedPrev) return false;
      // 字段重算复核，防止 h 之外的字段被改
      final recomputed = _computeHash(
        m['t'] ?? '',
        m['a'] ?? '',
        m['g'] ?? '',
        m['ok'] ?? '',
        m['d'],
        prevHash,
      );
      if (recomputed != h) return false;
      lastHash = h;
    }
    return true;
  }

  /// 最近审计事件（新→旧），最多 [limit] 条。首次调用会从持久化层恢复。
  static Future<List<AuditEvent>> recent({int limit = 20}) async {
    if (!_hydrated) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getStringList(_kEvents) ?? const [];
        _buffer = raw
            .map((s) {
              try {
                final m = jsonDecode(s) as Map<String, dynamic>;
                return m.map((k, v) => MapEntry(k, v?.toString() ?? ''));
              } catch (_) {
                return <String, String>{};
              }
            })
            .where((m) => m.isNotEmpty)
            .toList();
      } catch (_) {
        _buffer = <Map<String, String>>[];
      }
      _hydrated = true;
    }
    return _buffer.take(limit).map(AuditEvent.fromMap).toList();
  }

  /// 清空审计事件（连同持久化）。清空本身也记一条。
  static Future<void> clear() async {
    _buffer = <Map<String, String>>[];
    _hydrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kEvents);
    } catch (_) {}
    record('clearAudit', 'audit:trail');
  }

  /// 仅供测试：清空内存态（不影响持久化）。
  static void resetForTest() {
    _buffer = <Map<String, String>>[];
    _hydrated = false;
  }

  /// 在一个带 traceId 的链路里执行 [task]，并把凭证操作审计自动带上同一 traceId。
  static Future<T> traced<T>(
    String traceId,
    Future<T> Function() task,
  ) =>
      LogContext.zone(traceId: traceId, fn: task);
}

/// 一条审计事件（不含任何凭证明文）。
class AuditEvent {
  const AuditEvent({
    required this.time,
    required this.action,
    required this.target,
    required this.ok,
    this.detail,
    this.hash = '',
    this.prevHash = '',
  });

  factory AuditEvent.fromMap(Map<String, String> m) => AuditEvent(
        time: DateTime.tryParse(m['t'] ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        action: m['a'] ?? '?',
        target: m['g'] ?? '?',
        ok: m['ok'] != '0',
        detail: m['d'],
        hash: m['h'] ?? '', // 旧数据无此字段 → 空串
        prevHash: m['p'] ?? '',
      );

  final DateTime time;
  final String action;
  final String target;
  final bool ok;
  final String? detail;

  /// 当前事件哈希（P3-31 链式）；旧事件为空串。
  final String hash;

  /// 上一条事件哈希；链首为创世哈希。旧事件为空串。
  final String prevHash;
}

/// 审计动作命名约定（与 [CredentialAuditLogger.record] 的 [action] 配套）。
abstract final class CredentialAuditAction {
  static const String view = 'view';
  static const String copy = 'copy';
  static const String export = 'export';
  static const String enterPassphrase = 'enterPassphrase';
  static const String migrate = 'migrate';
  static const String clearAudit = 'clearAudit';
}
