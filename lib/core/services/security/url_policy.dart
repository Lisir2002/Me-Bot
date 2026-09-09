import 'policy_provider.dart';

/// WebView URL 守卫（PR-8）。
///
/// 共享守卫，同时接入 `webview_flutter` 与 `webview_windows` 两条路径
/// （在 `WebViewPage` 的 NavigationDelegate 里调用）。
///
/// 规则（与验收矩阵对齐）：
/// - `file://`、`javascript:`、`data:` 等危险 scheme **一律拦截**（无论是否启用策略）；
/// - `https:` 默认放行（安全传输）；
/// - `http:` 默认拦截，除非策略开启 [PolicyProvider.allowWebViewHttp] 或命中例外主机；
/// - 例外主机（[PolicyProvider.allowedWebViewHosts]）用于放行特定的 http 源。
///
/// 拦截行为由调用方记审计日志（[LogTags.policy]）。
class UrlGuard {
  UrlGuard(this.provider);

  final PolicyProvider provider;

  /// 永远不允许用于网页渲染的 scheme。
  static const Set<String> _blockedSchemes = {
    'file',
    'javascript',
    'data',
    'content',
  };

  UrlGuardResult check(Uri uri) {
    final scheme = uri.scheme.toLowerCase();

    // 危险 scheme 硬拦截（不可被任何开关绕过）
    if (_blockedSchemes.contains(scheme)) {
      return UrlGuardResult.deny('危险 scheme 被拦截: $scheme');
    }

    if (scheme == 'https') return UrlGuardResult.allow();

    if (scheme == 'http') {
      if (provider.allowedWebViewHosts.contains(uri.host)) {
        return UrlGuardResult.allow();
      }
      if (provider.allowWebViewHttp) return UrlGuardResult.allow();
      return UrlGuardResult.deny('仅允许 https（http 被拦截）');
    }

    // 其它 scheme（tel/mailto 等）放行，不在此守卫范围内
    return UrlGuardResult.allow();
  }

  /// 便捷：直接判断一个 url 字符串。
  UrlGuardResult checkString(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return UrlGuardResult.deny('无法解析的 URL');
    return check(uri);
  }
}

/// URL 守卫裁决。
class UrlGuardResult {
  const UrlGuardResult._(this.allowed, this.reason);
  factory UrlGuardResult.allow() => const UrlGuardResult._(true, '');
  factory UrlGuardResult.deny(String reason) => UrlGuardResult._(false, reason);

  final bool allowed;
  final String reason;

  bool get denied => !allowed;
}
