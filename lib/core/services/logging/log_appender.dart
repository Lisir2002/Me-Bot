
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:collection';
import 'dart:io';

import '../../../utils/app_directories.dart';
import 'log_level.dart';
import 'log_record.dart';
import 'log_sanitizer.dart';

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

  /// 轮转归档保留份数（当前文件超限时归档为 .1，旧的 .1→.2 …）。
  final int maxRotatedFiles;

  /// 测试可注入的日志目录；为 null 时走 AppDirectories 默认目录。
  final Directory? logDirOverride;

  FileAppender({
    this.maxFileBytes = 5 * 1024 * 1024,
    this.maxAgeDays = 7,
    this.flushIntervalMs = 500,
    this.maxRotatedFiles = 5,
    this.logDirOverride,
  });

  @override
  bool shouldAccept(LogRecord record) => record.level.ordinal >= minLevel.ordinal;

  @override
  Future<void> init() async {
    // 允许注入目录（测试用），否则走平台默认 App 数据目录
    final override = logDirOverride;
    if (override != null) {
      _logDir = override;
    } else {
      _logDir = Directory('${(await AppDirectories.getAppDataDirectory()).path}/logs');
    }
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
      // 超限先轮转归档（当前文件 → .1，旧的依次后移），不再直接覆盖丢历史
      await _rotateIfNeeded(file);
      await file.writeAsString(text, mode: FileMode.append);
    } catch (e) {
      // FileAppender 自己兜底，不向上抛（避免 Logger 崩溃）
      // ignore: avoid_print
      debugPrint('[FileAppender] write failed: $e');
    }
  }

  /// 当前文件超过 [maxFileBytes] 时执行轮转归档。
  ///
  /// 文件名：`log-YYYY-MM-DD.log` → 归档为 `log-YYYY-MM-DD.log.1`，
  /// 已有的 `.1` 变 `.2`，……，最老的 `.maxRotatedFiles` 被删除。
  /// 轮转失败时 fallback 到直接覆盖，绝不抛到上层。
  Future<void> _rotateIfNeeded(File file) async {
    try {
      if (!await file.exists()) return;
      if (await file.length() <= maxFileBytes) return;

      final base = file.path; // .../log-YYYY-MM-DD.log
      // 1) 删掉最老的一份，给滚动腾位置
      final oldest = File('$base.$maxRotatedFiles');
      if (await oldest.exists()) await oldest.delete();
      // 2) 从大到小依次后移：.1→.2、.2→.3 … 这样 .1 的槽位被空出
      for (int i = maxRotatedFiles - 1; i >= 1; i--) {
        final src = File('$base.$i');
        if (await src.exists()) {
          await src.rename('$base.${i + 1}');
        }
      }
      // 3) 当前文件归档为 .1
      await file.rename('$base.1');
    } catch (e) {
      // 边界/IO 异常兜底：轮转失败就退化成覆盖，不能让日志链路崩溃
      debugPrint('[FileAppender] rotate failed, fallback to overwrite: $e');
      try {
        await file.writeAsString(
          '--- 轮转失败，日志已重置 ---\n',
          mode: FileMode.write,
        );
      } catch (_) {
        // 连覆盖都失败就静默，避免影响主流程
      }
    }
  }

  Future<void> _cleanupOldLogs() async {
    final dir = _logDir;
    if (dir == null || !await dir.exists()) return;
    final cutoff = DateTime.now().subtract(Duration(days: maxAgeDays));
    final rotatedRe = RegExp(r'\.log\.\d+$'); // 匹配 .log.1 / .log.2 …
    await for (final ent in dir.list(followLinks: false)) {
      if (ent is! File) continue;
      // 主文件以 .log 结尾；轮转归档是 .log.N；其余（如临时文件）忽略
      final isMain = ent.path.endsWith('.log');
      final isRotated = rotatedRe.hasMatch(ent.path);
      if (!isMain && !isRotated) continue;
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

      // 关键：error 和 stack 必须再脱敏一次（Logger 可能漏了某些来源）
      if (r.error != null) {
        final safeMsg = LogSanitizer.safeErrorString(r.error);
        buf.writeln('  ${r.error.runtimeType}: $safeMsg');
      }
      final safeStack = LogSanitizer.safeStackPreview(r.stack);
      if (safeStack != null) {
        buf.writeln('  ── stack trace ──');
        buf.write(safeStack);
      }

      // traceId / context 附加（未来可能用得上，先留着）
      if (r.traceId != null) {
        buf.writeln('  traceId: ${r.traceId}');
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
