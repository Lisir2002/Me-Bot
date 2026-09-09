import 'package:local_auth/local_auth.dart';

import 'app_lock_gate.dart';

/// local_auth 实现的身份校验器（预留接口⑤ 首个实现，PR-6）。
///
/// 生物识别优先；系统在无生物识别时会自动回退到设备 PIN/图案/密码
/// （`deviceAuthAllowed`）。local_auth 自身保证这一回退。
class LocalIdentityVerifier implements IdentityVerifier {
  LocalIdentityVerifier({LocalAuthentication? auth}) : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  @override
  Future<bool> isDeviceSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> authenticate(String localizedReason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          biometricOnly: false, // 允许回退系统 PIN/密码
          stickyAuth: true,
        ),
      );
      return ok;
    } catch (_) {
      // 认证被系统取消 / 异常 → 视为未通过，不阻塞主流程由调用方决定
      return false;
    }
  }

  @override
  String get methodName => '生物识别 / 设备 PIN';
}
