import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:minime_core/core/services/backup/credential_bridge.dart';
import 'package:minime_core/core/services/secure_storage/credential_keys.dart';
import 'package:minime_core/core/services/secure_storage/credential_record.dart';

import '../../helpers/fake_secure_backend.dart';

const _providerKey = 'sk-provider-secret';
const _searchKey = 'sk-search-secret';
const _ttsKey = 'sk-tts-secret';
const _davPass = 'dav-secret';
const _proxyPass = 'proxy-secret';

/// 一份「迁移前」的脏快照：凭证全在明文里。
Map<String, dynamic> dirtySnapshot() => <String, dynamic>{
      CredentialKeys.legacyProviderConfigs: jsonEncode(<String, dynamic>{
        'OpenAI': <String, dynamic>{
          'id': 'OpenAI',
          'apiKey': _providerKey,
          'baseUrl': 'https://api.openai.com/v1',
          'proxyPassword': 'p-pass',
        },
      }),
      CredentialKeys.legacySearchServices: jsonEncode(<dynamic>[
        <String, dynamic>{'id': 's1', 'type': 'tavily', 'apiKey': _searchKey},
      ]),
      CredentialKeys.legacyTtsServices: jsonEncode(<dynamic>[
        <String, dynamic>{'id': 't1', 'kind': 'openai', 'apiKey': _ttsKey},
      ]),
      CredentialKeys.legacyWebDavConfig: jsonEncode(<String, dynamic>{
        'url': 'https://dav.example.com',
        'password': _davPass,
      }),
      CredentialKeys.legacyGlobalProxyUsername: 'guser',
      CredentialKeys.legacyGlobalProxyPassword: _proxyPass,
      'theme_mode_v1': 'dark',
    };

