import 'dart:convert';

import 'package:flutter/material.dart';

import '../../l10n/build_context_l10n.dart';
import 'app_dialog.dart';

/// 工具调用审批弹窗。
/// 返回 true 表示用户允许执行该工具，false 表示拒绝。
Future<bool> showToolApprovalDialog(
  BuildContext context, {
  required String toolName,
  required Map<String, dynamic> arguments,
  String? serverName,
}) async {
  final allowed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _ToolApprovalDialog(
      toolName: toolName,
      arguments: arguments,
      serverName: serverName,
    ),
  );
  return allowed ?? false;
}

class _ToolApprovalDialog extends StatelessWidget {
  const _ToolApprovalDialog({
    required this.toolName,
    required this.arguments,
    this.serverName,
  });

  final String toolName;
  final Map<String, dynamic> arguments;
  final String? serverName;

  String get _argsPreview {
    try {
      return const JsonEncoder.withIndent('  ').convert(arguments);
    } catch (_) {
      return arguments.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AppDialog(
      title: l10n.toolApprovalDialogTitle,
      titleIcon: Icons.shield_outlined,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (serverName != null && serverName!.isNotEmpty) ...[
            _LabelRow(label: l10n.toolApprovalDialogServer, value: serverName!),
            const SizedBox(height: 8),
          ],
          _LabelRow(label: l10n.toolApprovalDialogTool, value: toolName),
          const SizedBox(height: 12),
          Text(
            l10n.toolApprovalDialogHint,
            style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.7)),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 220),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                _argsPreview,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.5,
                  color: cs.onSurface.withOpacity(0.9),
                ),
              ),
            ),
          ),
        ],
      ),
      actions: [
        Expanded(
          child: AppDialog.button(
            label: l10n.toolApprovalDialogDeny,
            kind: AppDialogButtonKind.danger,
            filled: false,
            onPressed: () => Navigator.of(context).pop(false),
          ),
        ),
        Expanded(
          child: AppDialog.button(
            label: l10n.toolApprovalDialogAllow,
            kind: AppDialogButtonKind.primary,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ),
      ],
    );
  }
}

class _LabelRow extends StatelessWidget {
  const _LabelRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

// ──────────────────────────────────────────────────────────────
// 非经典样式下的完整三选项审批弹窗
//
// 视觉复用 [AppDialog] 与既有 toolApprovalDialog* 文案，仅补充三选项决策：
//   允许一次 / 本会话始终允许 / 拒绝（可附原因，反馈给模型）。
// 与经典流程的 [showToolApprovalDialog]（返回 bool）并存，互不影响。
// ──────────────────────────────────────────────────────────────

/// 工具审批决策结果。
sealed class ToolApprovalDecision {
  const ToolApprovalDecision();
}

/// 允许本次执行（仅一次）。
class ToolApprovalAllowOnce extends ToolApprovalDecision {
  const ToolApprovalAllowOnce();
}

/// 本会话始终允许同类操作。
class ToolApprovalAlwaysAllow extends ToolApprovalDecision {
  const ToolApprovalAlwaysAllow();
}

/// 拒绝执行，[reason] 为可选原因（会反馈给模型）。
class ToolApprovalRejected extends ToolApprovalDecision {
  const ToolApprovalRejected(this.reason);

  final String? reason;
}

/// 弹出完整三选项审批对话框。
///
/// [toolName] 操作名（对应 ApprovalPart.action），[description] 操作描述，
/// [details] 详细键值信息（以只读预览展示），[serverName] 可选 MCP 服务名。
/// 返回用户决策；用户直接关闭（barrier 不可点关闭，此分支实际不会发生）时为 null。
Future<ToolApprovalDecision?> showRichToolApprovalDialog(
  BuildContext context, {
  required String toolName,
  required String description,
  Map<String, dynamic> details = const {},
  String? serverName,
}) {
  return showDialog<ToolApprovalDecision>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _RichToolApprovalDialog(
      toolName: toolName,
      description: description,
      details: details,
      serverName: serverName,
    ),
  );
}

class _RichToolApprovalDialog extends StatefulWidget {
  const _RichToolApprovalDialog({
    required this.toolName,
    required this.description,
    required this.details,
    this.serverName,
  });

  final String toolName;
  final String description;
  final Map<String, dynamic> details;
  final String? serverName;

  @override
  State<_RichToolApprovalDialog> createState() =>
      _RichToolApprovalDialogState();
}

class _RichToolApprovalDialogState extends State<_RichToolApprovalDialog> {
  late final TextEditingController _reasonController;

  @override
  void initState() {
    super.initState();
    _reasonController = TextEditingController();
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  String get _detailsPreview {
    if (widget.details.isEmpty) return '';
    try {
      return const JsonEncoder.withIndent('  ').convert(widget.details);
    } catch (_) {
      return widget.details.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final detailsPreview = _detailsPreview;

    return AppDialog(
      title: l10n.toolApprovalDialogTitle,
      titleIcon: Icons.shield_outlined,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.serverName != null && widget.serverName!.isNotEmpty) ...[
            _LabelRow(label: l10n.toolApprovalDialogServer, value: widget.serverName!),
            const SizedBox(height: 8),
          ],
          _LabelRow(label: l10n.toolApprovalDialogTool, value: widget.toolName),
          const SizedBox(height: 12),
          Text(
            l10n.toolApprovalDialogHint,
            style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.7)),
          ),
          const SizedBox(height: 8),
          // 操作描述
          Text(
            widget.description,
            style: const TextStyle(fontSize: 14, height: 1.5),
          ),
          if (detailsPreview.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 180),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.3)),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  detailsPreview,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    height: 1.5,
                    color: cs.onSurface.withOpacity(0.9),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          // 拒绝原因（可选）——仅拒绝时会被采纳并反馈给模型
          Text(
            l10n.convStyleApprovalReasonLabel,
            style: TextStyle(fontSize: 13, color: cs.onSurface.withOpacity(0.6)),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _reasonController,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: l10n.convStyleApprovalReasonHint,
              hintStyle: TextStyle(color: cs.onSurface.withOpacity(0.4)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: cs.primary, width: 1.5),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
          ),
        ],
      ),
      actions: [
        // 三个决策：上行 拒绝 / 允许一次；下行 本会话始终允许
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: AppDialog.button(
                      label: l10n.toolApprovalDialogDeny,
                      kind: AppDialogButtonKind.danger,
                      filled: false,
                      onPressed: () {
                        final reason = _reasonController.text.trim();
                        Navigator.of(context).pop(
                          ToolApprovalRejected(reason.isEmpty ? null : reason),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: AppDialog.button(
                      label: l10n.convStyleApprovalAllowOnce,
                      kind: AppDialogButtonKind.primary,
                      onPressed: () => Navigator.of(context).pop(
                        const ToolApprovalAllowOnce(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: AppDialog.button(
                  label: l10n.convStyleApprovalAlwaysAllow,
                  kind: AppDialogButtonKind.secondary,
                  filled: false,
                  onPressed: () => Navigator.of(context).pop(
                    const ToolApprovalAlwaysAllow(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
