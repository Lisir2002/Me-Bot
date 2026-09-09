import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_lock_gate.dart';
import 'local_identity_verifier.dart';

/// 隐私门禁服务（PR-6，预留接口⑤ 首个实现）。
///
/// - 设置项默认**关**；开启前校验设备是否支持生物识别/PIN（不支持则不允许开启）；
/// - 开启后，敏感动作（查看/复制 Key、加密导出、输入口令）会先弹系统认证；
/// - 设备不支持时功能应已被 UI 隐藏，极端情况下 [ensureUnlocked] 兜底放行，不阻塞主流程。
///
/// 生物识别 → 系统 PIN 的回退由 [LocalIdentityVerifier]（local_auth）保证。
class AppLockService extends ChangeNotifier implements AppLockGate {
  AppLockService({IdentityVerifier? verifier}) : _verifier = verifier ?? LocalIdentityVerifier();

  static AppLockService? _instance;
  static bool _loaded = false;

  final IdentityVerifier _verifier;

  bool _enabled = false;

  static const String _kEnabled = 'lock_enabled';

  /// 单例（已 load）。未 load 前 [enabled] 为 false（最保守）。
  static AppLockService? get instance => _loaded ? _instance : null;

  /// 从 SharedPreferences 装配单例（幂等）。
  static Future<AppLockService> load() async {
    if (_loaded && _instance != null) return _instance!;
    _instance = AppLockService();
    final prefs = await SharedPreferences.getInstance();
    _instance!._enabled = prefs.getBool(_kEnabled) ?? false; // 默认关
    _loaded = true;
    return _instance!;
  }

  @override
  bool get enabled => _enabled;

  @override
  Future<bool> canEnable() async => await _verifier.isDeviceSupported();

  /// 开启/关闭门禁；开启时若设备不支持则忽略（保持关）。
  Future<bool> setEnabled(bool value) async {
    if (value) {
      if (!await canEnable()) return false;
    }
    _enabled = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, value);
    } catch (_) {
      // 持久化失败不致命，内存态已更新
    }
    notifyListeners();
    return true;
  }

  /// 若开启门禁则先校验身份，否则直接放行。
  /// [reason] 为展示给用户的本地化说明（如「验证身份以查看密钥」）。
  /// 返回 true 表示允许继续；false 表示取消 / 校验失败。
  @override
  Future<bool> ensureUnlocked(LockAction action,
      {BuildContext? context, String? reason}) async {
    if (!_enabled) return true;
    if (!await _verifier.isDeviceSupported()) return true; // 兜底放行
    return _verifier.authenticate(reason ?? '需要验证身份以继续');
  }

  /// 仅供测试：重置单例，便于验证持久化往返。
  static void resetForTest() {
    _instance = null;
    _loaded = false;
  }
}
