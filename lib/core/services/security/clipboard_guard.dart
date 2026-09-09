import 'dart:async';

import 'package:flutter/services.dart';

/// 剪贴板守卫（PR-5）。
///
/// 把敏感内容（如 API Key）写入剪贴板后，约定一段时间后自动清除——
/// **但清除前会校验「剪贴板里还是不是当初那份内容」**：如果用户中途复制了别的东西，
/// 守卫就**不**去误删，避免清掉用户新复制的文本。
///
/// 设计：
/// - 单例，全局只有一把「待清除」锁，避免多个守卫互相打架；
/// - [guard] 返回 [ClipboardGuardTicket]，调用方可在离开页面时 [cancel] 提前取消；
/// - 默认 60s，可配置（测试可传很短的 duration）。
class ClipboardGuard {
  ClipboardGuard._();

  static ClipboardGuard? _instance;
  static ClipboardGuard get instance => _instance ??= ClipboardGuard._();

  /// 默认自动清除延时。
  static const Duration defaultTtl = Duration(seconds: 60);

  Timer? _timer;
  String? _watched;

  /// 把 [value] 写入剪贴板，并安排在 [ttl] 后（若剪贴板仍是它）自动清除。
  ///
  /// 返回票据，调用方可在不再需要守卫时 [ClipboardGuardTicket.cancel]。
  /// 若已有一个守卫在跑，新的 [guard] 会接管（旧的被替换）。
  Future<ClipboardGuardTicket> guard(
    String value, {
    Duration ttl = defaultTtl,
  }) async {
    await Clipboard.setData(ClipboardData(text: value));
    _watched = value;
    _timer?.cancel();
    _timer = Timer(ttl, () => _expire());
    return ClipboardGuardTicket._(this);
  }

  /// 到期：仅当剪贴板仍是被守卫的内容才清除。
  Future<void> _expire() async {
    _timer = null;
    final watched = _watched;
    _watched = null;
    if (watched == null) return;
    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      final text = current?.text;
      if (text != null && text == watched) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (_) {
      // 读不到剪贴板（权限/无头环境）→ 不强制清，避免异常上抛
    }
  }

  /// 主动取消守卫（离开页面 / 用户手动复制别的内容时）。
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _watched = null;
  }

  /// 测试用：是否仍有守卫在跑。
  bool get isActive => _timer?.isActive ?? false;

  /// 测试用：直接触发到期逻辑。
  Future<void> expireNowForTest() async {
    _timer?.cancel();
    await _expire();
  }
}

/// 剪贴板守卫票据。离开页面时调用 [cancel] 可提前取消自动清除。
class ClipboardGuardTicket {
  ClipboardGuardTicket._(this._guard);
  final ClipboardGuard _guard;

  /// 取消守卫（不再自动清除剪贴板）。
  void cancel() => _guard.cancel();
}
