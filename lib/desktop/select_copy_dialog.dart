import 'package:flutter/material.dart';
import '../core/models/chat_message.dart';
import '../l10n/build_context_l10n.dart';
import '../icons/lucide_adapter.dart';
import '../shared/widgets/snackbar.dart';
import 'package:flutter/services.dart';

Future<void> showSelectCopyDesktopDialog(BuildContext context, {required ChatMessage message}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => _SelectCopyDesktopDialog(message: message),
  );
}

class _SelectCopyDesktopDialog extends StatelessWidget {
  const _SelectCopyDesktopDialog({required this.message});
  final ChatMessage message;

  Future<void> _copyAll(BuildContext context) async {
    final l10n = context.l10n;
    await Clipboard.setData(ClipboardData(text: message.content));
    if (!context.mounted) return;
    showAppSnackBar(context, message: l10n.selectCopyPageCopiedAll, type: NotificationType.success);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = context.l10n;
    // no_raw_alert_dialog 白名单：桌面端选词复制窗口，自定义标题栏（全部复制/关闭按钮）+ Expanded 可滚动选中文本区，固定尺寸，不适合 AppDialog
    return Dialog(
      elevation: 12,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 420, maxWidth: 720, maxHeight: 640),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Material(
            color: cs.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                  child: Row(
                    children: [
                      Text(l10n.selectCopyPageTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const Spacer(),
                      TextButton.icon(
                        onPressed: () => _copyAll(context),
                        icon: Icon(Lucide.Copy, size: 18, color: cs.primary),
                        label: Text(l10n.selectCopyPageCopyAll, style: TextStyle(color: cs.primary, fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        tooltip: l10n.mcpPageClose,
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: Icon(Lucide.X, size: 18, color: cs.onSurface.withOpacity(0.75)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : const Color(0xFFF2F3F5),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.outlineVariant.withOpacity(0.18), width: 0.6),
                      ),
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(12),
                          child: SelectionArea(
                            child: Text(
                              message.content,
                              style: const TextStyle(fontSize: 15, height: 1.5),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

