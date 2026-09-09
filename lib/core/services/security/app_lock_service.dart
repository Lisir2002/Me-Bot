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
///
/// ## 严谨性设计（v0.0.48 强化）
/// - **开关双向验证**：开启与关闭都要现场验证身份。开启时验证确认「是本人在开」，
///   关闭时验证防止借机的人随手把门禁关掉（否则门禁形同虚设）；
/// - **解锁宽限期**：一次认证通过后 [graceMinutes] 分钟内免重复认证——否则每次
///   复制一个 Key 都要按指纹，用户会直接把门禁关掉（安全的最大敌人是烦）。
///   宽限期 0 表示每次都要验证；验证失败的**不刷新**宽限期。
class AppLockService extends ChangeNotifier implements AppLockGate {
  AppLockService({IdentityVerifier? verifier}) : _verifier = verifier ?? LocalIdentityVerifier();

  static AppLockService? _instance;
  static bool _loaded = false;

  final IdentityVerifier _verifier;

  bool _enabled = false;
  int _graceMinutes = 5;
  DateTime? _lastUnlockAt;

  static const String _kEnabled = 'lock_enabled';
  static const String _kGraceMinutes = 'lock_grace_minutes';

  /// 可选的宽限期档位（分钟）。
  static const List<int> graceChoices = <int>[0, 1, 5, 15];

  /// 默认宽限期：5 分钟内免重复验证。
  static const int defaultGraceMinutes = 5;

  /// 单例（已 load）。未 load 前 [enabled] 为 false（最保守）。
  static AppLockService? get instance => _loaded ? _instance : null;

  /// 从 SharedPreferences 装配单例（幂等）。[verifier] 仅供测试注入。
  static Future<AppLockService> load({IdentityVerifier? verifier}) async {
    if (_loaded && _instance != null) return _instance!;
    _instance = AppLockService(verifier: verifier);
    final prefs = await SharedPreferences.getInstance();
    _instance!._enabled = prefs.getBool(_kEnabled) ?? false; // 默认关
    _instance!._graceMinutes =
        prefs.getInt(_kGraceMinutes) ?? defaultGraceMinutes;
    _loaded = true;
    return _instance!;
  }

  @override
  bool get enabled => _enabled;

  /// 当前宽限期（分钟）。0 = 每次敏感操作都要求验证。
  int get graceMinutes => _graceMinutes;

  /// 是否处于解锁宽限期内（仅当门禁开启时有意义）。
  bool get withinGrace {
    if (!_enabled || _graceMinutes <= 0) return false;
    final last = _lastUnlockAt;
    if (last == null) return false;
    return DateTime.now().difference(last) <= Duration(minutes: _graceMinutes);
  }

  @override
  Future<bool> canEnable() async => await _verifier.isDeviceSupported();

  /// 以指定文案现场验证一次身份（供 UI 在开关门禁等管理动作前调用）。
  /// 仅验证，不改变任何状态，也不进入宽限期。
  Future<bool> verifyWith(String reason) => _verifier.authenticate(reason);

  /// 开启/关闭门禁。**两个方向都要求现场验证身份**：
  /// - 开启：确认是本人在开（而不是借手机的人乱点）；
  /// - 关闭：防止他人直接把门禁关掉，让保护形同虚设。
  ///
  /// 设备不支持时开启直接拒绝（返回 false）；关闭不需要设备支持也要验证吗？
  /// —— 关闭同样走验证；设备不支持时门禁本来就无法开启，这里只是兜底。
  ///
  /// [verify] 供测试注入；默认现场调 [_verifier.authenticate]。
  Future<bool> setEnabled(bool value, {Future<bool> Function()? verify}) async {
    if (value && !await canEnable()) return false;
    // 现场验证身份（成功与否都不留宽限期——开/关是管理动作，不是解锁）。
    // 认证器异常（插件缺失等）按验证失败处理，不向上抛。
    bool authed = false;
    try {
      authed = await (verify ?? () => _verifier.authenticate(
          value ? '验证身份以开启隐私门禁' : '验证身份以关闭隐私门禁'))();
    } catch (_) {
      authed = false;
    }
    if (!authed) return false;
    _enabled = value;
    if (!value) _lastUnlockAt = null; // 关闭即清空解锁态
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kEnabled, value);
    } catch (_) {
      // 持久化失败不致命，内存态已更新
    }
    notifyListeners();
    return true;
  }

  /// 设置宽限期（分钟），持久化。
  Future<void> setGraceMinutes(int minutes) async {
    _graceMinutes = minutes.clamp(0, 60);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kGraceMinutes, _graceMinutes);
    } catch (_) {}
    notifyListeners();
  }

  /// 若开启门禁则先校验身份，否则直接放行。
  /// [reason] 为展示给用户的本地化说明（如「验证身份以查看密钥」）。
  /// 返回 true 表示允许继续；false 表示取消 / 校验失败。
  ///
  /// 宽限期内（最近一次认证成功后 [graceMinutes] 分钟内）直接放行。
  @override
  Future<bool> ensureUnlocked(LockAction action,
      {BuildContext? context, String? reason}) async {
    if (!_enabled) return true;
    if (withinGrace) return true; // 宽限期内免重复认证
    if (!await _verifier.isDeviceSupported()) return true; // 兜底放行
    final ok = await _verifier.authenticate(reason ?? '需要验证身份以继续');
    if (ok) _lastUnlockAt = DateTime.now(); // 只有成功才进入宽限期
    return ok;
  }

  /// 立即清空解锁态（下次敏感操作强制重新验证）。
  Future<void> lockNow() async {
    _lastUnlockAt = null;
    notifyListeners();
  }

  /// 仅供测试：重置单例，便于验证持久化往返。
  static void resetForTest() {
    _instance = null;
    _loaded = false;
  }
}
