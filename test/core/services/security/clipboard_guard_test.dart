import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:minime_core/core/services/security/clipboard_guard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 用内存态模拟系统剪贴板，便于断言清除行为。
  late String? clip;
  setUp(() {
    clip = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          final data = call.arguments as Map?;
          clip = data?['text'] as String?;
          return null;
        case 'Clipboard.getData':
          return <String, Object?>{'text': clip};
        default:
          return null;
      }
    });
  });

  tearDown(() {
    ClipboardGuard.instance.cancel();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('guard 写入剪贴板', () async {
    await ClipboardGuard.instance.guard('sk-secret-key');
    expect(clip, 'sk-secret-key');
    expect(ClipboardGuard.instance.isActive, isTrue);
  });

  test('到期时剪贴板仍是目标内容 → 自动清除', () async {
    await ClipboardGuard.instance.guard('sk-secret-key');
    await ClipboardGuard.instance.expireNowForTest();
    expect(clip, '');
  });

  test('中途用户复制了别的内容 → 不误清', () async {
    await ClipboardGuard.instance.guard('sk-secret-key');
    // 用户复制了别的东西（模拟系统剪贴板变化）
    clip = '用户正常复制的一段文本';
    await ClipboardGuard.instance.expireNowForTest();
    expect(clip, '用户正常复制的一段文本');
  });

  test('cancel 提前取消守卫', () async {
    await ClipboardGuard.instance.guard('sk-secret-key');
    ClipboardGuard.instance.cancel();
    expect(ClipboardGuard.instance.isActive, isFalse);
  });
}
