import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:minime_core/core/services/logging/log_appender.dart';
import 'package:minime_core/core/services/logging/log_level.dart';
import 'package:minime_core/core/services/logging/log_record.dart';

/// P0-2：当前文件超过 maxFileBytes 时应轮转归档（.1/.2…），
/// 而不是直接覆盖清空历史。
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mebot_log_rot_test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  String mainLogName() {
    final n = DateTime.now();
    String p(int v) => v.toString().padLeft(2, '0');
    return 'log-${n.year}-${p(n.month)}-${p(n.day)}.log';
  }

  LogRecord rec(String msg) => LogRecord(
        timestamp: DateTime.now(),
        level: LogLevel.info,
        tag: 'RotTest',
        message: msg,
      );

  test('文件超限后生成 .log.1 归档，且主文件重新创建', () async {
    // maxFileBytes 设小，flush 不自动触发，测试里手动 flush
    final appender = FileAppender(
      maxFileBytes: 200,
      flushIntervalMs: 10000,
      maxRotatedFiles: 5,
      logDirOverride: tmp,
    );
    await appender.init();

    // 第一次写入：建立主文件
    appender.append(rec('A' * 600));
    await appender.flush();

    final main = File('${tmp.path}/${mainLogName()}');
    expect(await main.exists(), isTrue);
    expect(await main.length(), greaterThan(200));

    // 第二次写入：主文件已超限 → 应轮转为主文件.1
    appender.append(rec('B' * 600));
    await appender.flush();

    final rot1 = File('${tmp.path}/${mainLogName()}.1');
    expect(await rot1.exists(), isTrue, reason: '未生成 .log.1 归档文件');

    // 主文件应被重新创建并写入新内容（不再是空的"已重置"占位）
    expect(await main.exists(), isTrue);
    final mainContent = await main.readAsString();
    expect(mainContent, contains('B' * 600));
  });

  test('多次超限后按 .1/.2 滚动，超过 maxRotatedFiles 丢弃最老一份', () async {
    final appender = FileAppender(
      maxFileBytes: 200,
      flushIntervalMs: 10000,
      maxRotatedFiles: 2, // 只保留 .1 / .2 两份
      logDirOverride: tmp,
    );
    await appender.init();

    // 连续五次写入，触发多次轮转
    for (var i = 0; i < 5; i++) {
      appender.append(rec('MSG$i' * 300));
      await appender.flush();
    }

    final rot1 = File('${tmp.path}/${mainLogName()}.1');
    final rot2 = File('${tmp.path}/${mainLogName()}.2');
    final rot3 = File('${tmp.path}/${mainLogName()}.3');

    // 保留最近两份
    expect(await rot1.exists(), isTrue);
    expect(await rot2.exists(), isTrue);
    // 超过上限的最老归档被丢弃
    expect(await rot3.exists(), isFalse);

    await appender.dispose();
  });

  test('主文件不存在时不崩溃（边界）', () async {
    final appender = FileAppender(
      maxFileBytes: 200,
      flushIntervalMs: 10000,
      logDirOverride: tmp,
    );
    await appender.init();

    // 直接写一条不存在的文件：不应抛
    appender.append(rec('fresh'));
    await appender.flush();

    expect(await File('${tmp.path}/${mainLogName()}').exists(), isTrue);
    await appender.dispose();
  });
}
