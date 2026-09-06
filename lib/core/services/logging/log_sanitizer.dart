import 'dart:convert';

/// 日志脱敏工具（Logger 和 FileAppender 共用，避免重复逻辑）。
class LogSanitizer {
  LogSanitizer._();

  /// 脱敏长 base64 字符串、超长 JSON、API key 字段。
  static String redact(String text) {
    if (text.length < 200) return text;
    var out = text;
    // data:image/xxx;base64,AA...AA → 省略
    out = out.replaceAllMapped(
      RegExp(r'data:[a-zA-Z0-9._/-]+;base64,([A-Za-z0-9+/=]{200,})'),
      (m) => 'data:${m.group(1)!.substring(0, 20)}[base64 omitted: ${m.group(1)!.length} chars]',
    );
    // JSON 里的 base64 大字段
    out = out.replaceAllMapped(
      RegExp(r'"([a-zA-Z_]+)"\s*:\s*"([A-Za-z0-9+/=]{200,})"'),
      (m) => '"${m.group(1)}": "[base64 omitted: ${m.group(2)!.length} chars]"',
    );
    // Bearer / Authorization / api_key / secret
    out = out.replaceAllMapped(
      RegExp(
        r'"(?:Authorization|Bearer|api[_-]?key|apikey|x-api-key|secret|token)"\s*:\s*"([^"]{4,})"',
        caseSensitive: false,
      ),
      (m) {
        final key = m.group(1)!;
        final masked =
            key.length <= 8 ? '[redacted]' : '${key.substring(0, 4)}[redacted len=${key.length}]${key.substring(key.length - 4)}';
        return '"${m.group(1)}": "$masked"';
      },
    );
    // 裸 Bearer 字符串
    out = out.replaceAllMapped(
      RegExp(r'(Bearer\s+)([A-Za-z0-9_\-\.]{10,})'),
      (m) {
        final tok = m.group(2)!;
        final masked =
            tok.length <= 12 ? '[redacted]' : '${tok.substring(0, 4)}[redacted len=${tok.length}]${tok.substring(tok.length - 4)}';
        return '${m.group(1)}$masked';
      },
    );
    return out;
  }

  static String truncate(String text, {int max = 4000}) {
    if (text.length <= max) return text;
    return '${text.substring(0, max)}\n  ... [truncated ${text.length - max} chars]';
  }

  /// 安全地把 error 转成脱敏后的字符串（error.toString() 可能抛）。
  static String safeErrorString(Object? error) {
    if (error == null) return '';
    try {
      return redact(error.toString());
    } catch (_) {
      return '[error.toString() threw: ${error.runtimeType}]';
    }
  }

  /// 安全地把 stack 转成前 N 行（stack.toString() 可能抛）。
  static String? safeStackPreview(StackTrace? stack, {int maxLines = 20}) {
    if (stack == null) return null;
    try {
      final lines = stack.toString().split('\n');
      final buf = StringBuffer();
      for (var i = 0; i < lines.length && i < maxLines; i++) {
        buf.writeln('  ${lines[i]}');
      }
      return buf.toString().trimRight();
    } catch (_) {
      return '[stack.toString() threw]';
    }
  }
}
