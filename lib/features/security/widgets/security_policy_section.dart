// ignore_for_file: hardcoded_ui_string
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/mcp_provider.dart';
import '../../../core/services/security/policy_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_section.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/design_tokens.dart';
import 'security_shared.dart';

/// 安全中心「白名单策略」section（P1 #6 从 security_page.dart 抽出）。
///
/// 展示并编辑 [LocalPolicyProvider] 的白名单策略：
/// - 白名单总开关 / allowWebViewHttp 开关（带风险确认）
/// - MCP stdio 命令白名单 chips（增删 / 恢复默认 / 去重提示）
/// - WebView 主机白名单 chips（增删 / 去重提示）
/// - MCP 服务器逐台开关（关闭时二次确认）
/// - 新功能 5：策略冲突检测（stdio 服务器的 command 不在白名单时给出黄色警告行）
///
/// 策略由父级在 initState 中创建并缓存为 [policyFuture]；任何变更后调用
/// [onPolicyChanged] 通知父级 setState，用于刷新安全评分。
class SecurityPolicySection extends StatelessWidget {
  const SecurityPolicySection({
    super.key,
    required this.policyFuture,
    required this.onPolicyChanged,
  });

  /// 由父级在 initState 中创建并缓存的策略 Future（P1 #6）。
  final Future<LocalPolicyProvider> policyFuture;

