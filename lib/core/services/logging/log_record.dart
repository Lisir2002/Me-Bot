
import 'log_level.dart';

/// 结构化日志记录。
///
/// [Logger] 内部不再直接拼字符串落盘，而是先构造一个 [LogRecord]，
/// 再分发到各个 [LogAppender]（文件、内存、远程……）。
/// 新增字段（如 traceId / userId / requestId / 自定义 metadata）
/// 只需在这里加，不影响任何下游 Appender。
class LogRecord {
  /// 日志产生的精确时间戳。
  final DateTime timestamp;

  /// 等级。
  final LogLevel level;

  /// 来源模块 Tag（例如 `ApiReq`、`McpTool`）。
  final String tag;

  /// 主消息（已过脱敏 + 截断）。
  final String message;

  /// 附带的 error（可能为 null）。
  final Object? error;

  /// 附带的堆栈（可能为 null）。
  final StackTrace? stack;

  /// 链路追踪 ID。同一请求 / 同一 MCP 调用链上的所有日志共享。
  final String? traceId;

  /// 业务级上下文（可选）：userId / requestId / 自定义 KV。
  final Map<String, String>? context;

  const LogRecord({
    required this.timestamp,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stack,
    this.traceId,
    this.context,
  });
}
