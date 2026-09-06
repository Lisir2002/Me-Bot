import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mcp_client/mcp_client.dart' as mcp;

import '../../../icons/lucide_adapter.dart';
import '../../../core/providers/mcp_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/ios_tile_button.dart';

/// 工具试调面板：输入参数 → 直接调用 MCP 工具 → 预览返回结果。
/// 设计为内嵌在工具详情页「工具操作」分区中使用。
class McpToolTestPanel extends StatefulWidget {
  const McpToolTestPanel({super.key, required this.serverId, required this.toolName});
  final String serverId;
  final String toolName;

  @override
  State<McpToolTestPanel> createState() => _McpToolTestPanelState();
}

class _McpToolTestPanelState extends State<McpToolTestPanel> {
  late final TextEditingController _argsCtrl;
  bool _running = false;
  bool _showResult = false;
  String? _resultText;
  String? _resultError;

  @override
  void initState() {
    super.initState();
    final tool = _findTool();
    _argsCtrl = TextEditingController(text: _exampleArgs(tool));
  }

  @override
  void dispose() {
    _argsCtrl.dispose();
    super.dispose();
  }

  McpToolConfig? _findTool() {
    final mcp = context.read<McpProvider>();
    final server = mcp.getById(widget.serverId);
    if (server == null) return null;
    for (final t in server.tools) {
      if (t.name == widget.toolName) return t;
    }
    return null;
  }

  String _exampleArgs(McpToolConfig? tool) {
    final schema = tool?.schema;
    final props = (schema?['properties'] is Map)
        ? (schema!['properties'] as Map).cast<String, dynamic>()
        : null;
    if (props == null || props.isEmpty) return '{}';
    final req = (schema?['required'] is List)
        ? (schema!['required'] as List).cast<String>()
        : const <String>[];
    final sample = <String, dynamic>{};
    props.forEach((key, spec) {
      if (spec is! Map) return;
      final type = spec['type'];
      final val = spec['default'];
      dynamic v;
      if (val != null) {
        v = val;
      } else if (type == 'integer' || type == 'number') {
        v = 0;
      } else if (type == 'boolean') {
        v = false;
      } else if (type == 'array') {
        v = const [];
      } else if (type == 'object') {
        v = const {};
      } else if (req.contains(key)) {
        v = '';
      } else {
        v = '';
      }
      sample[key] = v;
    });
    return const JsonEncoder.withIndent('  ').convert(sample);
  }

  Future<void> _run() async {
    Map<String, dynamic> args;
    try {
      final decoded = jsonDecode(_argsCtrl.text.trim());
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('expected JSON object');
      }
      args = decoded;
    } catch (e) {
      final l10n = AppLocalizations.of(context)!;
      if (mounted) {
        setState(() {
          _showResult = true;
          _resultError = l10n.mcpToolTestInvalidJson;
        });
      }
      return;
    }
    setState(() {
      _running = true;
      _showResult = false;
      _resultText = null;
      _resultError = null;
    });
    final mcp = context.read<McpProvider>();
    final res = await mcp.callTool(widget.serverId, widget.toolName, args);
    if (!mounted) return;
    setState(() {
      _running = false;
      _showResult = true;
      if (res == null) {
        _resultError = mcp.errorFor(widget.serverId) ?? 'Unknown error';
      } else {
        _resultText = _flattenResult(res);
      }
    });
  }

  String _flattenResult(mcp.CallToolResult res) {
    final buf = StringBuffer();
    for (final c in res.content) {
      if (c is mcp.TextContent) {
        buf.writeln(c.text);
        continue;
      }
      if (c is mcp.ResourceContent) {
        final t = (c.text ?? '').toString();
        if (t.trim().isNotEmpty) {
          buf.writeln(t);
        } else {
          buf.writeln('resource: ${c.uri}');
        }
        continue;
      }
      if (c is mcp.ImageContent) {
        final u = c.url;
        buf.writeln(u != null && u.isNotEmpty ? '[image: ${c.mimeType}: $u]' : '[image: ${c.mimeType}]');
        continue;
      }
      buf.writeln(c.toString());
    }
    return buf.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final tool = _findTool();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.mcpToolTestArgsLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
          ),
          child: TextField(
            controller: _argsCtrl,
            maxLines: 8,
            minLines: 4,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
            decoration: InputDecoration(
              hintText: '{}',
              hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.4)),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l10n.mcpToolTestArgsHint,
          style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.55)),
        ),
        const SizedBox(height: 16),
        if (tool?.description != null && (tool!.description ?? '').isNotEmpty) ...[
          Text(tool.description!, style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.7))),
          const SizedBox(height: 16),
        ],
        if (_showResult) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark
                  ? (cs.error.withOpacity(0.15))
                  : (_resultError != null ? cs.error.withOpacity(0.08) : const Color(0xFFF2F3F5)),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: (_resultError != null ? cs.error : cs.primary).withOpacity(0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      _resultError != null ? Lucide.CircleX : Lucide.Check,
                      size: 16,
                      color: _resultError != null ? cs.error : Colors.green,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _resultError != null ? l10n.mcpToolTestFailed : l10n.mcpToolTestSuccess,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _resultError != null ? cs.error : Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SelectableText(
                  _resultError ?? _resultText ?? '',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: cs.onSurface.withOpacity(0.9),
                    fontFamily: _resultError == null ? 'monospace' : null,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
        SizedBox(
          width: double.infinity,
          child: Stack(
            children: [
              IosTileButton(
                icon: Lucide.Play,
                label: _running ? l10n.mcpToolTestRunning : l10n.mcpToolTestRun,
                backgroundColor: cs.primary,
                onTap: _running ? () {} : _run,
              ),
              if (_running)
                Positioned.fill(
                  child: Container(color: cs.surface.withOpacity(0.4)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}