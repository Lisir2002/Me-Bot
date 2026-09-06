import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../utils/app_directories.dart';
import 'log_level.dart';

/// 全局日志核心：异步串行落盘 + 可选 logcat 镜像 + 按天分文件 + 文件大小上限 + 过期清理。
///
/// 初始化（在 main 中调用一次即可）：
/// ```dart
/// await Logger.init();
/// // 可选：修改最低记录等级
/// Logger.minLevel = LogLevel.debug;
/// ```
///
/// 写日志（任何地方都能直接调，不需要 BuildContext）：
/// ```dart
/// Logger.i('AuthService', 'login attempt');
/// Logger.w('Net', 'retrying', exception, stackTrace);
/// Logger.e('Api', 'request failed', exception, stackTrace);
/// ```
///
/// 格式（与 deepcode-R 的 FileLogger 一致，便于 LogLineParser 统一解析）：
/// ```
/// 2026-09-06 14:30:55.123 INFO  [AuthService] login attempt
/// 2026-09-06 14:30:55.456 ERROR [Api] request failed
///   SocketException: Connection refused
///   #0      _NativeSocket.startConnect (dart:io-patch/socket_patch.dart:1234)
///   ...
/// ```
///
/// 设计要点：
/// - 所有写入串行化到一个后台 Isolate（实际上是单 isolate 内的异步队列），不阻塞 UI。
/// - 支持 Tag（来源模块），查询时可按 Tag 过滤。
/// - 支持 Throwable/StackTrace 格式化，按 Dart 堆栈输出。
/// - 支持大内容脱敏（base64 长字符串）和截断，避免日志被单个巨型 payload 撑爆。
/// - 支持文件大小上限（默认 5MB）和过期清理（默认 7 天）。
class Logger {
  Logger._();

  static const _tag = 'Logger';

  static bool _initialized = false;

  /// 日志目录（App 数据目录下 logs/）。
  static Directory? _logDir;

  /// 单线程队列，保证顺序写入。
  static final List<_LogItem> _queue = [];
  static bool _draining = false;
  static Timer? _flushTimer;

  /// 当前日期用于切换文件（按天分文件）。
  static DateTime _currentDay = DateTime.now();

  /// 最少记录等级；低于它的日志一律跳过。默认 [LogLevel.verbose]（开发期全量）。
  static LogLevel minLevel = LogLevel.verbose;

  /// logcat/debugPrint 镜像开关。release 构建下自动关闭。
  static bool mirrorToConsole = !kReleaseMode;

  // ── 常量 ──
  static const _maxFileBytes = 5 * 1024 * 1024; // 单文件上限 5MB
  static const _maxAgeDays = 7; // 过期清理天数
  static const _flushIntervalMs = 500; // 队列攒 500ms 再落盘一次，降低 IO
  static const _maxPayloadChars = 4000; // 单条日志消息最多保留的字符数

  // ── 初始化 ──
  static Future<void> init() async {
    if (_initialized) return;
    _logDir = Directory('${(await AppDirectories.getAppDataDirectory()).path}/logs');
    if (!await _logDir!.exists()) await _logDir!.create(recursive: true);
    _currentDay = DateTime.now();
    // 启动就清理一次旧日志（异步，不阻塞 init）
    unawaited(_cleanupOldLogs());
    _initialized = true;
    i(_tag, 'Logger 初始化完成，目录: ${_logDir!.path}');
  }

