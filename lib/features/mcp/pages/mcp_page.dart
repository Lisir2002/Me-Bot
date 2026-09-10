import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_slidable/flutter_slidable.dart';

import '../../../core/providers/mcp_provider.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../l10n/build_context_l10n.dart';
import '../../../shared/widgets/app_dialog.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/app_states.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../shared/widgets/snackbar.dart';
import '../../../theme/design_tokens.dart';
import '../widgets/mcp_server_edit_sheet.dart';
import '../widgets/mcp_json_edit_sheet.dart';
import 'mcp_server_detail_page.dart';

/// MCP 服务器列表页。
///
/// 已迁移到 AppPage 槽位骨架，并顺带做了两处组件收敛：
/// 1. Scaffold + AppBar + ListView → AppPage(title/leading/actions/body)
///    - body 用 Column(stretch)：AppPage 滚动容器给子项紧宽度，Column 默认 center
///      会把宽度放宽导致卡片缩成内容宽度，必须 stretch。
/// 2. 私有 _TactileIconButton → 共享 IosIconButton（与 settings/sponsor 等页一致）
/// 3. 手写 showModalBottomSheet（错误详情）→ AppSheet 模板，footer 承载「关闭/重连」
/// 4. padding LTRB(16,12,16,16) → fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.md)
/// 5. 空态 → AppEmpty（保留原 top:120 的视觉下沉）
class McpPage extends StatelessWidget {
  const McpPage({super.key});

  /// 空态距顶部的下沉量。原实现靠它把「暂无服务器」顶到视觉中部
  /// （AppPage 的滚动容器是无限高度，无法用 Center 做垂直居中）。
  static const double _emptyTopOffset = 120;

  Color _statusColor(BuildContext context, McpStatus s) {
    final cs = Theme.of(context).colorScheme;
    switch (s) {
      case McpStatus.connected:
        return Colors.green;
      case McpStatus.connecting:
        return cs.primary;
      case McpStatus.error:
      case McpStatus.idle:
        return Colors.red;
    }
  }

