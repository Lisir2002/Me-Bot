import 'dart:convert';

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
    final event = <String, String>{
      't': DateTime.now().toIso8601String(),
      'a': action,
      'g': target,
      'ok': ok ? '1' : '0',
      if (detail != null) 'd': detail,
    };
    _buffer = <Map<String, String>>[event, ..._buffer];
    if (_buffer.length > maxEvents) {
      _buffer = _buffer.sublist(0, maxEvents);
    }
    // 持久化失败不致命（审计主通道是 Logger 日志）。
    () async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(
            _kEvents, _buffer.map(jsonEncode).toList());
      } catch (_) {}
    }();
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
  });

  factory AuditEvent.fromMap(Map<String, String> m) => AuditEvent(
        time: DateTime.tryParse(m['t'] ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
        action: m['a'] ?? '?',
        target: m['g'] ?? '?',
        ok: m['ok'] != '0',
        detail: m['d'],
      );

  final DateTime time;
  final String action;
  final String target;
  final bool ok;
  final String? detail;
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
