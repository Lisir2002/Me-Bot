import 'dart:io';

import '../../../core/services/logging/log_parser.dart';
import '../../../core/services/logging/logger.dart';
import '../../../utils/app_directories.dart';

/// 旧版日志存储入口：保留 API 签名，底层委托到新 [Logger]。
///
/// 原项目 UI 调的是 [sessions]/[requests]/[application]，现在新 Logger
/// 统一按 Tag 分，所以这里做一次适配：根据文件名归类回原来的三个桶。
class LogStore {
  LogStore._();

  static Future<Directory> _logDir() async {
    final existing = Logger.logDir;
    if (existing != null && await existing.exists()) return existing;
    final root = await AppDirectories.getAppDataDirectory();
    return Directory('${root.path}/logs');
  }

  static Future<List<LogEntry>> _listWhere(bool Function(String name) match) async {
    final dir = await _logDir();
    if (!await dir.exists()) return const [];
    final out = <LogEntry>[];
    await for (final ent in dir.list(followLinks: false)) {
      if (ent is! File) continue;
      final name = ent.path.split(RegExp(r'[/\\]')).last;
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

  /// 上下文日志（按 Tag = 'Chat' / 'Context' 过滤）。
  static Future<List<LogEntry>> sessions() =>
      _listWhere((n) => n.contains('session') || n.contains('context') || n.endsWith('.log'));

  /// 请求日志（按 Tag = 'Api' / 'Network' 过滤）。
  static Future<List<LogEntry>> requests() =>
      _listWhere((n) => n.contains('request') || n.contains('network') || n.contains('http') || n.endsWith('.log'));

  /// 应用日志（全量 log-*.log 文件）。
  static Future<List<LogEntry>> application() =>
      _listWhere((n) => n.contains('app') || n.contains('runtime') || n.contains('run') || n.endsWith('.log'));
}

/// 日志条目（供日志查看页展示）。
class LogEntry {
  final String title;
  final String time;
  final String body;
  const LogEntry({required this.title, required this.time, required this.body});
}
