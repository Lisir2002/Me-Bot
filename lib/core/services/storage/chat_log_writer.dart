import 'dart:async';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/app_directories.dart';

/// 记录用户提问与模型回复的操作日志（fire-and-forget）。
///
/// 每个对话轮次写入一个独立文件：`logs/requests_<yyyyMMdd_HHmmss>_<seq>.log`，
/// 便于日志查看页按条展示（LogStore.requests 命中 request 前缀）。
class ChatLogWriter {
  ChatLogWriter._();

  static final Map<String, int> _seq = {}; // 同一秒内递增序号，避免覆盖

  /// 追加一轮对话日志。调用方无需 await，写入异常会被吞掉。
  static void recordTurn({
    String question = '',
    String answer = '',
    String? error,
  }) {
    unawaited(_write(question: question, answer: answer, error: error));
  }

  static Future<void> _write({
    required String question,
    required String answer,
    String? error,
  }) async {
    try {
      // 与日志设置页开关对齐：关闭「保存响应输出」则不落盘
      final prefs = await SharedPreferences.getInstance();
      if (!(prefs.getBool('log_save_response') ?? true)) return;

      final root = await AppDirectories.getAppDataDirectory();
      final dir = Directory('${root.path}/logs');
      if (!await dir.exists()) await dir.create(recursive: true);

      final now = DateTime.now();
      final stamp = _stamp(now);
      final seq = (_seq[stamp] ?? 0) + 1;
      _seq[stamp] = seq;

      final file = File('${dir.path}/requests_${stamp}_$seq.log');
      final buf = StringBuffer();
      buf
        ..writeln('[用户提问]')
        ..writeln(question.isEmpty ? '(空)' : question)
        ..writeln()
        ..writeln('[模型回复]')
        ..writeln(answer.isEmpty ? (error == null ? '(空)' : '(无输出)') : answer);
      if (error != null && error.isNotEmpty) {
        buf
          ..writeln()
          ..writeln('[错误]')
          ..writeln(error);
      }
      await file.writeAsString(buf.toString(), flush: true);
    } catch (_) {
      // 日志写入不允许影响主流程
    }
  }

  static String _stamp(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}${two(t.month)}${two(t.day)}_${two(t.hour)}${two(t.minute)}${two(t.second)}';
  }
}