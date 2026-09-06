
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'log_appender.dart';
import 'log_context.dart';
import 'log_level.dart';
import 'log_record.dart';

/// 全局日志核心：结构化记录 + Appender 分发 + 控制台镜像。
///
/// ## 架构
///
/// ```
/// Logger.i(tag, msg, err, stack)
///         │
///         ▼
///     LogRecord  ── 脱敏 + 截断 ──► 分发到全部 Appender
///         │                             │
///         │                    ┌────────┼────────┐
///         │                    ▼        ▼        ▼
///         │              FileApp  MemoryApp  RemoteApp (未来)
///         │
///         ▼
///     debugPrint（可选镜像）
/// ```
///
/// ## 初始化
///
/// ```dart
/// await Logger.init();               // 默认注册 FileAppender + MemoryAppender
/// Logger.minLevel = LogLevel.debug;  // 可选
/// Logger.registerAppender(custom);  // 可选：挂自己的 Appender
/// ```
///
/// ## 调用（任何地方都能直接调，不需要 BuildContext）
///
/// ```dart
/// Logger.i('ApiReq', 'request /v1/chat');
/// Logger.e('Network', 'connection refused', exception, stackTrace);
/// ```
///
/// ## 链路追踪
///
/// ```dart
/// await LogContext.zone(traceId: 'req-abc123', () async {
///   // 块内所有 Logger 调用自动带上 traceId
/// });
/// ```
///
/// ## 格式
///
/// ```
/// 2026-09-06 14:30:55.123 INFO    [ApiReq] REQUEST ...
///   SocketException: Connection refused
///   ── stack trace ──
///   #0 ...
/// ```
class Logger {
  Logger._();

  static const _tag = 'Logger';

  static bool _initialized = false;

  // ── Appender 注册表 ──
  static final List<LogAppender> _appenders = [];

  /// 注册一个 Appender（init 之后也能动态加）。
  static void registerAppender(LogAppender app) {
    if (_appenders.any((a) => a.name == app.name)) return;
    _appenders.add(app);
    if (_initialized) unawaited(app.init());
  }

  /// 移除一个 Appender（按 name）。
  static void unregisterAppender(String name) {
    _appenders.removeWhere((a) => a.name == name);
  }

  /// 所有已注册 Appender（调试用）。
  static List<LogAppender> get appenders => List.unmodifiable(_appenders);

  // ── 控制台镜像开关 ──
  /// release 构建下默认关闭。
  static bool mirrorToConsole = !kReleaseMode;

  /// 最少记录等级；低于它的日志一律跳过（所有 Appender 的兜底阈值）。
  static LogLevel minLevel = LogLevel.verbose;

  // ── 便捷访问（FileAppender / MemoryAppender 是默认注册的，可以直接拿实例）──

  /// 最近注册的 FileAppender（如果有）。
  static FileAppender? get fileAppender {
    for (final a in _appenders) {
      if (a is FileAppender) return a;
    }
    return null;
  }

  /// 最近注册的 MemoryAppender（如果有）。
  static MemoryAppender? get memoryAppender {
    for (final a in _appenders) {
      if (a is MemoryAppender) return a;
    }
    return null;
  }

  /// 日志目录（供 UI 查看/导出）。
  static Directory? get logDir {
    return fileAppender != null ? _lazyLogDir : null;
  }

  static Directory? _lazyLogDir;

  // ── 常量 ──
  static const _maxPayloadChars = 4000; // 单条日志消息最多保留的字符数

  // ── 初始化 ──

  /// 初始化并注册默认 Appender（File + Memory）。
  static Future<void> init({
    LogLevel minLevel = LogLevel.verbose,
    bool mirrorToConsole = !kReleaseMode,
    int memoryCapacity = 500,
    int fileMaxBytes = 5 * 1024 * 1024,
    int fileMaxAgeDays = 7,
    int fileFlushIntervalMs = 500,
  }) async {
    if (_initialized) return;
    Logger.minLevel = minLevel;
    Logger.mirrorToConsole = mirrorToConsole;

    // 默认 FileAppender
    final fileApp = FileAppender(
      maxFileBytes: fileMaxBytes,
      maxAgeDays: fileMaxAgeDays,
      flushIntervalMs: fileFlushIntervalMs,
    );
    await fileApp.init();
    _appenders.add(fileApp);

    // 默认 MemoryAppender（环形缓冲）
    _appenders.add(MemoryAppender(capacity: memoryCapacity));

    // 缓存 logDir 供外部查询
    _lazyLogDir = fileApp.logDir;

    _initialized = true;

    // 自报家门（走一次完整的 append → 控制台镜像）
    _log(LogLevel.info, _tag, 'Logger 初始化完成（appenders=${_appenders.length}, dir=${_lazyLogDir?.path ?? 'N/A'}）', null, null);
  }

  /// 等待队列排空（App 退出前调用）。
  static Future<void> flush() async {
    for (final a in _appenders) {
      await a.flush();
    }
  }

