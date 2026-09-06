
import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'logger.dart';
import 'log_level.dart';

/// 单条解析好的日志记录。
class ParsedLogLine {
  final DateTime timestamp;
  final LogLevel level;
  final String tag;
  final String body; // 主消息部分（含堆栈等附属行）
  const ParsedLogLine({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.body,
  });

  static final _empty = ParsedLogLine(
    timestamp: DateTime.fromMillisecondsSinceEpoch(0),
    level: LogLevel.info,
    tag: '(unknown)',
    body: '',
  );

  factory ParsedLogLine.empty() => _empty;
}

/// 日志行解析工具。
///
/// Logger 输出格式：
/// ```
/// 2026-09-06 14:30:55.123 INFO    [AuthService] login attempt
///   附属行（堆栈等）
/// ```
///
/// 不匹配该格式的行（如堆栈行、分隔线、reset 提示）自动归并到上一条记录。
class LogParser {
  // 2026-09-06 14:30:55.123 INFO    [AuthService] message
  static final _mainLine = RegExp(
    r'^(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\.(\d{3})\s+(VERBOSE|DEBUG|INFO|WARN|ERROR)\s+\[([^\]]+)\]\s+(.*)$',
  );

  static ParsedLogLine? tryParse(String line) {
    final m = _mainLine.firstMatch(line);
    if (m == null) return null;
    final date = m.group(1)!;
    final time = m.group(2)!;
    final ms = int.tryParse(m.group(3)!) ?? 0;
    final levelStr = m.group(4)!;
    final tag = m.group(5)!;
    final message = m.group(6)!;

    final dt = DateTime.tryParse('${date}T${time}Z')?.toLocal() ?? DateTime.now();
    final withMs = DateTime(
      dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second, ms,
    );

    final level = switch (levelStr) {
      'VERBOSE' => LogLevel.verbose,
      'DEBUG' => LogLevel.debug,
      'INFO' => LogLevel.info,
      'WARN' => LogLevel.warn,
      'ERROR' => LogLevel.error,
      _ => LogLevel.info,
    };

    return ParsedLogLine(
      timestamp: withMs,
      level: level,
      tag: tag,
      body: message,
    );
  }

  /// 完整解析一个日志文件，把附属行合并到主记录。
  static List<ParsedLogLine> parseFile(File file) {
    final out = <ParsedLogLine>[];
    ParsedLogLine? current;
    try {
      for (final raw in file.readAsLinesSync()) {
        final parsed = tryParse(raw);
        if (parsed != null) {
          if (current != null) out.add(current);
          current = parsed;
        } else {
          // 附属行（堆栈、错误消息 continuation）
          if (current != null) {
            current = ParsedLogLine(
              timestamp: current.timestamp,
              level: current.level,
              tag: current.tag,
              body: '${current.body}\n$raw',
            );
          }
        }
      }
      if (current != null) out.add(current);
    } catch (_) {}
    return out;
  }

  /// 从多行文本直接解析（供内存缓冲区使用）。
  static List<ParsedLogLine> parseText(String text) {
    final out = <ParsedLogLine>[];
    ParsedLogLine? current;
    final lines = text.split('\n');
    for (final raw in lines) {
      final parsed = tryParse(raw);
      if (parsed != null) {
        if (current != null) out.add(current);
        current = parsed;
      } else {
        if (current != null) {
          current = ParsedLogLine(
            timestamp: current.timestamp,
            level: current.level,
            tag: current.tag,
            body: '${current.body}\n$raw',
          );
        }
      }
    }
    if (current != null) out.add(current);
    return out;
  }

  /// 从一组记录里提取所有出现过的 Tag（去重、按首现顺序）。
  static List<String> extractTags(List<ParsedLogLine> records) {
    final seen = <String>{};
    final out = <String>[];
    for (final r in records) {
      if (seen.add(r.tag)) out.add(r.tag);
    }
    return out;
  }

  /// 把 Tag / Level 筛选条件序列化成 JSON（供持久化）。
  static String serializeFilter({Set<LogLevel>? levels, Set<String>? tags}) =>
      jsonEncode({
        'levels': levels?.map((l) => l.name).toList() ?? const [],
        'tags': tags?.toList() ?? const [],
      });

  static Map<String, dynamic> deserializeFilter(String raw) {
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final levels = (map['levels'] as List? ?? const [])
          .map((s) => LogLevel.values.firstWhere((l) => l.name == s, orElse: () => LogLevel.info))
          .toSet();
      final tags = (map['tags'] as List? ?? const []).map((s) => s.toString()).toSet();
      return {'levels': levels, 'tags': tags};
    } catch (_) {
      return {'levels': <LogLevel>{}, 'tags': <String>{}};
    }
  }
}
