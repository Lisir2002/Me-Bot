import 'dart:async';

/// 日志上下文（traceId / context KV）。
///
/// ## 优先级链（从高到低）
/// ```
/// manualStack（push 进来的） → zone（zoneValues）→ globalTraceId / globalContext
/// ```
///
/// zone 里 **null 值不再吞掉上层** —— 如果 zone 有 traceId=null，
/// 会自动 fallback 到 global。只有 **显式传了非 null 值** 才会覆盖上层。
///
/// ## 推荐用法
///
/// 1. **Zone 级别**（最干净，自动穿透异步）：
///    ```dart
///    await LogContext.zone(traceId: 'req-abc123', () async {
///      // 块内所有 Logger 调用自动带上 traceId
///      await ApiLogger.logRequest(...);
///    });
///    ```
///
/// 2. **手动 push/pop**（不依赖 zone，try-finally 保证配对）：
///    ```dart
///    LogContext.push(traceId: 'mcp-call-xyz');
///    try { ... } finally { LogContext.pop(); }
///    ```
///
/// 3. **全局兜底**（最外层，最不推荐但必要时用）：
///    ```dart
///    LogContext.globalTraceId = 'app-boot';
///    ```
class LogContext {
  LogContext._();

  // ── 全局兜底 ──
  static String? globalTraceId;
  static Map<String, String>? globalContext;

  // ── 手动栈（push/pop）──
  static final List<LogContextData> _manualStack = [];

  // ── 读取 zone ──
  static LogContextData? _fromZone() {
    final z = Zone.current[#LogContext];
    return z is LogContextData ? z : null;
  }

  /// 当前 traceId（manualStack.top → zone.traceId 非null → globalTraceId）。
  static String? get traceId {
    // 1. 手动栈顶优先
    if (_manualStack.isNotEmpty) {
      final top = _manualStack.last;
      if (top.traceId != null) return top.traceId;
    }
    // 2. zone —— 只覆盖非 null 值（zone 有 null 不吞掉 global）
    final zone = _fromZone();
    if (zone != null && zone.traceId != null) return zone.traceId;
    // 3. global 兜底
    return globalTraceId;
  }

  /// 当前业务 context（合并链：global ← zone(覆盖非null) ← manual(覆盖非null)）。
  /// 返回**合并后的完整 Map**（而不是只返回某一层的），方便统一序列化。
  static Map<String, String>? get context {
    final buf = <String, String>{};
    // 最底层：global
    if (globalContext != null) buf.addAll(globalContext!);
    // 中间：zone 覆盖非 null 的 key
    final zone = _fromZone();
    if (zone != null && zone.context != null) {
      buf.addAll(zone.context!);
    }
    // 最顶层：manualStack 从底往上叠（后来的覆盖前面的）
    for (final layer in _manualStack) {
      if (layer.context != null) buf.addAll(layer.context!);
    }
    return buf.isEmpty ? null : buf;
  }

  // ── Zone 封装 ──

  /// 在一个新 zone 里跑 [fn]，块内所有日志自动带上这个 traceId / context。
  ///
  /// **不传的字段（传 null）不会覆盖全局** —— 这是与旧版的关键区别。
  static Future<T> zone<T>({
    String? traceId,
    Map<String, String>? context,
    required Future<T> Function() fn,
  }) async {
    final data = LogContextData(traceId: traceId, context: context);
    // runZoned 的 body 签名是 Z Function()，显式让 Z = Future<T>
    return runZoned<Future<T>>(
      () async => await fn(),
      zoneValues: {#LogContext: data},
    );
  }

  /// 同步版本。
  static T zoneSync<T>({
    String? traceId,
    Map<String, String>? context,
    required T Function() fn,
  }) {
    final data = LogContextData(traceId: traceId, context: context);
    return runZoned<T>(
      fn,
      zoneValues: {#LogContext: data},
    );
  }

  // ── 手动 push/pop ──

  /// 手动 push 一层（不依赖 zone）。
  /// null 值不会覆盖上层（会自动 fallback）。
  static void push({String? traceId, Map<String, String>? context}) {
    // 解析继承：如果当前已经有值，就继承下来（这样 null 就变成"不覆盖"）
    final inheritedTraceId = traceId ?? traceId /* 保持用户传入的 null */;
    final inheritedContext = context;

    _manualStack.add(LogContextData(
      traceId: inheritedTraceId, // null = 让 getter 自动 fallback
      context: inheritedContext,
    ));
  }

  /// 和 push 配对使用。try-finally 保证不会泄漏。
  static void pop() {
    if (_manualStack.isNotEmpty) {
      _manualStack.removeLast();
    }
  }

  // ── 工具 ──

  /// 生成短 traceId（36 进制 8 位，够用）。
  static String shortId() {
    final t = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return t.substring(t.length - 8);
  }

  /// 调试 dump（看当前上下文栈）。
  static String debugDump() {
    final buf = StringBuffer('[LogContext]\n');
    buf.writeln('  globalTraceId: $globalTraceId');
    buf.writeln('  globalContext: $globalContext');
    buf.writeln('  zone: ${_fromZone()}');
    buf.writeln('  manualStack (${_manualStack.length}):');
    for (var i = 0; i < _manualStack.length; i++) {
      buf.writeln('    [$i] ${_manualStack[i]}');
    }
    buf.writeln('  → resolved traceId: $traceId');
    buf.writeln('  → resolved context: $context');
    return buf.toString();
  }
}

class LogContextData {
  final String? traceId;
  final Map<String, String>? context;
  const LogContextData({this.traceId, this.context});

  @override
  String toString() => 'LogContextData(traceId=$traceId, context=$context)';
}
