import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../../core/models/assistant.dart';
import '../../../utils/sandbox_path_resolver.dart';
import '../../../utils/avatar_cache.dart';
import '../../../shared/widgets/emoji_text.dart';

/// 助手头像渲染：支持 URL / 本地文件 / emoji / 首字母默认头像
Widget buildAssistantAvatar(
  BuildContext context,
  Assistant? a, {
  double size = 28,
  VoidCallback? onTap,
}) {
  final cs = Theme.of(context).colorScheme;
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final av = a?.avatar?.trim() ?? '';
  final name = a?.name ?? '';

  Widget avatar;
  if (av.isNotEmpty) {
    if (av.startsWith('http')) {
      avatar = FutureBuilder<String?>(
        future: AvatarCache.getPath(av),
        builder: (ctx, snap) {
          final p = snap.data;
          if (p != null && File(p).existsSync()) {
            return ClipOval(
              child: Image(
                image: FileImage(File(p)),
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
            );
          }
          return ClipOval(
            child: Image.network(
              av,
              width: size,
              height: size,
              fit: BoxFit.cover,
              errorBuilder: (c, e, s) => _initialAvatar(cs, name, size),
            ),
          );
        },
      );
    } else if (!kIsWeb && (av.startsWith('/') || av.contains(':'))) {
      final fixed = SandboxPathResolver.fix(av);
      final f = File(fixed);
      if (f.existsSync()) {
        avatar = ClipOval(
          child: Image(
            image: FileImage(f),
            width: size,
            height: size,
            fit: BoxFit.cover,
          ),
        );
      } else {
        avatar = _initialAvatar(cs, name, size);
      }
    } else {
      avatar = _emojiAvatar(cs, av, size);
    }
  } else {
    avatar = _initialAvatar(cs, name, size);
  }

  // 加边框
  final child = Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: isDark ? Colors.white24 : Colors.black12,
        width: 0.5,
      ),
    ),
    child: avatar,
  );

  if (onTap == null) return child;
  return InkWell(
    onTap: onTap,
    customBorder: const CircleBorder(),
    child: child,
  );
}

Widget _initialAvatar(ColorScheme cs, String name, double size) {
  final letter = name.isNotEmpty ? name.characters.first : '?';
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: cs.primary.withOpacity(0.15),
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: Text(
      letter,
      style: TextStyle(
        color: cs.primary,
        fontSize: size * 0.42,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

Widget _emojiAvatar(ColorScheme cs, String emoji, double size) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: cs.primary.withOpacity(0.15),
      shape: BoxShape.circle,
    ),
    alignment: Alignment.center,
    child: EmojiText(
      emoji.characters.take(1).toString(),
      fontSize: size * 0.5,
      optimizeEmojiAlign: true,
    ),
  );
}
