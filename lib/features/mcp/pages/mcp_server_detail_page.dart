import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/mcp_provider.dart';
import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../theme/design_tokens.dart';
import '../widgets/mcp_server_edit_sheet.dart';
import 'mcp_tool_detail_page.dart';

/// 服务器详情独立页：顶栏 Tab「MCP详情 / MCP工具」。
///
/// 已迁移到 AppPage 槽位骨架（**segments top** 样板）：
/// - 手写 DefaultTabController + Scaffold + AppBar.bottom(TabBar) + TabBarView
///   → AppPage(segments: [...], segmentsMode: AppSegmentMode.top)，引擎自动补
///   DefaultTabController / TabBar / TabBarView
/// - ⚠️ 分段模式下引擎不会给内容区加 padding 或 ListView，
///   因此每个 segment 的 body 必须自带滚动与内边距（本页两个 Tab 原本就是自带 ListView，保持不变）
/// - 工具列表空态 → AppEmpty（与 mcp_tool_detail_page 一致）
/// - 魔法数字 → AppGap / AppRadius（无精确 token 的 14/10/7/5/3 保留字面量，避免无谓视觉回归）
class McpServerDetailPage extends StatelessWidget {
  const McpServerDetailPage({super.key, required this.serverId});
  final String serverId;

  Color _statusColor(BuildContext context, McpStatus s) {
    final cs = Theme.of(context).colorScheme;
    switch (s) {
      case McpStatus.connected:
        return Colors.green;
      case McpStatus.connecting:
        return cs.primary;
      default:
        return Colors.redAccent;
    }
  }

