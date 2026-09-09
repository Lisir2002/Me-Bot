import '../logging/logger.dart';
import '../logging/log_tags.dart';
import '../logging/log_context.dart';

/// 凭证操作审计（PR-5）。
///
/// 把「查看 / 复制 / 导出 / 迁移 / 解密」等敏感操作统一记到独立 [LogTags.security]
/// 通道，带 [LogContext.zone] 的 traceId，在既有日志查看器里可直接按标签过滤。
///
/// 铁律：任何审计事件都**不携带凭证明文值**——只记录操作名、对象类别、结果。
/// 因此这里的方法签名里永远看不到 value。
class CredentialAuditLogger {
  CredentialAuditLogger._();

  /// 凭证相关操作的类别（仅用于日志归类，不泄露内容）。
  static const String _scope = 'credential';

  /// 记录一次凭证操作（成功或失败都记，便于审计与排障）。
  ///
  /// [action] 见 [CredentialAuditAction]；[target] 是对象类别（如 'provider:openai'、
  /// 'backup:encrypted'、'migration:v1'），**不是明文值**；[ok]=false 时记 warn。
  static void record(
    String action,
    String target, {
    bool ok = true,
    String? detail,
    Object? error,
    StackTrace? stack,
  }) {
    final msg = '[$_scope] $action target=$target'
        '${ok ? '' : ' FAILED'}${detail != null ? ' ($detail)' : ''}';
    if (ok) {
      Logger.i(LogTags.security, msg, error, stack);
    } else {
      Logger.w(LogTags.security, msg, error, stack);
    }
  }

  /// 在一个带 traceId 的链路里执行 [task]，并把凭证操作审计自动带上同一 traceId。
  static Future<T> traced<T>(
    String traceId,
    Future<T> Function() task,
  ) =>
      LogContext.zone(traceId: traceId, fn: task);
}
