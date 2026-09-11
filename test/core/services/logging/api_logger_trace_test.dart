import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:minime_core/core/services/logging/api_logger.dart';
import 'package:minime_core/core/services/logging/log_context.dart';
import 'package:minime_core/core/services/logging/logger.dart';

/// P0-4：ApiLogger 必须接入 LogContext.traceId，
/// 并在 REQUEST / RESPONSE / ERROR 日志中输出 (traceId=xxx)。
void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('mebot_api_trace_test');
    // 注入临时目录，避免依赖平台 path_provider
    await Logger.init(
      mirrorToConsole: false,
      fileLogDirOverride: tmp,
      fileFlushIntervalMs: 10000,
    );
  });

  tearDown(() async {
    await Logger.flush(); // 先排空，避免删目录后定时器再写触发兜底日志
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('zone 内的 traceId 出现在 REQUEST/RESPONSE/ERROR 日志中', () async {
    final ApiRequest req = await LogContext.zone<ApiRequest>(
      traceId: 'trace-xyz-123',
      fn: () async {
        final r = ApiLogger.logRequest(
          provider: 'SiliconFlow',
          model: 'qwen3-8b',
          method: 'POST',
          url: '/v1/chat/completions',
        );
        ApiLogger.logResponse(r, statusCode: 200, body: '{"ok":true}');
        ApiLogger.logError(r, message: 'boom');
        return r;
      },
    );

    // 请求发生时快照的 traceId 应落在句柄上
    expect(req.traceId, 'trace-xyz-123');

    await Logger.flush();

    // MemoryAppender 里的消息应包含 traceId=trace-xyz-123
    final msgs = Logger.memoryAppender!
        .recent()
        .map((r) => r.message)
        .join('\n');

    expect(msgs, contains('traceId=trace-xyz-123'),
        reason: 'ApiLogger 日志未带上 traceId:\n$msgs');
  });

  test('无 zone 时 traceId 为 null，日志不报错且不带 traceId 段', () async {
    final req = ApiLogger.logRequest(
      provider: 'P',
      model: 'M',
      method: 'GET',
      url: '/health',
    );
    ApiLogger.logResponse(req, statusCode: 200);

    expect(req.traceId, isNull);
    await Logger.flush();

    final last = Logger.memoryAppender!.recent().first.message;
    expect(last, contains('RESPONSE'));
    expect(last, isNot(contains('(traceId=')));
  });
}
