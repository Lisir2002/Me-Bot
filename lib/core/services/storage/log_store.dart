import 'dart:io';

import '../../../utils/app_directories.dart';

/// 日志条目（供日志查看页展示）。
class LogEntry {
  final String title;
  final String time;
  final String body;
  const LogEntry({required this.title, required this.time, required this.body});
}

/// 从应用 `logs/` 目录读取日志文件，按类型分类。
/// 若尚无日志文件，返回空列表（页面显示空态）。
class LogStore {
  LogStore._();

  static Future<Directory> _logDir() async {
    final root = await AppDirectories.getAppDataDirectory();
    return Directory('${root.path}/logs');
  }

  static Future<List<LogEntry>> _listWhere(bool Function(String name) match) async {
    final dir = await _logDir();
    if (!await dir.exists()) return const [];
    final out = <LogEntry>[];
    await for (final ent in dir.list(followLinks: false)) {
      if (ent is! File) continue;
      final name = ent.path.split('/').last;
      if (!match(name.toLowerCase())) continue;
      String body = '';
      try {
        body = await ent.readAsString();
      } catch (_) {}
      if (body.length > 20000) body = body.substring(0, 20000);
      final stat = ent.statSync();
      final t = stat.modified.toLocal();
      String two(int n) => n.toString().padLeft(2, '0');
      out.add(LogEntry(
        title: name,
        time: '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}',
        body: body.isEmpty ? '(empty)' : body,
      ));
    }
    out.sort((a, b) => b.time.compareTo(a.time));
    return out;
  }

  /// 上下文日志。
  static Future<List<LogEntry>> sessions() =>
      _listWhere((n) => n.contains('context') || n.contains('session'));

  /// 请求日志。
  static Future<List<LogEntry>> requests() =>
      _listWhere((n) => n.contains('request') || n.contains('network') || n.contains('http'));

  /// 应用日志。
  static Future<List<LogEntry>> application() =>
      _listWhere((n) => n.contains('app') || n.contains('runtime') || n.contains('run'));
}