void main() {
  group('导出：默认脱敏（拍板②）', () {
    test('备份内容不含任何凭证明文', () async {
      final backend = FakeBackend();
      final bridge = BackupCredentialBridge(buildService(backend));
      final out = await bridge.prepareForExport(dirtySnapshot());

      final encoded = jsonEncode(out);
      for (final secret in <String>[
        _providerKey,
        _searchKey,
        _ttsKey,
        _davPass,
        _proxyPass,
        'p-pass',
        'guser',
      ]) {
        expect(encoded.contains(secret), isFalse,
            reason: '$secret 不应出现在脱敏后的备份中');
      }
    });

    test('脱敏保留非敏感配置', () async {
      final backend = FakeBackend();
      final bridge = BackupCredentialBridge(buildService(backend));
      final out = await bridge.prepareForExport(dirtySnapshot());

      expect(out['theme_mode_v1'], 'dark');
      final provider = jsonDecode(
        out[CredentialKeys.legacyProviderConfigs] as String,
      ) as Map<String, dynamic>;
      expect(
        (provider['OpenAI'] as Map)['baseUrl'],
        'https://api.openai.com/v1',
      );
      final search =
          jsonDecode(out[CredentialKeys.legacySearchServices] as String) as List;
      expect((search[0] as Map)['type'], 'tavily');
      expect((search[0] as Map)['id'], 's1');
    });

    test('形态保持：原本是 JSON 字符串，脱敏后仍是字符串', () async {
      final backend = FakeBackend();
      final bridge = BackupCredentialBridge(buildService(backend));
      final out = await bridge.prepareForExport(dirtySnapshot());
      expect(out[CredentialKeys.legacyProviderConfigs], isA<String>());
      expect(out[CredentialKeys.legacySearchServices], isA<String>());
    });
  });

  group('导出：include 策略', () {
    test('把安全存储里的凭证注入备份内容', () async {
      final backend = FakeBackend();
      final svc = buildService(backend);
      final bridge = BackupCredentialBridge(svc);

      // 先按脱敏导出（模拟本机当前状态）
      final clean = await bridge.prepareForExport(dirtySnapshot());
      // 凭证实际在安全存储里
      await svc.writeCredential(
        CredentialKeys.provider('OpenAI'),
        CredentialRecord(type: CredentialType.apiKey, value: _providerKey),
      );

      final out = await bridge.prepareForExport(
        clean,
        policy: BackupCredentialPolicy.include,
      );
      final provider = jsonDecode(
        out[CredentialKeys.legacyProviderConfigs] as String,
      ) as Map<String, dynamic>;
      expect((provider['OpenAI'] as Map)['apiKey'], _providerKey);
    });
  });

  group('恢复：吸收凭证', () {
    test('老备份（含明文）的凭证被抽进安全存储', () async {
      final backend = FakeBackend();
      final svc = buildService(backend);
      final bridge = BackupCredentialBridge(svc);

      final restored = await bridge.absorbOnRestore(dirtySnapshot());
      final encoded = jsonEncode(restored);

      for (final secret in <String>[
        _providerKey,
        _searchKey,
        _ttsKey,
        _davPass,
        _proxyPass,
      ]) {
        expect(encoded.contains(secret), isFalse,
            reason: '$secret 不应写回 SharedPreferences');
      }

      // 凭证确实进了安全存储
      final p = await svc.readCredential(CredentialKeys.provider('OpenAI'));
      expect(p?.value, _providerKey);
      final s = await svc.readCredential(CredentialKeys.service('s1'));
      expect(s?.value, _searchKey);
      final t = await svc.readCredential(CredentialKeys.service('t1'));
      expect(t?.value, _ttsKey);
      expect(await svc.read(CredentialKeys.webDavPassword), _davPass);
      expect(await svc.read(CredentialKeys.globalProxyPassword), _proxyPass);
    });

    test('恢复后非敏感配置完整保留', () async {
      final backend = FakeBackend();
      final bridge = BackupCredentialBridge(buildService(backend));
      final restored = await bridge.absorbOnRestore(dirtySnapshot());

      expect(restored['theme_mode_v1'], 'dark');
      final provider = jsonDecode(
        restored[CredentialKeys.legacyProviderConfigs] as String,
      ) as Map<String, dynamic>;
      expect(
        (provider['OpenAI'] as Map)['baseUrl'],
        'https://api.openai.com/v1',
      );
      final search = jsonDecode(
        restored[CredentialKeys.legacySearchServices] as String,
      ) as List;
      expect((search[0] as Map)['type'], 'tavily');
    });

    test('新版脱敏备份恢复时无副作用', () async {
      final backend = FakeBackend();
      final bridge = BackupCredentialBridge(buildService(backend));
      final clean = await bridge.prepareForExport(dirtySnapshot());

      final restored = await bridge.absorbOnRestore(clean);
      expect(backend.store, isEmpty);
      expect(restored['theme_mode_v1'], 'dark');
    });

    test('损坏的 JSON 不抛异常', () async {
      final backend = FakeBackend();
      final bridge = BackupCredentialBridge(buildService(backend));
      await expectLater(
        bridge.absorbOnRestore(<String, dynamic>{
          CredentialKeys.legacyProviderConfigs: '{bad',
          CredentialKeys.legacySearchServices: '[]',
          CredentialKeys.legacyWebDavConfig: 'null',
        }),
        completes,
      );
    });
  });

  group('核查与孤儿清理', () {
    test('containsPlaintextCredentials 能识别脏内容', () async {
      final backend = FakeBackend();
      final bridge = BackupCredentialBridge(buildService(backend));

      expect(bridge.containsPlaintextCredentials(dirtySnapshot()), isTrue);
      final clean = await bridge.prepareForExport(dirtySnapshot());
      expect(bridge.containsPlaintextCredentials(clean), isFalse);
    });

    test('孤儿凭证被清理，在用的保留', () async {
      final backend = FakeBackend();
      final svc = buildService(backend);
      final bridge = BackupCredentialBridge(svc);

      await svc.writeCredential(
        CredentialKeys.provider('Alive'),
        CredentialRecord(type: CredentialType.apiKey, value: 'a'),
      );
      await svc.writeCredential(
        CredentialKeys.provider('Ghost'),
        CredentialRecord(type: CredentialType.apiKey, value: 'g'),
      );
      await svc.writeCredential(
        CredentialKeys.service('OldSvc'),
        CredentialRecord(type: CredentialType.apiKey, value: 'o'),
      );

      final removed = await bridge.purgeOrphans(
        providerIds: <String>{'Alive'},
        serviceIds: <String>{},
      );

      expect(removed, 2);
      expect(await svc.readCredential(CredentialKeys.provider('Alive')),
          isNotNull);
      expect(await svc.readCredential(CredentialKeys.provider('Ghost')), isNull);
      expect(await svc.readCredential(CredentialKeys.service('OldSvc')), isNull);
    });
  });
}

