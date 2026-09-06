
import 'dart:async';
import 'dart:collection';
import 'dart:io';

import '../../../utils/app_directories.dart';
import 'log_level.dart';
import 'log_record.dart';

/// 日志输出目标（Appender）。
///
/// [Logger] 把 [LogRecord] 分发给所有已注册的 Appender，
/// 每个 Appender 可以有自己的等级过滤、缓冲、持久化策略。
///
/// 未来扩展方向：
/// - `RemoteAppender`：上传到服务端做聚合分析
/// - `CrashAppender`：ERROR 以上单独落 crash-*.log 目录
/// - `MetricsAppender`：抽 error rate / 耗时分布做监控
abstract class LogAppender {
  const LogAppender();

  /// Appender 名称（调试用）。
  String get name;

  /// 是否接受这条记录。通常按 level 过滤即可。
  bool shouldAccept(LogRecord record);

  /// 接收一条记录。实现可以缓冲、异步写入、drop 低等级。
  void append(LogRecord record);

  /// Appender 生命周期：Logger.init() 时调用。
  Future<void> init() async {}

  /// 队列排空 / flush。App 退出前调用。
  Future<void> flush() async {}

  /// 资源释放（一般不需要）。
  Future<void> dispose() async {}
}

// ──────────────────────────────────────────────
//  文件 Appender（现有 Logger 的落盘逻辑整体搬过来）
// ──────────────────────────────────────────────

class FileAppender extends LogAppender {
  @override
  String get name => 'FileAppender';

  /// 日志目录（App 数据目录下 logs/）。
  Directory? _logDir;

  /// 日志目录（init 后可用）。
  Directory? get logDir => _logDir;

  /// 当前日期用于切换文件。
  DateTime _currentDay = DateTime.now();

  /// 每个 Appender 独立的等级阈值，低于它的记录一律丢弃。
  LogLevel minLevel = LogLevel.verbose;

  /// 后台队列（用 Queue，removeFirst O(1)）。
  final Queue<LogRecord> _queue = Queue<LogRecord>();
  bool _draining = false;
  Timer? _flushTimer;

  // ── 常量（可通过构造参数覆盖）──
  final int maxFileBytes;
  final int maxAgeDays;
  final int flushIntervalMs;

  FileAppender({
    this.maxFileBytes = 5 * 1024 * 1024,
    this.maxAgeDays = 7,
    this.flushIntervalMs = 500,
  });

  @override
  bool shouldAccept(LogRecord record) => record.level.ordinal >= minLevel.ordinal;

  @override
  Future<void> init() async {
    _logDir = Directory('${(await AppDirectories.getAppDataDirectory()).path}/logs');
    if (!await _logDir!.exists()) await _logDir!.create(recursive: true);
    _currentDay = DateTime.now();
    unawaited(_cleanupOldLogs());
  }

  @override
  void append(LogRecord record) {
    if (!shouldAccept(record)) return;
    if (_logDir == null) return; // init 前丢弃
    _queue.add(record);
    _scheduleFlush();
  }

  void _scheduleFlush() {
    if (_draining) return;
    _flushTimer?.cancel();
    _flushTimer = Timer(Duration(milliseconds: flushIntervalMs), () {
      unawaited(_drain());
    });
  }