  /// 策略变更后通知父级 setState（用于刷新安全评分）。
  final VoidCallback onPolicyChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SecuritySectionHeader(l10n.allowlist, first: true),
        SecuritySectionDesc(l10n.allowlistDesc),
        FutureBuilder<LocalPolicyProvider>(
          future: policyFuture,
          builder: (context, snap) {
            final policy = snap.data;
            if (policy == null) return const SizedBox.shrink();
            final servers = context.watch<McpProvider>().servers;
            return AppSectionCard(
              children: _buildRows(context, l10n, policy, servers),
            );
          },
        ),
      ],
    );
  }

  // ── 卡内行集合 ──────────────────────────────────────────────

  List<Widget> _buildRows(
    BuildContext context,
    AppLocalizations l10n,
    LocalPolicyProvider policy,
    List<McpServerConfig> servers,
  ) {
    final cs = Theme.of(context).colorScheme;
    return [
      // 白名单总开关
      AppSwitchRow(
        icon: Lucide.Shield,
        label: l10n.allowlistEnable,
        value: policy.enabled,
        onChanged: (v) async {
          await policy.setEnabled(v);
          onPolicyChanged();
        },
      ),
      const AppSectionDivider(),
      // allowHttp 开关（P2：开启时弹风险警告）
      AppSwitchRow(
        icon: Lucide.Globe,
        label: l10n.allowHttp,
        value: policy.allowWebViewHttp,
        onChanged: (v) => _onAllowHttpChanged(context, policy, v),
      ),
      const AppSectionDivider(),
      // MCP 命令白名单标题 + 恢复默认
      SecurityRowHeader(
        l10n.mcpCommandAllowlist,
        trailing: TextButton.icon(
          onPressed: () => _restoreDefaultCmds(policy),
          icon: const Icon(Lucide.RefreshCw, size: 16),
          label: Text(l10n.restoreDefaultCmds),
        ),
      ),
      SecurityChipWrap([
        for (final c in policy.allowedMcpCommands)
          InputChip(
            label: Text(c),
            onDeleted: () async {
              final next = Set.of(policy.allowedMcpCommands)..remove(c);
              await policy.setAllowedMcpCommands(next);
              onPolicyChanged();
            },
          ),
        ActionChip(
          avatar: const Icon(Lucide.Plus, size: 18),
          label: Text(l10n.addCommand),
          onPressed: () => _addCommand(context, policy),
        ),
      ]),
      const AppSectionDivider(),
      // WebView 主机白名单标题 + 添加
      SecurityRowHeader(
        l10n.webviewHosts,
        trailing: TextButton.icon(
          onPressed: () => _addHost(context, policy),
          icon: const Icon(Lucide.Plus, size: 16),
          label: Text(l10n.addHost),
        ),
      ),
      if (policy.allowedWebViewHosts.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppGap.sm, 0, AppGap.sm, AppGap.xxs),
          child: Text(l10n.webviewHostsEmpty,
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withValues(alpha: 0.55))),
        )
      else
        SecurityChipWrap([
          for (final h in policy.allowedWebViewHosts)
            InputChip(
              label: Text(h),
              onDeleted: () async {
                final next = Set.of(policy.allowedWebViewHosts)..remove(h);
                await policy.setWebViewHosts(next);
                onPolicyChanged();
              },
            ),
        ]),
      const AppSectionDivider(),
      // MCP 服务器策略标题
      SecurityRowHeader(l10n.mcpServersPolicy),
      // 新功能 5：策略冲突检测（白名单开启时才检查）
      if (policy.enabled) ..._buildConflicts(context, policy, servers),
      if (servers.isEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(AppGap.sm, 0, AppGap.sm, AppGap.xxs),
          child: Text(l10n.mcpServersEmpty,
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withValues(alpha: 0.55))),
        )
      else
        for (final s in servers)
          _serverRow(context, l10n, cs, policy, s),
    ];
  }

  // ── 新功能 5：策略冲突警告行 ────────────────────────────────

  /// 计算 stdio 服务器中 command 不在白名单的冲突项，并生成黄色警告行。
  List<Widget> _buildConflicts(
    BuildContext context,
    LocalPolicyProvider policy,
    List<McpServerConfig> servers,
  ) {
    final conflicts = servers
        .where((s) =>
            s.transport == McpTransportType.stdio &&
            s.command != null &&
            s.command!.isNotEmpty &&
            !policy.allowedMcpCommands.contains(s.command))
        .toList();
    if (conflicts.isEmpty) return const [];

    return [
      for (final s in conflicts)
        Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppGap.sm, vertical: AppGap.xxs),
          child: Row(
            children: [
              const Icon(Lucide.AlertTriangle,
                  color: AppStatusColor.warning, size: 18),
              const SizedBox(width: AppGap.sm),
              Expanded(
                child: Text(
                  '服务器「${s.name}」的命令「${s.command}」未在白名单中，将被拦截',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.7),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _addCommandToWhitelist(context, policy, s.command!),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('添加'),
              ),
            ],
          ),
        ),
    ];
  }

  /// 将冲突的 command 加入白名单（供冲突警告行的「添加」按钮调用）。
  Future<void> _addCommandToWhitelist(
    BuildContext context,
    LocalPolicyProvider policy,
    String command,
  ) async {
    final next = Set.of(policy.allowedMcpCommands)..add(command);
    await policy.setAllowedMcpCommands(next);
    onPolicyChanged();
  }

  // ── P2：allowHttp 开启风险确认 ──────────────────────────────

  Future<void> _onAllowHttpChanged(
    BuildContext context,
    LocalPolicyProvider policy,
    bool v,
  ) async {
    // 仅在 off→on 时弹风险警告；关闭时直接执行。
    if (v && !policy.allowWebViewHttp) {
      final ok = await AppDialog.confirm(
        context,
        title: '允许 HTTP 连接',
        message:
            '允许 WebView 加载 HTTP 页面会降低安全性，可能导致数据被窃听或篡改。确定要开启吗？',
        confirmText: '仍要开启',
        danger: true,
      );
      if (!ok) return;
    }
    await policy.setAllowWebViewHttp(v);
    onPolicyChanged();
  }

  // ── MCP 服务器开关行（P1：关闭时二次确认）──────────────────

  Widget _serverRow(
    BuildContext context,
    AppLocalizations l10n,
    ColorScheme cs,
    LocalPolicyProvider policy,
    McpServerConfig s,
  ) {
    final sub = s.command != null && s.command!.isNotEmpty
        ? 'stdio: ${s.command}'
        : s.transport.name;
    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: AppGap.xxs),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.name.isNotEmpty ? s.name : s.id,
                    style: TextStyle(
                        fontSize: 15, color: cs.onSurface.withValues(alpha: 0.9))),
                const SizedBox(height: AppGap.xxxs),
                Text(sub,
                    style: TextStyle(
                        fontSize: 12, color: cs.onSurface.withValues(alpha: 0.55))),
              ],
            ),
          ),
          IosSwitch(
            value: policy.isMcpServerAllowed(s.id),
            onChanged: (v) => _onServerSwitchChanged(context, policy, s, v),
          ),
        ],
      ),
    );
  }

  Future<void> _onServerSwitchChanged(
    BuildContext context,
    LocalPolicyProvider policy,
    McpServerConfig s,
    bool v,
  ) async {
    // P1：仅在 on→off 时弹关闭确认；开启时不需要确认。
    if (!v && policy.isMcpServerAllowed(s.id)) {
      final ok = await AppDialog.confirm(
        context,
        title: '关闭 MCP 服务器',
        message: '确定要关闭「${s.name}」吗？关闭后该服务器将无法使用。',
        confirmText: '关闭',
        danger: true,
      );
      if (!ok) return;
    }
    await policy.setMcpServerEnabled(s.id, v);
    onPolicyChanged();
  }

  // ── 命令 / 主机增删 ─────────────────────────────────────────

  Future<void> _restoreDefaultCmds(LocalPolicyProvider policy) async {
    await policy.setAllowedMcpCommands(policy.defaultMcpCommands);
    onPolicyChanged();
  }

  /// 添加命令：输入弹窗 → 去重 → 校验 → 写入。
  Future<void> _addCommand(
      BuildContext context, LocalPolicyProvider policy) async {
    final l10n = context.l10n;
    final cmd = await AppDialog.input(
      context,
      title: l10n.addCommand,
      hintText: l10n.commandHint,
      confirmText: MaterialLocalizations.of(context).okButtonLabel,
      cancelText: MaterialLocalizations.of(context).cancelButtonLabel,
    );
    if (cmd == null) return;
    if (!context.mounted) return;
    // P2：重复命令提前拦截
    if (policy.allowedMcpCommands.contains(cmd)) {
      showAppSnackBar(context,
          message: '该命令已存在', type: NotificationType.warning);
      return;
    }
    if (cmd.isEmpty || !LocalPolicyProvider.isValidCommand(cmd)) {
      showAppSnackBar(context,
          message: l10n.invalidCommand, type: NotificationType.error);
      return;
    }
    final next = Set.of(policy.allowedMcpCommands)..add(cmd);
    await policy.setAllowedMcpCommands(next);
    onPolicyChanged();
  }

  /// 添加主机：输入弹窗 → trim/lowercase → 去重 → 校验 → 写入。
  Future<void> _addHost(
      BuildContext context, LocalPolicyProvider policy) async {
    final l10n = context.l10n;
    final hostInput = await AppDialog.input(
      context,
      title: l10n.addHost,
      hintText: l10n.hostHint,
      confirmText: MaterialLocalizations.of(context).okButtonLabel,
      cancelText: MaterialLocalizations.of(context).cancelButtonLabel,
    );
    if (hostInput == null) return;
    if (!context.mounted) return;
    final host = hostInput.trim().toLowerCase();
    // P2：重复主机提前拦截
    if (policy.allowedWebViewHosts.contains(host)) {
      showAppSnackBar(context,
          message: '该主机已存在', type: NotificationType.warning);
      return;
    }
    if (host.isEmpty || !LocalPolicyProvider.isValidHost(host)) {
      showAppSnackBar(context,
          message: l10n.invalidHost, type: NotificationType.error);
      return;
    }
    final next = Set.of(policy.allowedWebViewHosts)..add(host);
    await policy.setWebViewHosts(next);
    onPolicyChanged();
  }
}
