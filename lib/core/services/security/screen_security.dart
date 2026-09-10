import 'dart:io';

import 'package:flutter/services.dart';

/// 屏幕安全（PR-6）。
///
/// Android：凭证页设置 `FLAG_SECURE`，阻止截屏 / 录屏 / 近期任务缩略图泄露 Key。
/// 通过自建 MethodChannel 实现，不引入额外依赖。
///
/// iOS 的「进后台模糊遮罩」由 UI 层在 `AppLifecycleState.inactive` 时叠加遮罩完成
/// （见各凭证页），本类只负责 Android 这一侧的硬开关。
class ScreenSecurity {
  ScreenSecurity._();

  static const MethodChannel _channel =
      MethodChannel('minime_core/screen_security');

  /// 开启/关闭防截屏。非 Android 平台为 no-op。
  static Future<void> setSecure(bool secure) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<bool>('setSecure', secure);
    } catch (_) {
      // 原生未注册 handler 或调用失败 → 静默，不阻塞 UI
    }
  }
}
