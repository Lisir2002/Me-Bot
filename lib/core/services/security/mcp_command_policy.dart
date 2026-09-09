import 'policy_provider.dart';

/// MCP stdio 命令守卫（PR-8）。
///
/// 校验 MCP stdio 服务器要 spawn 的命令是否在白名单内。实际进程由 `mcp_client`
/// 包内部 `Process.start` 拉起，因此只能在「我们的连接调用处」拦截——即在
/// [McpProvider.connect] 取出 `command` 之后、交给 `mcp_client` 之前调用本守卫。
///
/// 规则：
/// - 策略未启用 → 全部放行（宽松默认，不阻断既有用法）；
/// - 单服务器被关闭 stdio（[PolicyProvider.isMcpServerAllowed]=false）→ 拦截；
/// - 命令为空 → 拦截；
/// - 命令基础名（去路径）不在 [PolicyProvider.allowedMcpCommands] → 拦截。
///
/// 拦截由调用方记审计日志（[LogTags.policy]）并阻断连接。
class McpCommandGuard {
  McpCommandGuard(this.provider);

  final PolicyProvider provider;

  /// 取命令基础名（去掉路径与参数）。`/usr/bin/node` → `node`；`node` → `node`。
  static String baseName(String command) {
    final trimmed = command.trim();
    if (trimmed.isEmpty) return '';
    // 取第一段（命令本身，不含参数）
    final head = trimmed.split(RegExp(r'\s+')).first;
    // 去掉目录
    final seg = head.split(RegExp(r'[/\\]'));
    return seg.last;
  }

  McpGuardResult check(String? command, {String? serverId}) {
    if (!provider.enabled) return McpGuardResult.allow();

    if (serverId != null && !provider.isMcpServerAllowed(serverId)) {
      return McpGuardResult.deny('该服务器已被停用 stdio 传输');
    }

    final cmd = command?.trim();
    if (cmd == null || cmd.isEmpty) {
      return McpGuardResult.deny('stdio 命令为空');
    }

    final base = baseName(cmd);
    if (base.isEmpty) return McpGuardResult.deny('stdio 命令无法解析');

    if (provider.allowedMcpCommands.contains(base)) {
      return McpGuardResult.allow();
    }
    return McpGuardResult.deny('命令不在白名单: $base');
  }
}

/// MCP 命令守卫裁决。
class McpGuardResult {
  const McpGuardResult._(this.allowed, this.reason);
  factory McpGuardResult.allow() => const McpGuardResult._(true, '');
  factory McpGuardResult.deny(String reason) => McpGuardResult._(false, reason);

  final bool allowed;
  final String reason;

  bool get denied => !allowed;
}
