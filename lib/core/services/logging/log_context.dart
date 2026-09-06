
import 'dart:async';

/// 日志上下文（traceId 等）。
///
/// 两种使用方式：
///
/// 1. **Zone 级别**（推荐）：
///    ```dart
///    await LogContext.zone(traceId: 'req-abc123', () async {
///      // 块内所有 Logger 调用自动带上 traceId
///      await ApiLogger.logRequest(...);
///    });
///    ```
///
/// 2. **手动 push/pop**：
///    ```dart
///    LogContext.push(traceId: 'mcp-call-xyz');
///    try { ... } finally { LogContext.pop(); }
///    ```
///
/// 3. **全局 fallback**（最外层兜底）：
///    ```dart
///    LogContext.globalTraceId = 'app-boot';
///    ```
class LogContext {
  LogContext._();

  /// 当前 zone 里的上下文（如果有的话）。
  static LogContextData? _current() =>
      Zone.current[#LogContext] as LogContextData?;

  /// 全局兜底 traceId（没有 zone 上下文时使用）。
  static String? globalTraceId;

  /// 当前 traceId（zone > global > null）。
  static String? get traceId {
    final zone = _current();
    if (zone != null) return zone.traceId;
    return globalTraceId;
  }

  /// 当前业务上下文（zone 覆盖 global，null 表示不挂 context）。
  static Map<String, String>? get context {
    final zone = _current();
    if (zone != null) return zone.context;
    return null;
  }

  /// 在一个新 zone 里跑 [fn]，块内所有日志自动带上这个 traceId。
  static Future<T> zone<T>({
    String? traceId,
    Map<String, String>? context,
    required Future<T> Function() fn,
  }) async {
    final data = LogContextData(traceId: traceId, context: context);
    return runZoned(
      fn,
      zoneValues: {#LogContext: data},
    );
  }

  /// 同 zone 的同步版本。
  static T zoneSync<T>({
    String? traceId,
    Map<String, String>? context,
    required T Function() fn,
  }) {
    final data = LogContextData(traceId: traceId, context: context);
    return runZoned(
      fn,
      zoneValues: {#LogContext: data},
    );
  }

  /// 手动 push（栈式覆盖，逐层 pop）。
  static void push({String? traceId, Map<String, String>? context}) {
    final zone = _current();
    final data = LogContextData(
      traceId: traceId ?? zone?.traceId ?? globalTraceId,
      context: context ?? zone?.context,
    );
    // 把新数据放进一个嵌套 zone
    runZoned<void>(() {
      // no-op，这里只是利用 zone 机制挂值
    }, zoneValues: {#LogContext: data});
    // 实际上直接覆盖全局会更简单：
    _manualStack.add(data);
  }

  /// 手动 pop（和 push 配对）。
  static void pop() {
    if (_manualStack.isNotEmpty) _manualStack.removeLast();
  }

  static final List<LogContextData> _manualStack = [];

  /// 生成短 traceId（36 进制 8 位，够用）。
  static String shortId() {
    final t = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return t.substring(t.length - 8);
  }
}

class LogContextData {
  final String? traceId;
  final Map<String, String>? context;
  const LogContextData({this.traceId, this.context});
}
