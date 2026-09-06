import 'dart:io';

import 'log_level.dart';
import 'log_parser.dart';
import 'logger.dart';

/// 日志查询层：在 UI 层按等级 / Tag / 日期范围 过滤日志，做统计。
class LogRepository {
  LogRepository._();

  static final LogRepository instance = LogRepository._();

  /// 查询参数。
  final ({
    Set<LogLevel> levels, // 空集合=全等级
    Set<String> tags, // 空集合=全 Tag
    DateTime? from, // null=不限
    DateTime? to, // null=不限
    String? keyword, // null 或 '' = 不搜
  }) _noFilter = (
    levels: const {},
    tags: const {},
    from: null,
    to: null,
    keyword: null,
  );

  /// 加载所有日志文件、解析、按条件过滤并返回倒序（最新在前）列表。
  /// 传入 [limit] 时只返回前 N 条（UI 分页）。
  Future<List<ParsedLogLine>> query({
    Set<LogLevel> levels = const {},
    Set<String> tags = const {},
    DateTime? from,
    DateTime? to,
    String? keyword,
    int? limit,
  }) async {
    final dir = Logger.logDir;
    if (dir == null || !await dir.exists()) return const [];

    final buffer = <ParsedLogLine>[];
    final files = await Logger.listLogFiles();
    for (final f in files) {
      buffer.addAll(LogParser.parseFile(f));
    }

    // 过滤
    final kw = keyword?.trim();
    Iterable<ParsedLogLine> it = buffer;
    if (levels.isNotEmpty) it = it.where((r) => levels.contains(r.level));
    if (tags.isNotEmpty) it = it.where((r) => tags.contains(r.tag));
    if (from != null) it = it.where((r) => r.timestamp.isAfter(from));
    if (to != null) {
      final end = to.add(const Duration(days: 1));
      it = it.where((r) => r.timestamp.isBefore(end));
    }
    if (kw != null && kw.isNotEmpty) {
      it = it.where((r) {
        final hay = '${r.tag} ${r.body}'.toLowerCase();
        return hay.contains(kw.toLowerCase());
      });
    }

    final list = it.toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (limit != null && list.length > limit) return list.sublist(0, limit);
    return list;
  }

  /// 统计：每个 Tag 出现次数（全等级）。
  Future<Map<String, int>> countByTag() async {
    final all = await query();
    final map = <String, int>{};
    for (final r in all) {
      map[r.tag] = (map[r.tag] ?? 0) + 1;
    }
    return map;
  }

  /// 统计：每个等级出现次数（全 Tag）。
  Future<Map<LogLevel, int>> countByLevel() async {
    final all = await query();
    final map = <LogLevel, int>{};
    for (final r in all) {
      map[r.level] = (map[r.level] ?? 0) + 1;
    }
    return map;
  }

  /// 所有可用 Tag（去重、按首现顺序）。
  Future<List<String>> allTags() async {
    final all = await query();
    return LogParser.extractTags(all);
  }

  /// 所有可用等级（实际出现过的）。
  Future<Set<LogLevel>> allLevelsPresent() async {
    final all = await query();
    return all.map((r) => r.level).toSet();
  }

  /// 日志总大小（字节）。
  Future<int> totalBytes() async {
    final files = await Logger.listLogFiles();
    int bytes = 0;
    for (final f in files) {
      try {
        bytes += await f.length();
      } catch (_) {}
    }
    return bytes;
  }

  /// 删除所有日志文件。
  Future<int> clearAll() async {
    final files = await Logger.listLogFiles();
    int deleted = 0;
    for (final f in files) {
      try {
        await f.delete();
        deleted++;
      } catch (_) {}
    }
    return deleted;
  }

  /// 删除指定日期范围（按文件名匹配）。[before] 传 DateTime 时删除其之前的所有文件。
  Future<int> clearBefore(DateTime before) async {
    final files = await Logger.listLogFiles();
    int deleted = 0;
    for (final f in files) {
      final name = f.path.split(RegExp(r'[/\\]')).last;
      final m = RegExp(r'^log-(\d{4}-\d{2}-\d{2})\.log$').firstMatch(name);
      if (m == null) continue;
      final dt = DateTime.tryParse('${m.group(1)}T00:00:00Z');
      if (dt == null) continue;
      if (dt.isBefore(before)) {
        try {
          await f.delete();
          deleted++;
        } catch (_) {}
      }
    }
    return deleted;
  }
}