  Widget _card(BuildContext context, {required List<Widget> children}) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : Colors.white.withOpacity(0.96),
        // 14 无精确 token，保留字面量
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(isDark ? 0.1 : 0.08), width: 0.6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: AppGap.xxs),
        child: Column(
          children: [
            for (int i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(height: 10, thickness: 0.6, color: cs.outlineVariant.withOpacity(0.18)),
              children[i],
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(BuildContext context,
      {required String label, required String value, Color? valueColor}) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.6))),
          const SizedBox(width: AppGap.sm),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: valueColor),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final mcp = context.watch<McpProvider>();
    final server = mcp.getById(serverId);

    // 服务器不存在（如已被删除）：同样走 AppPage 骨架
    if (server == null) {
      return AppPage(
        title: 'MCP',
        body: AppEmpty(message: l10n.mcpPageNoServers),
      );
    }

    final isBuiltin = server.transport == McpTransportType.inmemory;

    return AppPage(
      title: server.name,
      // 保留原来的返回 Tooltip 文案（AppPage 默认用系统 backButtonTooltip）
      leading: Tooltip(
        message: l10n.mcpPageBackTooltip,
        child: IconButton(
          icon: const Icon(Lucide.ArrowLeft),
          color: cs.onSurface,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      actions: [
        if (!isBuiltin)
          Tooltip(
            message: l10n.mcpDetailEditTooltip,
            child: IconButton(
              icon: const Icon(Lucide.Settings2),
              color: cs.onSurface,
              onPressed: () => showMcpServerEditSheet(context, serverId: serverId),
            ),
          ),
        IconButton(
          icon: const Icon(Lucide.RefreshCw),
          color: cs.primary,
          onPressed: () => mcp.refreshTools(serverId),
        ),
        const SizedBox(width: AppGap.xs),
      ],
      // 顶栏 TabBar：引擎据此生成 TabBar + TabBarView + DefaultTabController
      segmentsMode: AppSegmentMode.top,
      segments: [
        AppSegment(
          label: l10n.mcpDetailTabOverview,
          body: (_) => _buildOverviewTab(context, server),
        ),
        AppSegment(
          label: l10n.mcpDetailTabTools,
          body: (_) => _buildToolsTab(context, server),
        ),
      ],
    );
  }

  Widget _buildOverviewTab(BuildContext context, McpServerConfig server) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final mcp = context.watch<McpProvider>();
    final st = mcp.statusFor(serverId);
    final err = mcp.errorFor(serverId);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isBuiltin = server.transport == McpTransportType.inmemory;

    // 分段模式下引擎不加 padding，body 自带滚动
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.xxl),
      children: [
        _card(context, children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppGap.sm),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: server.enabled ? _statusColor(context, st) : cs.outline,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    st == McpStatus.connected
                        ? l10n.mcpPageStatusConnected
                        : (st == McpStatus.connecting
                            ? l10n.mcpPageStatusConnecting
                            : (server.enabled
                                ? l10n.mcpDetailStatusDisconnected
                                : l10n.mcpPageStatusDisabled)),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: AppGap.xxs),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(AppRadius.circular),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Lucide.Terminal, size: 12, color: Colors.green),
                      const SizedBox(width: 5),
                      Text(
                        isBuiltin
                            ? l10n.mcpTransportTagInmemory
                            : (server.transport == McpTransportType.sse
                                ? 'SSE'
                                : (server.transport == McpTransportType.stdio ? 'STDIO' : 'HTTP')),
                        style: const TextStyle(
                            fontSize: 11, color: Colors.green, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _row(context,
              label: isBuiltin ? l10n.mcpDetailIdLabel : l10n.mcpDetailUrlLabel,
              value: isBuiltin ? server.id : (server.url.isEmpty ? '-' : server.url)),
          _row(context,
              label: l10n.mcpDetailToolsCountLabel,
              value: l10n.mcpPageToolsCount(
                  server.tools.where((t) => t.enabled).length, server.tools.length)),
          if (isBuiltin)
            _row(context,
                label: l10n.mcpDetailBuiltinLabel,
                value: l10n.mcpDetailBuiltinYes,
                valueColor: Colors.green),
          if (!server.enabled)
            _row(context,
                label: l10n.mcpDetailEnabledLabel,
                value: l10n.mcpDetailDisabled,
                valueColor: Colors.redAccent),
        ]),

        if (st == McpStatus.error && (err?.isNotEmpty ?? false)) ...[
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppGap.sm),
            decoration: BoxDecoration(
              color: isDark ? cs.error.withOpacity(0.15) : cs.error.withOpacity(0.08),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: cs.error.withOpacity(0.35)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Lucide.MessageCircleWarning, size: 16, color: cs.error),
                const SizedBox(width: AppGap.xs),
                Expanded(
                  child: Text(
                    err!,
                    style: TextStyle(fontSize: 12, color: cs.error, height: 1.4),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildToolsTab(BuildContext context, McpServerConfig server) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // 空态 → 统一 AppEmpty
    if (server.tools.isEmpty) {
      return AppEmpty(message: l10n.mcpServerEditSheetNoToolsHint);
    }

    Widget _tag(String text, Color color) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(AppRadius.circular),
            border: Border.all(color: color.withOpacity(0.4)),
          ),
          child: Text(text,
              style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.xxl),
      children: server.tools.map((tool) {
        final enabledColor = tool.enabled ? Colors.green : cs.onSurface.withOpacity(0.5);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            Haptics.light();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => McpToolDetailPage(serverId: serverId, toolName: tool.name),
              ),
            );
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(AppGap.sm),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : const Color(0xFFF7F7F9),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Lucide.Wrench, size: 16, color: cs.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(tool.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                          if ((tool.description ?? '').isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(tool.description!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppGap.xs),
                    Icon(Lucide.ChevronRight, size: 16, color: cs.onSurface.withOpacity(0.5)),
                  ],
                ),
                const SizedBox(height: AppGap.xs),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _tag(tool.enabled ? l10n.mcpDetailEnabledLive : l10n.mcpDetailDisabled,
                        enabledColor),
                    _tag(
                        tool.requireApproval
                            ? l10n.mcpToolRequireApprovalLabel
                            : l10n.mcpToolSchemaNoApproval,
                        tool.requireApproval ? cs.primary : cs.onSurface.withOpacity(0.5)),
                    ...tool.params.take(4).map((p) => _tag(p.name,
                        p.required ? cs.primary : cs.onSurface.withOpacity(0.5))),
                  ],
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
