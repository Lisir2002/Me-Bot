import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/services/haptics.dart';
import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/ios_tile_button.dart';
import '../widgets/mcp_server_edit_sheet.dart';
import '../widgets/mcp_tool_test_sheet.dart';

/// 服务器详情独立页：概览 / 工具 / 调用记录 分区。
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final mcp = context.watch<McpProvider>();
    final server = mcp.getById(serverId);
    if (server == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('MCP')),
        body: Center(child: Text(l10n.mcpPageNoServers)),
      );
    }
    final st = mcp.statusFor(serverId);
    final err = mcp.errorFor(serverId);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isBuiltin = server.transport == McpTransportType.inmemory;
    final history = mcp.toolCallHistory(serverId);

    Widget _card({required List<Widget> children}) => Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : Colors.white.withOpacity(0.96),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withOpacity(isDark ? 0.1 : 0.08), width: 0.6),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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

    Widget _row({required String label, required String value, Color? valueColor}) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 14, color: cs.onSurface.withOpacity(0.6))),
              const SizedBox(width: 12),
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

    Widget _sectionTitle(String t) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 10),
          child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        );

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: Tooltip(
          message: l10n.mcpPageBackTooltip,
          child: IconButton(
            icon: const Icon(Lucide.ArrowLeft),
            color: cs.onSurface,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(server.name),
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
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // ---- 概览卡片 ----
          _card(children: [
            // 头部：状态圆点 + 名称 + 传输类型
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
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
                              : (server.enabled ? l10n.mcpDetailStatusDisconnected : l10n.mcpPageStatusDisabled)),
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Wrap(
                          textDirection: TextDirection.ltr,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: cs.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Lucide.Terminal, size: 12, color: Colors.green),
                                  const SizedBox(width: 5),
                                  Text(
                                    server.transport == McpTransportType.inmemory
                                        ? l10n.mcpTransportTagInmemory
                                        : (server.transport == McpTransportType.sse ? 'SSE' : (server.transport == McpTransportType.stdio ? 'STDIO' : 'HTTP')),
                                    style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                ],
              ),
            ),
            _row(label: isBuiltin ? l10n.mcpDetailIdLabel : l10n.mcpDetailUrlLabel,
                value: isBuiltin ? server.id : (server.url.isEmpty ? '-' : server.url)),
            _row(label: l10n.mcpDetailToolsCountLabel,
                value: l10n.mcpPageToolsCount(server.tools.where((t) => t.enabled).length, server.tools.length)),
            if (isBuiltin)
              _row(label: l10n.mcpDetailBuiltinLabel, value: l10n.mcpDetailBuiltinYes, valueColor: Colors.green),
            if (!server.enabled)
              _row(label: l10n.mcpDetailEnabledLabel, value: l10n.mcpDetailDisabled, valueColor: Colors.redAccent),
          ]),

          // ---- 错误信息 ----
          if (st == McpStatus.error && (err?.isNotEmpty ?? false)) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? cs.error.withOpacity(0.15) : cs.error.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.error.withOpacity(0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Lucide.MessageCircleWarning, size: 16, color: cs.error),
                  const SizedBox(width: 8),
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

          _sectionTitle(l10n.mcpDetailToolsSection),

          // ---- 工具列表 ----
          if (server.tools.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text(l10n.mcpServerEditSheetNoToolsHint, style: TextStyle(color: cs.onSurface.withOpacity(0.6)))),
            )
          else
            ...server.tools.map((tool) => _toolCard(context, tool, serverId)).toList(),

          _sectionTitle(l10n.mcpDetailHistorySection),

          // ---- 最近调用记录 ----
          if (history.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(l10n.mcpDetailNoHistory, style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 13)),
              ),
            )
          else
            _card(children: [
              for (final rec in history.reversed.take(20).toList())
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(rec.isError ? Lucide.CircleX : Lucide.Check,
                          size: 16, color: rec.isError ? cs.error : Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(rec.toolName, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                            const SizedBox(height: 2),
                            Text(
                              rec.isError ? (rec.error ?? '') : _truncate(rec.result ?? ''),
                              style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7), height: 1.4),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(rec.time),
                        style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5)),
                      ),
                    ],
                  ),
                ),
            ]),
        ],
      ),
    );
  }

  Widget _toolCard(BuildContext context, McpToolConfig tool, String serverId) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : const Color(0xFFF7F7F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Lucide.Wrench, size: 14, color: cs.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(tool.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                    if ((tool.description ?? '').isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(tool.description!, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
                    ],
                    if (tool.params.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: tool.params.map((p) {
                          final color = p.required ? cs.primary : cs.onSurface.withOpacity(0.5);
                          final bg = p.required ? cs.primary.withOpacity(0.12) : cs.onSurface.withOpacity(0.06);
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: color.withOpacity(0.5)),
                            ),
                            child: Text(p.name, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.mcpToolEnableLabel, style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.6))),
                      const SizedBox(width: 6),
                      IosSwitch(
                        value: tool.enabled,
                        onChanged: (v) => context.read<McpProvider>().setToolEnabled(serverId, tool.name, v),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(l10n.mcpToolRequireApprovalLabel, style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.6))),
                      const SizedBox(width: 6),
                      IosSwitch(
                        value: tool.requireApproval,
                        onChanged: (v) => context.read<McpProvider>().setToolRequireApproval(serverId, tool.name, v),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 底部操作行：试调 / Schema
          Row(
            children: [
              Expanded(
                child: _MiniActionButton(
                  icon: Lucide.Play,
                  label: l10n.mcpToolTestShort,
                  onTap: () => showMcpToolTestSheet(context, serverId: serverId, toolName: tool.name),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MiniActionButton(
                  icon: Lucide.FileText,
                  label: l10n.mcpToolSchema,
                  onTap: () => showMcpToolSchemaSheet(context, tool: tool),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _truncate(String s, {int n = 120}) =>
      s.length > n ? '${s.substring(0, n)}...' : s;

  String _formatTime(DateTime t) {
    final now = DateTime.now();
    final d = now.difference(t);
    if (d.inSeconds < 60) return '${d.inSeconds}s';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }
}

/// 工具卡片上的小按钮。
class _MiniActionButton extends StatelessWidget {
  const _MiniActionButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.light();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: cs.primary.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cs.primary.withOpacity(0.35)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: cs.primary),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(fontSize: 12, color: cs.primary, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

/// Schema 详情底部弹窗。
Future<void> showMcpToolSchemaSheet(BuildContext context, {required McpToolConfig tool}) async {
  final cs = Theme.of(context).colorScheme;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: cs.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (_) => _McpToolSchemaSheet(tool: tool),
  );
}

class _McpToolSchemaSheet extends StatelessWidget {
  const _McpToolSchemaSheet({required this.tool});
  final McpToolConfig tool;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String schemaText;
    try {
      schemaText = const JsonEncoder.withIndent('  ').convert(tool.schema);
    } catch (_) {
      schemaText = tool.schema.toString();
    }
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          builder: (context, controller) => Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: cs.onSurface.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 36,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.center,
                      child: Text(
                        l10n.mcpToolSchemaTitle(tool.name),
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            Haptics.light();
                            Navigator.of(context).maybePop();
                          },
                          child: const Padding(
                            padding: EdgeInsets.all(6),
                            child: Icon(Lucide.X, size: 20),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    if ((tool.description ?? '').isNotEmpty) ...[
                      Text(tool.description!, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.8))),
                      const SizedBox(height: 12),
                    ],
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
                      ),
                      child: SelectableText(
                        schemaText,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12, height: 1.5),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Lucide.Check, size: 14, color: tool.enabled ? Colors.green : cs.onSurface.withOpacity(0.4)),
                        const SizedBox(width: 6),
                        Text(
                          tool.enabled ? l10n.mcpToolSchemaEnabled : l10n.mcpToolSchemaDisabled,
                          style: TextStyle(
                            fontSize: 13,
                            color: tool.enabled ? Colors.green : cs.onSurface.withOpacity(0.5),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Icon(tool.requireApproval ? Lucide.Shield : Lucide.EyeOff,
                            size: 14,
                            color: tool.requireApproval ? cs.primary : cs.onSurface.withOpacity(0.4)),
                        const SizedBox(width: 6),
                        Text(
                          tool.requireApproval ? l10n.mcpToolSchemaRequiresApproval : l10n.mcpToolSchemaNoApproval,
                          style: TextStyle(
                            fontSize: 13,
                            color: tool.requireApproval ? cs.primary : cs.onSurface.withOpacity(0.5),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}