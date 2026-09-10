import 'package:flutter/material.dart';
import 'package:characters/characters.dart';
import '../../l10n/build_context_l10n.dart';
import 'app_dialog.dart';
import 'emoji_text.dart';

/// A reusable emoji picker dialog used by both mobile and desktop.
/// Returns the chosen emoji (single grapheme) or null if cancelled.
Future<String?> showEmojiPickerDialog(
  BuildContext context, {
  String? title,
  String? hintText,
}) async {
  final l10n = context.l10n;
  final controller = TextEditingController();
  String value = '';

  bool validGrapheme(String s) {
    final trimmed = s.characters.take(1).toString().trim();
    return trimmed.isNotEmpty && trimmed == s.trim();
  }

  const List<String> quick = <String>[
    '😀','😁','😂','🤣','😃','😄','😅','😊','😍','😘','😗','😙','😚','🙂','🤗','🤩','🫶','🤝','👍','👎','👋','🙏','💪','🔥','✨','🌟','💡','🎉','🎊','🎈','🌈','☀️','🌙','⭐','⚡','☁️','❄️','🌧️','🍎','🍊','🍋','🍉','🍇','🍓','🍒','🍑','🥭','🍍','🥝','🍅','🥕','🌽','🍞','🧀','🍔','🍟','🍕','🌮','🌯','🍣','🍜','🍰','🍪','🍩','🍫','🍻','☕','🧋','🥤','⚽','🏀','🏈','🎾','🏐','🎮','🎧','🎸','🎹','🎺','📚','✏️','💼','💻','🖥️','📱','🛩️','✈️','🚗','🚕','🚙','🚌','🚀','🛰️','🧠','🫀','💊','🩺','🐶','🐱','🐭','🐹','🐰','🦊','🐻','🐼','🐨','🐯','🦁','🐮','🐷','🐸','🐵'
  ];

  return showDialog<String>(
    context: context,
    builder: (ctx) {
      final cs = Theme.of(ctx).colorScheme;
      return StatefulBuilder(
        builder: (ctx, setLocal) {
          final media = MediaQuery.of(ctx);
          final avail = media.size.height - media.viewInsets.bottom;
          final double gridHeight = (avail * 0.28).clamp(120.0, 220.0);
          return AppDialog(
            title: title ?? l10n.assistantEditEmojiDialogTitle,
            maxWidth: 400,
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.08),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: EmojiText(
                        value.isEmpty ? '🙂' : value.characters.take(1).toString(),
                        fontSize: 40,
                        optimizeEmojiAlign: true,
                        nudge: Offset.zero,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    onChanged: (v) => setLocal(() => value = v),
                    onSubmitted: (_) {
                      if (validGrapheme(value)) {
                        Navigator.of(ctx).pop(value.characters.take(1).toString());
                      }
                    },
                    decoration: InputDecoration(
                      hintText: hintText ?? l10n.assistantEditEmojiDialogHint,
                      filled: true,
                      fillColor: Theme.of(ctx).brightness == Brightness.dark ? Colors.white10 : const Color(0xFFF2F3F5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.transparent),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.transparent),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: cs.primary.withOpacity(0.4)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: gridHeight,
                    child: GridView.builder(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 8,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemCount: quick.length,
                      itemBuilder: (c, i) {
                        final e = quick[i];
                        return InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => Navigator.of(ctx).pop(e),
                          child: Container(
                            decoration: BoxDecoration(
                              color: cs.primary.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: EmojiText(
                              e,
                              fontSize: 20,
                              optimizeEmojiAlign: true,
                              nudge: Offset.zero,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              AppDialog.button(
                label: l10n.assistantEditEmojiDialogCancel,
                kind: AppDialogButtonKind.secondary,
                filled: false,
                onPressed: () => Navigator.of(ctx).pop(),
              ),
              Opacity(
                opacity: validGrapheme(value) ? 1.0 : 0.5,
                child: AbsorbPointer(
                  absorbing: !validGrapheme(value),
                  child: AppDialog.button(
                    label: l10n.assistantEditEmojiDialogSave,
                    onPressed: () => Navigator.of(ctx).pop(value.characters.take(1).toString()),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  ).then((result) => result);
}
