/// 凭证明文模式探测器（PR-5）。
///
/// 用于「明文残留 / 日志文件」扫描器：在一串文本里找是否疑似含有 API Key。
/// 采用**多模式白名单 + 高熵兜底**策略，并基于样本集测试，避免把正常文本误判成密钥。
///
/// 铁律：本类只返回「模式名 + 命中位点数量」，**绝不回传命中的明文片段**。
class SecretDetector {
  SecretDetector._();

  /// 已知前缀模式（取自主流服务商的 Key 形态）。
  /// 顺序即优先级；命中任意一个即判定「疑似明文 Key」。
  static final List<_Pattern> _patterns = [
    _Pattern('sk-', RegExp(r'\bsk-[A-Za-z0-9]{20,}\b')), // OpenAI
    _Pattern('AKIA', RegExp(r'\bAKIA[0-9A-Z]{16}\b')), // AWS
    _Pattern('ghp_', RegExp(r'\bgh[pousr]_[A-Za-z0-9]{36,}\b')), // GitHub
    _Pattern('xoxb-', RegExp(r'\bxox[baprs]-[A-Za-z0-9-]{10,}\b')), // Slack
    // Google：AIza + 35 位，字符集含大小写（真实 Key 大小写混合）
    _Pattern('AIza', RegExp(r'\bAIza[A-Za-z0-9_-]{30,40}\b')),
    _Pattern('eyJ', RegExp(r'\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b')), // JWT
  ];

  /// 高熵串阈值：长度足够长且字符集分散的疑似随机串。
  static final RegExp _highEntropy =
      RegExp(r'[A-Za-z0-9+/=_-]{40,}');

  /// 在 [text] 中探测疑似明文 Key。返回命中的模式名（无则 null）。
  ///
  /// [sampleForTest] 仅测试用，允许注入固定文本；默认用 [text]。
  static String? detect(String text) {
    if (text.isEmpty) return null;
    for (final p in _patterns) {
      if (p.regex.hasMatch(text)) return p.name;
    }
    // 高熵兜底：仅当整段存在足够长的随机串才报（避免普通长单词误报）。
    // 用「命中且其中字母/数字混合比例高」进一步收敛。
    final m = _highEntropy.firstMatch(text);
    if (m != null) {
      final token = m.group(0)!;
      if (_looksRandom(token)) return 'high-entropy';
    }
    return null;
  }

  /// 统计 [text] 中命中的模式数量（用于报告「发现 N 处疑似明文」）。
  static int countMatches(String text) {
    if (text.isEmpty) return 0;
    var n = 0;
    for (final p in _patterns) {
      n += p.regex.allMatches(text).length;
    }
    if (_looksRandomInText(text)) n += 1;
    return n;
  }

  static bool _looksRandomInText(String text) =>
      _highEntropy.hasMatch(text) && _looksRandom(_highEntropy.firstMatch(text)!.group(0)!);

  /// 简易熵估计：同时含字母与数字/符号且无明显自然语言单词 → 视为随机串。
  static bool _looksRandom(String token) {
    if (token.length < 40) return false;
    final hasLower = token.contains(RegExp(r'[a-z]'));
    final hasUpper = token.contains(RegExp(r'[A-Z]'));
    final hasDigit = token.contains(RegExp(r'[0-9]'));
    final hasSpecial = token.contains(RegExp(r'[+/=_-]'));
    // 至少两类字符集混合，且不是纯 URL/路径（含明显分隔符单词）
    final mixedClasses = [hasLower, hasUpper, hasDigit, hasSpecial].where((b) => b).length;
    if (mixedClasses < 2) return false;
    // 排除像「abcdefghijklmnopqrstuvwxyz0123456789」这种规律序列（极端兜底）
    if (token == token.toLowerCase() && token.contains(RegExp(r'[aeiou]{4,}'))) return false;
    return true;
  }
}

class _Pattern {
  const _Pattern(this.name, this.regex);
  final String name;
  final RegExp regex;
}
