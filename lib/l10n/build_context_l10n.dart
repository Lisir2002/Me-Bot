import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

/// 用法：`context.l10n.someKey`
///
/// 约定：仅在 build / 回调执行时现取，禁止缓存到字段或 initState ——
/// 语言切换依赖 MaterialApp.locale 变更后重新 build，缓存会导致文案不刷新。
/// （工具链：custom_lint `l10n_no_field_cache` 会拦截字段缓存。）
extension BuildContextL10n on BuildContext {
  /// 非 null 快捷入口（l10n.yaml `nullable-getter: false`，gen-l10n 产物本身非空）。
  AppLocalizations get l10n => AppLocalizations.of(this);
}
