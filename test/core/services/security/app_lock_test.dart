import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:minime_core/core/services/security/app_lock_gate.dart';
import 'package:minime_core/core/services/security/app_lock_service.dart';

class _FakeVerifier implements IdentityVerifier {
  _FakeVerifier({this.supported = true, this.authResult = true});
  final bool supported;
  final bool authResult;
  int authCalls = 0;

  @override
  Future<bool> isDeviceSupported() async => supported;
  @override
  Future<bool> authenticate(String localizedReason) async {
    authCalls++;
    return authResult;
  }

  @override
  String get methodName => 'fake';
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AppLockService.resetForTest();
  });

  test('默认关闭 → 无需认证直接放行', () async {
    final v = _FakeVerifier();
    final svc = AppLockService(verifier: v);
    expect(await svc.ensureUnlocked(LockAction.viewCredential), isTrue);
    expect(v.authCalls, 0);
  });

  test('开启 + 支持 + 认证通过 → 放行', () async {
    final v = _FakeVerifier();
    final svc = AppLockService(verifier: v);
    expect(await svc.setEnabled(true), isTrue);
    expect(await svc.ensureUnlocked(LockAction.copyCredential), isTrue);
    expect(v.authCalls, 1);
  });

  test('开启 + 认证失败 → 拒绝', () async {
    final v = _FakeVerifier(authResult: false);
    final svc = AppLockService(verifier: v);
    await svc.setEnabled(true);
    expect(await svc.ensureUnlocked(LockAction.exportWithKey), isFalse);
  });

  test('开启但设备不支持 → 兜底放行（不阻塞主流程）', () async {
    final v = _FakeVerifier(supported: false);
    final svc = AppLockService(verifier: v);
    // 设备不支持时不允许开启
    expect(await svc.setEnabled(true), isFalse);
    expect(svc.enabled, isFalse);
    // 极端情况（已 enabled 但设备不支持）兜底放行
    expect(await svc.ensureUnlocked(LockAction.viewCredential), isTrue);
    expect(v.authCalls, 0);
  });

  test('持久化往返：开启后重新 load 仍为开启', () async {
    final v = _FakeVerifier();
    final svc = AppLockService(verifier: v);
    await svc.setEnabled(true);

    AppLockService.resetForTest();
    final reloaded = await AppLockService.load();
    expect(reloaded.enabled, isTrue);

    // 关闭后也持久化
    await reloaded.setEnabled(false);
    AppLockService.resetForTest();
    expect((await AppLockService.load()).enabled, isFalse);
  });

  test('canEnable 反映设备支持情况', () async {
    expect(await AppLockService(verifier: _FakeVerifier(supported: true)).canEnable(), isTrue);
    expect(await AppLockService(verifier: _FakeVerifier(supported: false)).canEnable(), isFalse);
  });
}