  // ── 日志入口（静态 API，签名保持不变）──

  static void v(String tag, String message, [Object? error, StackTrace? stack]) =>
      _log(LogLevel.verbose, tag, message, error, stack);

  static void d(String tag, String message, [Object? error, StackTrace? stack]) =>
      _log(LogLevel.debug, tag, message, error, stack);

  static void i(String tag, String message, [Object? error, StackTrace? stack]) =>
      _log(LogLevel.info, tag, message, error, stack);

  static void w(String tag, String message, [Object? error, StackTrace? stack]) =>
      _log(LogLevel.warn, tag, message, error, stack);

  static void e(String tag, String message, [Object? error, StackTrace? stack]) =>
      _log(LogLevel.error, tag, message, error, stack);

  // ── 核心 ──

  static void _log(LogLevel level, String tag, String message, Object? error, StackTrace? stack) {
    if (level.ordinal < minLevel.ordinal) return;

    final timestamp = DateTime.now();
    final body = _buildBody(message, error, stack);

    // 控制台镜像（先算好文本行，保证和 FileAppender 的序列化一致）
    if (mirrorToConsole) {
      final two = (int n) => n.toString().padLeft(2, '0');
      final ms = timestamp.millisecond.toString().padLeft(3, '0');
      final ts = '${timestamp.year}-${two(timestamp.month)}-${two(timestamp.day)} '
          '${two(timestamp.hour)}:${two(timestamp.minute)}:${two(timestamp.second)}.$ms';
      final line = '$ts ${level.nameUpper.padRight(7)} [$tag] $body';
      debugPrint(line);
    }

    // 构造 LogRecord 并分发到所有 Appender
    final traceId = LogContext.traceId;
    final context = LogContext.context;

    final record = LogRecord(
      timestamp: timestamp,
      level: level,
      tag: tag,
      message: body,
      error: error,
      stack: stack,
      traceId: traceId,
      context: context,
    );

    for (final a in _appenders) {
      // init 前丢弃
      if (!_initialized && a is FileAppender) continue;
      try {
        a.append(record);
      } catch (e) {
        // 单个 Appender 崩了不能影响其他
        if (mirrorToConsole) debugPrint('[Logger] appender ${a.name} failed: $e');
      }
    }
  }

  // ── 构建 body（脱敏 + 截断 + 格式化堆栈）──

  static String _buildBody(String message, Object? error, StackTrace? stack) {
    final buf = StringBuffer();
    buf.writeln(_truncate(_redact(message)));
    if (error != null) {
      buf.writeln('  ${error.runtimeType}: ${_truncate(_redact(error.toString()))}');
    }
    if (stack != null) {
      buf.writeln('  ── stack trace ──');
      final lines = stack.toString().split('\n');
      for (var i = 0; i < lines.length && i < 20; i++) {
        buf.writeln('  ${lines[i]}');
      }
    }
    return buf.toString().trimRight();
  }

  /// 脱敏长 base64 字符串、超长 JSON、API key 字段。
  static String _redact(String text) {
    if (text.length < 200) return text;
    var out = text;
    out = out.replaceAllMapped(
      RegExp(r'data:[a-zA-Z0-9._/-]+;base64,([A-Za-z0-9+/=]{200,})'),
      (m) => 'data:${m.group(1)!.substring(0, 20)}[base64 omitted: ${m.group(1)!.length} chars]',
    );
    out = out.replaceAllMapped(
      RegExp(r'"([a-zA-Z_]+)"\s*:\s*"([A-Za-z0-9+/=]{200,})"'),
      (m) => '"${m.group(1)}": "[base64 omitted: ${m.group(2)!.length} chars]"',
    );
    return out;
  }

  static String _truncate(String text) {
    if (text.length <= _maxPayloadChars) return text;
    return '${text.substring(0, _maxPayloadChars)}\n  ... [truncated ${text.length - _maxPayloadChars} chars]';
  }

  // ── 文件级 API（委托给 FileAppender）──

  /// 列出所有日志文件（按文件名倒序 = 最新日期在前）。
  static Future<List<File>> listLogFiles() async {
    final dir = fileAppender?.logDir ?? _lazyLogDir;
    if (dir == null || !await dir.exists()) return const [];
    final files = <File>[];
    await for (final ent in dir.list(followLinks: false)) {
      if (ent is File && ent.path.endsWith('.log')) files.add(ent);
    }
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  // ── 调试 ──

  /// 当前 Logger 状态（dump 到 debugPrint）。
  static void dump() {
    final buf = StringBuffer('[Logger dump]\n');
    buf.writeln('  initialized=$_initialized');
    buf.writeln('  minLevel=${minLevel.name}');
    buf.writeln('  mirrorToConsole=$mirrorToConsole');
    buf.writeln('  appenders=${_appenders.length}');
    for (final a in _appenders) {
      buf.writeln('    - ${a.name}');
    }
    debugPrint(buf.toString());
  }
}
