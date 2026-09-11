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
