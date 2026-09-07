import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_switch.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../shared/widgets/app_states.dart';
import '../widgets/mcp_tool_test_sheet.dart';

/// 工具详情独立页：顶栏 Tab「工具操作 / 操作记录」。
class McpToolDetailPage extends StatelessWidget {
  const McpToolDetailPage({super.key, required this.serverId, required this.toolName});
  final String serverId;
  final String toolName;

  McpToolConfig? _findTool(List<McpToolConfig> tools) {
    for (final t in tools) {
      if (t.name == toolName) return t;
    }
    return null;
  }

  Widget _card(BuildContext context, {required List<Widget> children}) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
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
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final mcp = context.watch<McpProvider>();
    final server = mcp.getById(serverId);
    final tool = server == null ? null : _findTool(server.tools);

    if (tool == null) {
      return AppPage(
        title: toolName,
        body: AppEmpty(
          message: l10n.mcpToolDetailNotFound,
          icon: Icons.search_off_rounded,
        ),
      );
    }

    final toolSnap = tool;
    return AppPage(
      title: tool.name,
      segmentsMode: AppSegmentMode.top,
      segments: [
        AppSegment(
          label: l10n.mcpToolDetailTabActions,
          body: (ctx) => _buildActionsTab(ctx, toolSnap),
        ),
        AppSegment(
          label: l10n.mcpToolDetailTabHistory,
          body: (ctx) => _buildHistoryTab(ctx, toolSnap),
        ),
      ],
    );
  }

  Widget _buildActionsTab(BuildContext context, McpToolConfig tool) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    Widget _sectionTitle(String t) => Padding(
          padding: const EdgeInsets.only(top: 20, bottom: 10),
          child: Text(t, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        );

    String schemaText;
    try {
      schemaText = const JsonEncoder.withIndent('  ').convert(tool.schema);
    } catch (_) {
      schemaText = tool.schema.toString();
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        // ---- 描述 + 参数 ----
        _card(context, children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: cs.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Lucide.Wrench, size: 20, color: cs.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tool.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      if ((tool.description ?? '').isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(tool.description!, style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.7))),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (tool.params.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Wrap(
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
            ),
        ]),
        const SizedBox(height: 14),

        // ---- 开关 ----
        _card(context, children: [
          _SwitchRow(
            icon: tool.enabled ? Lucide.Check : Lucide.EyeOff,
            iconColor: tool.enabled ? Colors.green : cs.onSurface.withOpacity(0.5),
            label: l10n.mcpToolEnableLabel,
            value: tool.enabled,
            onChanged: (v) => context.read<McpProvider>().setToolEnabled(serverId, tool.name, v),
          ),
          _SwitchRow(
            icon: tool.requireApproval ? Lucide.Shield : Lucide.EyeOff,
            iconColor: tool.requireApproval ? cs.primary : cs.onSurface.withOpacity(0.5),
            label: l10n.mcpToolRequireApprovalLabel,
            value: tool.requireApproval,
            onChanged: (v) => context.read<McpProvider>().setToolRequireApproval(serverId, tool.name, v),
          ),
        ]),
        const SizedBox(height: 14),

        // ---- Schema ----
        _sectionTitle(l10n.mcpToolSchema),
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
        const SizedBox(height: 14),

        // ---- 调用测试 ----
        _sectionTitle(l10n.mcpToolTestShort),
        McpToolTestPanel(serverId: serverId, toolName: tool.name),
      ],
    );
  }

  Widget _buildHistoryTab(BuildContext context, McpToolConfig tool) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final history = context
        .watch<McpProvider>()
        .toolCallHistory(serverId)
        .where((r) => r.toolName == tool.name)
        .toList();

    if (history.isEmpty) {
      return Center(
        child: Text(l10n.mcpDetailNoHistory, style: TextStyle(color: cs.onSurface.withOpacity(0.6), fontSize: 13)),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        _card(context, children: [
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _formatTime(rec.time),
                        style: TextStyle(fontSize: 11, color: cs.onSurface.withOpacity(0.5)),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: (rec.isError ? cs.error : Colors.green).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          '${rec.durationMs}ms',
                          style: TextStyle(
                            fontSize: 10,
                            color: rec.isError ? cs.error : Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ]),
      ],
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

/// 卡片内的一行开关（用于工具详情操作页）。
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({required this.icon, required this.iconColor, required this.label, required this.value, required this.onChanged});
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ),
          IosSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}