  @override
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    await _drain();
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        final buf = StringBuffer();
        while (_queue.isNotEmpty) {
          // 攒批写入，一次 IO
          final r = _queue.removeFirst();
          buf.writeln(_serialize(r));
        }
        await _writeChunk(buf.toString());
      }
    } finally {
      _draining = false;
      if (_queue.isNotEmpty) _scheduleFlush();
    }
  }

  Future<void> _writeChunk(String text) async {
    final dir = _logDir;
    if (dir == null) return;
    final now = DateTime.now();
    if (!_sameDay(_currentDay, now)) {
      _currentDay = now;
      unawaited(_cleanupOldLogs());
    }
    final file = File('${dir.path}/log-${_formatDate(now)}.log');
    try {
      if (await file.exists() && await file.length() > maxFileBytes) {
        await file.writeAsString(
          '--- 日志超过 ${maxFileBytes ~/ 1024 ~/ 1024}MB 已重置 ---\n',
        );
      }
      await file.writeAsString(text, mode: FileMode.append);
    } catch (e) {
      // FileAppender 自己兜底，不向上抛（避免 Logger 崩溃）
      // ignore: avoid_print
      debugPrint('[FileAppender] write failed: $e');
    }
  }

  Future<void> _cleanupOldLogs() async {
    final dir = _logDir;
    if (dir == null || !await dir.exists()) return;
    final cutoff = DateTime.now().subtract(Duration(days: maxAgeDays));
    await for (final ent in dir.list(followLinks: false)) {
      if (ent is! File || !ent.path.endsWith('.log')) continue;
      try {
        if ((await ent.stat()).modified.isBefore(cutoff)) await ent.delete();
      } catch (_) {}
    }
  }

  // ── 序列化：LogRecord → 纯文本（保持与 LogParser 兼容）──
  //
  // 格式：
  //   2026-09-06 14:30:55.123 INFO    [ApiReq] REQUEST ...
  //     error: SocketException
  //     ── stack trace ──
  //     #0 ...
  String _serialize(LogRecord r) {
    final two = (int n) => n.toString().padLeft(2, '0');
    final ms = r.timestamp.millisecond.toString().padLeft(3, '0');
    final ts = '${r.timestamp.year}-${two(r.timestamp.month)}-${two(r.timestamp.day)} '
        '${two(r.timestamp.hour)}:${two(r.timestamp.minute)}:${two(r.timestamp.second)}.$ms';

    final levelStr = r.level.nameUpper.padRight(7);
    final tagPart = '[${r.tag}]';

    final buf = StringBuffer();
    buf.writeln('$ts $levelStr $tagPart ${r.message}');

    if (r.error != null) {
      buf.writeln('  ${r.error.runtimeType}: ${r.error}');
    }
    if (r.stack != null) {
      buf.writeln('  ── stack trace ──');
      final lines = r.stack.toString().split('\n');
      // 只保留前 20 行（Dart 堆栈冗长）
      for (var i = 0; i < lines.length && i < 20; i++) {
        buf.writeln('  ${lines[i]}');
      }
    }
    return buf.toString().trimRight();
  }

  // ── 工具 ──
  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}

// ──────────────────────────────────────────────
//  内存 Appender（环形缓冲，供 UI 实时预览 / 加速查询）
// ──────────────────────────────────────────────

class MemoryAppender extends LogAppender {
  @override
  String get name => 'MemoryAppender';

  final int capacity;
  final LogLevel minLevel;

  /// 环形缓冲（按时间升序，最新在末尾）。
  final List<LogRecord> _records = [];
  final int _capacity;

  MemoryAppender({
    this.capacity = 500,
    this.minLevel = LogLevel.verbose,
  }) : _capacity = capacity;

  @override
  bool shouldAccept(LogRecord record) => record.level.ordinal >= minLevel.ordinal;

  @override
  void append(LogRecord record) {
    if (!shouldAccept(record)) return;
    _records.add(record);
    if (_records.length > _capacity) {
      // O(1) 头部丢弃
      _records.removeRange(0, _records.length - _capacity);
    }
  }

  /// 取出最近 N 条（默认全量倒序 = 最新在前）。
  List<LogRecord> recent({int? limit}) {
    final list = List<LogRecord>.unmodifiable(_records);
    final reversed = List<LogRecord>.from(list.reversed);
    if (limit != null && limit < reversed.length) return reversed.sublist(0, limit);
    return reversed;
  }

  /// 按 tag 过滤。
  List<LogRecord> byTag(String tag, {int? limit}) {
    final list = recent().where((r) => r.tag == tag).toList();
    if (limit != null && limit < list.length) return list.sublist(0, limit);
    return list;
  }

  /// 按 traceId 过滤（整条调用链一起拉出来）。
  List<LogRecord> byTrace(String traceId) {
    return _records.where((r) => r.traceId == traceId).toList();
  }

  /// 清空。
  void clear() => _records.clear();

  /// 长度。
  int get length => _records.length;
}