  Future<void> _showErrorDetails(
      BuildContext context, String serverId, String? message, String name) async {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    await showAppSheet<void>(
      context: context,
      builder: AppSheet(
        title: l10n.mcpPageErrorDialogTitle,
        contentPadding: const EdgeInsets.fromLTRB(
            AppGap.md, AppGap.md, AppGap.md, AppGap.lg),
        // ignore: sort_child_properties_last —— AppSheet 语义顺序是 title → children → footer，与 lint 的「children 放最后」冲突
        children: [
          Text(name, style: TextStyle(color: cs.onSurface.withOpacity(0.7))),
          const SizedBox(height: AppGap.sm),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppGap.sm),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : const Color(0xFFF7F7F9),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
            ),
            child: Text(message?.isNotEmpty == true ? message! : l10n.mcpPageErrorNoDetails),
          ),
        ],
        footer: Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(Lucide.X, size: 16, color: cs.primary),
                label: Text(l10n.mcpPageClose, style: TextStyle(color: cs.primary)),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  backgroundColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                  side: BorderSide(color: cs.outlineVariant.withOpacity(0.35)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
              ),
            ),
            const SizedBox(width: AppGap.sm),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () async {
                  await context.read<McpProvider>().reconnect(serverId);
                  if (context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Lucide.RefreshCw, size: 18),
                label: Text(l10n.mcpPageReconnect),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  backgroundColor: cs.primary,
                  foregroundColor: cs.onPrimary,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    return AppPage(
      title: 'MCP',
      leading: Tooltip(
        message: l10n.mcpPageBackTooltip,
        child: IosIconButton(
          haptics: true,
          icon: Lucide.ArrowLeft,
          color: cs.onSurface,
          size: 22,
          minSize: 44,
          semanticLabel: l10n.mcpPageBackTooltip,
          onTap: () => Navigator.of(context).maybePop(),
        ),
      ),
      actions: [
        Tooltip(
          message: l10n.mcpJsonEditButtonTooltip,
          child: IosIconButton(
            haptics: true,
            icon: Lucide.Edit,
            color: cs.onSurface,
            size: 22,
            minSize: 44,
            semanticLabel: l10n.mcpJsonEditButtonTooltip,
            onTap: () async { await showMcpJsonEditSheet(context); },
          ),
        ),
        const SizedBox(width: AppGap.sm),
        Tooltip(
          message: l10n.mcpPageAddMcpTooltip,
          child: IosIconButton(
            haptics: true,
            icon: Lucide.Plus,
            color: cs.onSurface,
            size: 22,
            minSize: 44,
            semanticLabel: l10n.mcpPageAddMcpTooltip,
            onTap: () async { await showMcpServerEditSheet(context); },
          ),
        ),
        const SizedBox(width: AppGap.sm),
      ],
      bodyPadding: const EdgeInsets.fromLTRB(AppGap.md, AppGap.sm, AppGap.md, AppGap.md),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildServerList(context),
      ),
    );
  }

  /// 按 内置(MiniMe) / 第三方 分组构建服务器列表，组间插入小标题。
  List<Widget> _buildServerList(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final mcp = context.watch<McpProvider>();
    final servers = mcp.servers.toList();
    if (servers.isEmpty) {
      return [
        AppEmpty(
          message: l10n.mcpPageNoServers,
          verticalPadding: _emptyTopOffset,
        ),
      ];
    }

    final builtin = servers.where((s) => s.transport == McpTransportType.inmemory).toList();
    final third = servers.where((s) => s.transport != McpTransportType.inmemory).toList();

    Widget header(String text, IconData icon) => Padding(
          padding: const EdgeInsets.fromLTRB(AppGap.xxs, 14, 0, 6),
          child: Row(
            children: [
              Icon(icon, size: 14, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                text,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            ],
          ),
        );

    final out = <Widget>[];
    if (builtin.isNotEmpty) {
      out.add(header(l10n.mcpGroupBuiltin, Lucide.Bot));
      out.addAll(builtin.map((s) => _serverCard(context, s)).toList());
    }
    if (third.isNotEmpty) {
      out.add(header(l10n.mcpGroupThirdParty, Lucide.Terminal));
      out.addAll(third.map((s) => _serverCard(context, s)).toList());
    }
    return out;
  }

  Widget _serverCard(BuildContext context, McpServerConfig s) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final mcp = context.watch<McpProvider>();
    final st = mcp.statusFor(s.id);
    final err = mcp.errorFor(s.id);

    Widget tagStyled(String text, {Color? color}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: AppGap.xs, vertical: AppGap.xxxs),
          decoration: BoxDecoration(
            color: (color ?? cs.primary).withOpacity(0.12),
            borderRadius: BorderRadius.circular(AppRadius.circular),
            border: Border.all(color: (color ?? cs.primary).withOpacity(0.35)),
          ),
          child: Text(text, style: TextStyle(fontSize: 11, color: color ?? cs.primary, fontWeight: FontWeight.w700)),
        );

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final row = IosTactileRow(
      haptics: false,
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => McpServerDetailPage(serverId: s.id),
          ),
        );
      },
      builder: (ctx, pressed) {
        final base = cs.onSurface.withOpacity(0.9);
        return IosPressColor(
          pressed: pressed,
          base: base,
          builder: (c) {
            final overlay = pressed
                ? (isDark ? Colors.black.withOpacity(0.06) : Colors.white.withOpacity(0.05))
                : Colors.transparent;
            return Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : Colors.white.withOpacity(0.96),
                // 14 无精确 token（AppRadius.md=12 / lg=16），保留字面量
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: cs.outlineVariant.withOpacity(isDark ? 0.1 : 0.08), width: 0.6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: 11),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          alignment: Alignment.center,
                          child: Icon(Lucide.Terminal, size: 20, color: cs.primary),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: st == McpStatus.connecting
                              ? SizedBox(
                                  width: 12,
                                  height: 12,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                                  ),
                                )
                              : Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: s.enabled ? _statusColor(context, st) : cs.outline,
                                    shape: BoxShape.circle,
                                    border: Border.all(color: cs.surface, width: 1.5),
                                  ),
                                ),
                        ),
                        if (overlay != Colors.transparent)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                  color: overlay, borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: AppGap.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            s.name,
                            style: TextStyle(fontWeight: FontWeight.w700, color: c),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: AppGap.xs),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              tagStyled(
                                st == McpStatus.connected
                                    ? l10n.mcpPageStatusConnected
                                    : (st == McpStatus.connecting
                                        ? l10n.mcpPageStatusConnecting
                                        : l10n.mcpPageStatusDisconnected),
                                color: st == McpStatus.connected
                                    ? Colors.green
                                    : (st == McpStatus.connecting ? cs.primary : Colors.redAccent),
                              ),
                              tagStyled(
                                s.transport == McpTransportType.inmemory
                                    ? l10n.mcpTransportTagInmemory
                                    : (s.transport == McpTransportType.sse ? 'SSE' : 'HTTP'),
                              ),
                              tagStyled(l10n.mcpPageToolsCount(
                                  s.tools.where((t) => t.enabled).length, s.tools.length)),
                              if (!s.enabled)
                                tagStyled(l10n.mcpPageStatusDisabled,
                                    color: cs.onSurface.withOpacity(0.7)),
                            ],
                          ),
                          if (st == McpStatus.error && (err?.isNotEmpty ?? false)) ...[
                            const SizedBox(height: AppGap.xs),
                            Row(
                              children: [
                                Icon(Lucide.MessageCircleWarning, size: 14, color: Colors.red),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    l10n.mcpPageConnectionFailed,
                                    style: const TextStyle(fontSize: 12, color: Colors.red),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => _showErrorDetails(context, s.id, err, s.name),
                                  child: Text(l10n.mcpPageDetails),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: AppGap.xs),
                    Icon(Lucide.ChevronRight, size: 16, color: c),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Slidable(
        key: ValueKey('mcp-${s.id}'),
        endActionPane: ActionPane(
          motion: const StretchMotion(),
          extentRatio: 0.42,
          children: [
            CustomSlidableAction(
              autoClose: true,
              backgroundColor: Colors.transparent,
              child: Container(
                width: double.infinity,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: isDark ? cs.error.withOpacity(0.22) : cs.error.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.error.withOpacity(0.35)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: AppGap.sm, vertical: AppGap.xs),
                alignment: Alignment.center,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Lucide.Trash2, color: cs.error, size: 18),
                      const SizedBox(width: 6),
                      Text(l10n.mcpPageDelete,
                          style: TextStyle(color: cs.error, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),
              onPressed: (_) async {
                final ok = await AppDialog.confirm(
                  context,
                  title: l10n.mcpPageConfirmDeleteTitle,
                  message: l10n.mcpPageConfirmDeleteContent,
                  confirmText: l10n.mcpPageDelete,
                  cancelText: l10n.mcpPageCancel,
                  danger: true,
                );
                if (!ok) return;
                final prov = context.read<McpProvider>();
                final prev = prov.getById(s.id);
                await prov.removeServer(s.id);
                if (!context.mounted) return;
                showAppSnackBar(
                  context,
                  message: l10n.mcpPageServerDeleted,
                  type: NotificationType.info,
                  actionLabel: l10n.mcpPageUndo,
                  onAction: () {
                    if (prev == null) return;
                    Future(() async {
                      final newId = await prov.addServer(
                        enabled: prev.enabled,
                        name: prev.name,
                        transport: prev.transport,
                        url: prev.url,
                        headers: prev.headers,
                      );
                      // 回到前台后尽量刷新一次工具列表
                      try { await prov.refreshTools(newId); } catch (_) {}
                    });
                  },
                );
              },
            ),
          ],
        ),
        child: row,
      ),
    );
  }
}
