import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path_provider/path_provider.dart';

import '../security/credential_audit_logger.dart';
import 'log_tags.dart';
import 'logger.dart';

/// 日志导出工具（P3-32）。
///
/// 把 FileAppender 落盘的全部 `.log` 文件打包成一个 zip，交给分享/保存流程。
/// Logger 写盘前已经 LogSanitizer 脱敏，这里不再二次处理；导出动作本身记审计。
class LogExporter {
  LogExporter._();

  /// 导出全部日志文件为 zip，返回生成的 zip 文件绝对路径。
  ///
  /// 步骤：flush 落盘 → 列出日志文件 → 打包 zip 到临时目录 → 记审计。
  /// 没有任何日志文件时抛出 StateError，由调用方提示用户。
  static Future<String> exportLogs() async {
    // 1. 先 flush，确保缓冲中的日志全部落盘再打包
    await Logger.flush();

    // 2. 收集全部日志文件（Logger.listLogFiles 已按文件名倒序）
    final files = await Logger.listLogFiles();
    if (files.isEmpty) {
      throw StateError('no log files to export');
    }

    // 3. 打包 zip（保留原文件名，便于按日期查阅）
    final archive = Archive();
    for (final f in files) {
      final bytes = await f.readAsBytes();
      archive.addFile(ArchiveFile(f.uri.pathSegments.last, bytes.length, bytes));
    }
    final zipBytes = ZipEncoder().encode(archive);

    // 4. 写到临时目录，供 Share.shareXFiles 取用
    final tmp = await getTemporaryDirectory();
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final stamp = '${now.year}${two(now.month)}${two(now.day)}'
        '_${two(now.hour)}${two(now.minute)}${two(now.second)}';
    final out = File('${tmp.path}/minime_logs_$stamp.zip');
    await out.writeAsBytes(zipBytes);

    // 5. 审计：导出了 N 个日志文件（不记内容，只记数量）
    CredentialAuditLogger.record('export', 'log:files', detail: 'count=${files.length}');
    Logger.i(LogTags.storage, 'logs exported: count=${files.length} -> ${out.path}');

    return out.path;
  }
}
