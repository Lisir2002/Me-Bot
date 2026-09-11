import 'package:flutter_test/flutter_test.dart';

import 'package:minime_core/core/services/logging/log_sanitizer.dart';

/// P0-1：短密钥必须脱敏 —— 原先 redact 在 text.length < 200 时直接返回原文，
/// 导致 32 字符的裸 API key 明文落盘。
void main() {
  group('LogSanitizer.redact 短密钥脱敏', () {
    test('32 字符裸 sk- 前缀 key 被脱敏，原文不再出现', () {
      // 恰好 32 字符：sk- + 29 位字母数字
      const bareKey = 'sk-abcdEFGH1234wxyzIJKL5678qrst9';
      expect(bareKey.length, 32);

      final out = LogSanitizer.redact('token=$bareKey');

      // 原 key 不得整体出现在结果里
      expect(out.contains(bareKey), isFalse, reason: '裸 key 明文泄露: $out');
      // 必须有脱敏标记
      expect(out, contains('[redacted'));
      // 保留前缀便于排查
      expect(out.startsWith('token=sk-'), isTrue);
    });

    test('短 JSON 中的 api_key 字段被脱敏（不再被 200 阈值放行）', () {
      const shortJson = '{"api_key": "sk-short1234567890abcdef1234"}';
      expect(shortJson.length, lessThan(200));

      final out = LogSanitizer.redact(shortJson);

      expect(out.contains('sk-short1234567890abcdef1234'), isFalse,
          reason: 'api_key 明文泄露: $out');
      expect(out, contains('[redacted'));
    });

    test('短文本中的裸 Bearer 被脱敏', () {
      const msg = 'failed: Bearer abcdef123456zzzz';
      expect(msg.length, lessThan(200));

      final out = LogSanitizer.redact(msg);

      expect(out.contains('abcdef123456zzzz'), isFalse);
      expect(out, contains('[redacted'));
    });

    test('长文本中的 base64 大字段仍被省略（性能保护保留）', () {
      final b64 = 'A' * 500;
      final longText = 'data:image/png;base64,$b64 tail';

      final out = LogSanitizer.redact(longText);

      expect(out, contains('[base64 omitted:'));
      expect(out.contains(b64), isFalse);
    });

    test('普通短文本不误伤', () {
      const plain = 'user logged in, session abc123';
      expect(LogSanitizer.redact(plain), plain);
    });
  });
}