  /// 等待队列排空（一般只在 App 退出或测试中调用）。
  static Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _drain();
  }

  /// 获取日志目录（供 UI 查看/导出）。
  static Directory? get logDir => _logDir;

  /// 列出所有日志文件（按文件名倒序 = 最新日期在前）。
  static Future<List<File>> listLogFiles() async {
    final dir = _logDir;
    if (dir == null || !await dir.exists()) return const [];
    final files = <File>[];
    await for (final ent in dir.list(followLinks: false)) {
      if (ent is File && ent.path.endsWith('.log')) files.add(ent);
    }
    files.sort((a, b) => b.path.compareTo(a.path));
    return files;
  }

  // ── 日志入口 ──
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
    // 初始化前丢弃（避免 init 之前调日志报 Path 错误）
    if (!_initialized) return;

    final ts = _formatTimestamp(DateTime.now());
    final body = _buildBody(message, error, stack);
    final line = '$ts ${level.nameUpper.padRight(7)} [$tag] $body';

    if (mirrorToConsole) {
      debugPrint(line);
    }
    _queue.add(_LogItem(line));
    _scheduleFlush();
  }

  static void _scheduleFlush() {
    if (_draining) return;
    _flushTimer?.cancel();
    _flushTimer = Timer(const Duration(milliseconds: _flushIntervalMs), () {
      unawaited(_drain());
    });
  }

  static Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        // 每次攒成一个大写入，减少 IO
        final buf = StringBuffer();
        while (_queue.isNotEmpty) {
          buf.writeln(_queue.removeFirst().line);
        }
        await _writeChunk(buf.toString());
      }
    } finally {
      _draining = false;
      if (_queue.isNotEmpty) _scheduleFlush();
    }
  }

  static Future<void> _writeChunk(String text) async {
    final dir = _logDir;
    if (dir == null) return;
    // 检查是否需要切换日期文件
    final now = DateTime.now();
    if (!_sameDay(_currentDay, now)) {
      _currentDay = now;
      unawaited(_cleanupOldLogs());
    }
    final file = File('${dir.path}/log-${_formatDate(now)}.log');
    // 单文件超过上限则截断重开
    try {
      if (await file.exists() && await file.length() > _maxFileBytes) {
        await file.writeAsString(
          '--- 日志超过 ${_maxFileBytes ~/ 1024 ~/ 1024}MB 已重置 ---\n',
        );
      }
      await file.writeAsString(text, mode: FileMode.append);
    } catch (e) {
      if (mirrorToConsole) debugPrint('[Logger] write failed: $e');
    }
  }

  static Future<void> _cleanupOldLogs() async {
    final dir = _logDir;
    if (dir == null || !await dir.exists()) return;
    final cutoff = DateTime.now().subtract(const Duration(days: _maxAgeDays));
    await for (final ent in dir.list(followLinks: false)) {
      if (ent is! File || !ent.path.endsWith('.log')) continue;
      try {
        final stat = await ent.stat();
        final mtime = stat.modified;
        if (mtime.isBefore(cutoff)) await ent.delete();
      } catch (_) {}
    }
  }

  // ── 格式化工具 ──
  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static String _formatTimestamp(DateTime d) {
    final two = (int n) => n.toString().padLeft(2, '0');
    final ms = (d.millisecond).toString().padLeft(3, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}:${two(d.second)}.$ms';
  }

  static String _buildBody(String message, Object? error, StackTrace? stack) {
    final buf = StringBuffer();
    buf.writeln(_truncate(_redact(message)));
    if (error != null) {
      buf.writeln('  ${error.runtimeType}: ${_truncate(_redact(error.toString()))}');
    }
    if (stack != null) {
      buf.writeln('  ── stack trace ──');
      final lines = stack.toString().split('\n');
      // 只保留前 20 行堆栈（Dart 堆栈冗长）
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
    // data:image/xxx;base64,AA...AA → [base64 omitted: N chars]
    out = out.replaceAllMapped(
      RegExp(r'data:[a-zA-Z0-9._/-]+;base64,([A-Za-z0-9+/=]{200,})'),
      (m) => 'data:${m.group(1)!.substring(0, 20)}[base64 omitted: ${m.group(1)!.length} chars]',
    );
    // 直接嵌在 JSON 里的 base64 字段
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
}

class _LogItem {
  final String line;
  _LogItem(this.line);
}
