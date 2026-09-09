import 'package:flutter_test/flutter_test.dart';

import 'package:minime_core/core/models/provider_credentials.dart';
import 'package:minime_core/core/services/secure_storage/credential_record.dart';

void main() {
  const secret = 'sk-super-secret-value';

  Map<String, dynamic> sampleConfig() => <String, dynamic>{
        'id': 'OpenAI',
        'enabled': true,
        'name': 'OpenAI',
        'apiKey': secret,
        'baseUrl': 'https://api.openai.com/v1',
        'serviceAccountJson': '{"type":"service_account"}',
        'proxyEnabled': true,
        'proxyHost': '127.0.0.1',
        'proxyPort': '7890',
        'proxyUsername': 'alice',
        'proxyPassword': 'p@ss',
        'multiKeyEnabled': true,
        'apiKeys': <dynamic>[
          <String, dynamic>{
            'id': 'key_1',
            'key': 'sk-multi-1',
            'isEnabled': true,
            'priority': 3,
          },
          <String, dynamic>{
            'id': 'key_2',
            'key': 'sk-multi-2',
            'isEnabled': false,
            'priority': 7,
          },
        ],
      };

  group('ProviderCredentials 抽取', () {
    test('从配置 JSON 中抽出全部敏感字段', () {
      final creds = ProviderCredentials.fromConfigJson(sampleConfig());
      expect(creds.apiKey, secret);
      expect(creds.serviceAccountJson, '{"type":"service_account"}');
      expect(creds.proxyUsername, 'alice');
      expect(creds.proxyPassword, 'p@ss');
      expect(creds.apiKeys, <String, String>{
        'key_1': 'sk-multi-1',
        'key_2': 'sk-multi-2',
      });
      expect(creds.isEmpty, isFalse);
    });

    test('空配置抽取出 empty', () {
      expect(
        ProviderCredentials.fromConfigJson(<String, dynamic>{'id': 'x'})
            .isEmpty,
        isTrue,
      );
    });

    test('apiKeys 里 key 为空的条目被忽略', () {
      final json = sampleConfig();
      json['apiKeys'] = <dynamic>[
        <String, dynamic>{'id': 'key_1', 'key': ''},
        <String, dynamic>{'id': 'key_2', 'key': 'sk-real'},
      ];
      expect(
        ProviderCredentials.fromConfigJson(json).apiKeys,
        <String, String>{'key_2': 'sk-real'},
      );
    });
  });

  group('ProviderCredentials 剥离', () {
    test('剥离后的 JSON 不含任何明文字段', () {
      final stripped = ProviderCredentials.stripCredentials(sampleConfig());
      final encoded = stripped.toString();

      for (final sensitive in <String>[
        secret,
        'sk-multi-1',
        'sk-multi-2',
        'p@ss',
        'alice',
        'service_account',
      ]) {
        expect(encoded.contains(sensitive), isFalse,
            reason: '$sensitive 不应出现在剥离后的 JSON 中');
      }
    });

    test('剥离保留非敏感字段与 apiKeys 元数据', () {
      final stripped = ProviderCredentials.stripCredentials(sampleConfig());
      expect(stripped['baseUrl'], 'https://api.openai.com/v1');
      expect(stripped['proxyHost'], '127.0.0.1');
      expect(stripped['proxyPort'], '7890');
      expect(stripped.containsKey('proxyUsername'), isFalse);
      expect(stripped.containsKey('proxyPassword'), isFalse);

      final keys = stripped['apiKeys'] as List;
      expect(keys.length, 2);
      // 元数据保留，只有 key 被去掉
      expect((keys[0] as Map)['id'], 'key_1');
      expect((keys[0] as Map)['priority'], 3);
      expect((keys[0] as Map).containsKey('key'), isFalse);
    });
  });

  group('ProviderCredentials 回填', () {
    test('回填后与原始 JSON 等价（可无损往返）', () {
      final original = sampleConfig();
      final creds = ProviderCredentials.fromConfigJson(original);
      final restored = creds.mergeInto(
        ProviderCredentials.stripCredentials(original),
      );

      expect(restored['apiKey'], original['apiKey']);
      expect(restored['serviceAccountJson'], original['serviceAccountJson']);
      expect(restored['proxyUsername'], original['proxyUsername']);
      expect(restored['proxyPassword'], original['proxyPassword']);
      final keys = restored['apiKeys'] as List;
      expect((keys[0] as Map)['key'], 'sk-multi-1');
      expect((keys[1] as Map)['key'], 'sk-multi-2');
    });

    test('凭证缺失的 key 回填为空串而非 null', () {
      final stripped = ProviderCredentials.stripCredentials(sampleConfig());
      final partial = ProviderCredentials(
        apiKey: secret,
        apiKeys: <String, String>{'key_1': 'sk-multi-1'},
      ).mergeInto(stripped);
      final keys = partial['apiKeys'] as List;
      expect((keys[1] as Map)['key'], '');
    });
  });

  group('CredentialRecord 往返', () {
    test('toRecord/fromRecord 无损', () {
      final creds = ProviderCredentials.fromConfigJson(sampleConfig());
      final record = creds.toRecord('OpenAI');
      final back = ProviderCredentials.fromRecord(record);

      expect(back.apiKey, creds.apiKey);
      expect(back.serviceAccountJson, creds.serviceAccountJson);
      expect(back.proxyUsername, creds.proxyUsername);
      expect(back.proxyPassword, creds.proxyPassword);
      expect(back.apiKeys, creds.apiKeys);
    });

    test('record 携带 providerId 与类型', () {
      final record = ProviderCredentials(apiKey: secret).toRecord('Gemini');
      expect(record.id, 'Gemini');
      expect(record.type, CredentialType.apiKey);
    });

    test('空凭证不写冗余 ext 字段', () {
      final record = ProviderCredentials(apiKey: secret).toRecord('X');
      expect(record.ext, isEmpty);
    });

    test('record 为 null 时返回 empty', () {
      expect(ProviderCredentials.fromRecord(null).isEmpty, isTrue);
    });

    test('toString 不泄露凭证内容', () {
      final text = ProviderCredentials(apiKey: secret).toString();
      expect(text.contains(secret), isFalse);
    });
  });
}
