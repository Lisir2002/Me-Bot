import 'package:flutter/material.dart';

import '../../../core/models/chat_message.dart';
import '../../../l10n/app_localizations.dart';
import '../../../shared/widgets/app_page.dart';
import '../../../theme/design_tokens.dart';

/// 消息编辑页。
///
/// 已迁移到 AppPage 槽位骨架：
/// - Scaffold + AppBar + SafeArea → AppPage(title/actions/body)
/// - padding all(16) → AppPagePadding.all；圆角 12 → AppRadius.md
/// - ⚠️ TextField 为 maxLines: null 的自增输入框，放进取不到有界高度的 ListView 有风险，
///   故 scrollable: false，保持与原实现一致的布局约束
/// - 顺带移除未使用的 lucide_adapter import（消除 analyze 警告）
class MessageEditPage extends StatefulWidget {
  const MessageEditPage({super.key, required this.message});
  final ChatMessage message;

  @override
  State<MessageEditPage> createState() => _MessageEditPageState();
}

class _MessageEditPageState extends State<MessageEditPage> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.message.content);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return AppPage(
      title: l10n.messageEditPageTitle,
      scrollable: false,
      bodyPadding: AppPagePadding.all,
      actions: [
        TextButton(
          onPressed: () {
            final text = _controller.text.trim();
            Navigator.of(context).pop<String>(text);
          },
          child: Text(
            l10n.messageEditPageSave,
            style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
          ),
        ),
      ],
      body: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.multiline,
        minLines: 8,
        maxLines: null,
        decoration: InputDecoration(
          hintText: l10n.messageEditPageHint,
          filled: true,
          fillColor: Theme.of(context).brightness == Brightness.dark
              ? Colors.white10
              : const Color(0xFFF2F3F5),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: Colors.transparent),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: const BorderSide(color: Colors.transparent),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
            borderSide: BorderSide(color: cs.primary.withOpacity(0.45)),
          ),
        ),
      ),
    );
  }
}
