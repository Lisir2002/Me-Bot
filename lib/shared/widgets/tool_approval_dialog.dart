import 'dart:convert';

import 'package:flutter/material.dart';

import '../../core/services/haptics.dart';
import '../../l10n/app_localizations.dart';

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
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, size: 22, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.toolApprovalDialogTitle,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
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
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _DialogButton(
                    label: l10n.toolApprovalDialogDeny,
                    icon: Icons.close,
                    backgroundColor: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                    foregroundColor: cs.error,
                    borderColor: cs.outlineVariant.withOpacity(0.35),
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DialogButton(
                    label: l10n.toolApprovalDialogAllow,
                    icon: Icons.check,
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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

class _DialogButton extends StatelessWidget {
  const _DialogButton({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
    this.borderColor,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        Haptics.light();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: borderColor != null ? Border.all(color: borderColor!) : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: foregroundColor),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: foregroundColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
