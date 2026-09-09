import 'dart:io';

import '../checkup_scanner.dart';
import '../secret_detector.dart';

/// 日志文件扫描器（PR-5）。
///
/// 扫一遍本机日志文件，找是否把明文 Key 写进了日志（即便有 [LogSanitizer] 兜底，
/// 仍可能存在漏网的硬编码输出 / 第三方库直出）。
///
/// 只检测、不修复：重写日志文件有破坏取证链路的风险，故 [autoFix]=false，仅提示。
class LogFileScanner extends CheckupScanner {
  LogFileScanner(this._logFiles);
  final Future<List<File>> _logFiles;

  @override
  String get id => 'log_file';

  @override
  String get title => '日志文件';

  @override
  CheckupSeverity get severity => CheckupSeverity.warn;

  @override
  Future<List<CheckupFinding>> scan(CheckupStrings strings) async {
    final files = await _logFiles;
    var suspectLines = 0;
    var hitFiles = 0;

    for (final f in files) {
      if (!await f.exists()) continue;
      final hits = await _countHits(f);
      if (hits > 0) {
        hitFiles++;
        suspectLines += hits;
      }
    }

    if (hitFiles == 0) return const [];
    return [
      CheckupFinding(
        id: '$id:leak',
        scannerId: id,
        title: strings.logLeakTitle(),
        detail: strings.logLeakDetail(hitFiles, suspectLines),
        severity: CheckupSeverity.warn,
        autoFixable: false,
      )
    ];
  }

  static Future<int> _countHits(File f) async {
    try {
      final lines = await f.readAsLines();
      var n = 0;
      for (final line in lines) {
        if (SecretDetector.detect(line) != null) n++;
      }
      return n;
    } catch (_) {
      return 0;
    }
  }
}
