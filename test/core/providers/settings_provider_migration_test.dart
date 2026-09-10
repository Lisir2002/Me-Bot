import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:minime_core/core/providers/settings_provider.dart';

/// P2-5：v1 → v2 配置 key 迁移逻辑回归测试。
///
/// 验证 SettingsProvider.migrateLegacyV1Keys：
/// - v1 有值、v2 无值 → 复制到 v2 并删除 v1；
/// - v2 已有有效副本 → 删除冗余 v1，v2 不动；
/// - 三个 key 独立迁移、互不影响。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('v1 有值 v2 无值 → 自动复制到 v2 并删除 v1', () async {
    const providerJson = '{"openai":{"id":"openai","name":"OpenAI"}}';
    const searchJson = '[{"id":"google"}]';
    const ttsJson = '[{"id":"edge"}]';
    SharedPreferences.setMockInitialValues({
      'provider_configs_v1': providerJson,
      'search_services_v1': searchJson,
      'tts_services_v1': ttsJson,
    });
    final prefs = await SharedPreferences.getInstance();

    await SettingsProvider.migrateLegacyV1Keys(prefs);

    expect(prefs.getString('provider_configs_v2'), providerJson);
    expect(prefs.getString('search_services_v2'), searchJson);
    expect(prefs.getString('tts_services_v2'), ttsJson);
    expect(prefs.containsKey('provider_configs_v1'), isFalse);
    expect(prefs.containsKey('search_services_v1'), isFalse);
    expect(prefs.containsKey('tts_services_v1'), isFalse);
  });

  test('v2 已有有效副本 → 删除冗余 v1，v2 内容不变', () async {
    SharedPreferences.setMockInitialValues({
      'provider_configs_v1': '{"old":{}}',
      'provider_configs_v2': '{"new":{"id":"openai"}}',
    });
    final prefs = await SharedPreferences.getInstance();

    await SettingsProvider.migrateLegacyV1Keys(prefs);

    expect(prefs.getString('provider_configs_v2'), '{"new":{"id":"openai"}}');
    expect(prefs.containsKey('provider_configs_v1'), isFalse);
  });

  test('v1 不存在 → 不产生任何 key，不报错', () async {
    SharedPreferences.setMockInitialValues({'unrelated': 'x'});
    final prefs = await SharedPreferences.getInstance();

    await SettingsProvider.migrateLegacyV1Keys(prefs);

    expect(prefs.containsKey('provider_configs_v2'), isFalse);
    expect(prefs.containsKey('search_services_v2'), isFalse);
    expect(prefs.containsKey('tts_services_v2'), isFalse);
  });

  test('三个 key 独立迁移，互不影响', () async {
    SharedPreferences.setMockInitialValues({
      // 只有 provider 的 v1 需要搬
      'provider_configs_v1': '{"openai":{}}',
      // search 的 v1 为空字符串 → 只清不搬
      'search_services_v1': '',
    });
    final prefs = await SharedPreferences.getInstance();

    await SettingsProvider.migrateLegacyV1Keys(prefs);

    expect(prefs.getString('provider_configs_v2'), '{"openai":{}}');
    expect(prefs.containsKey('provider_configs_v1'), isFalse);
    expect(prefs.containsKey('search_services_v1'), isFalse,
        reason: '空 v1 也应被清理');
    expect(prefs.containsKey('search_services_v2'), isFalse,
        reason: '空 v1 不应产生空 v2');
    // tts 完全没动过
    expect(prefs.containsKey('tts_services_v1'), isFalse);
    expect(prefs.containsKey('tts_services_v2'), isFalse);
  });
}
