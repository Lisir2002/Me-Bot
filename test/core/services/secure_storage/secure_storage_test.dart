import 'package:flutter_test/flutter_test.dart';

import 'package:minime_core/core/services/secure_storage/credential_record.dart';
import 'package:minime_core/core/services/secure_storage/secure_storage_backend.dart';

import '../../helpers/fake_secure_backend.dart';

void main() {
  group('CredentialRecord（预留接口①）', () {
    test('编解码往返一致，元数据不丢失', () {
      final record = CredentialRecord.create(
        type: CredentialType.apiKey,
        value: 'sk-secret-value',
        id: 'provider_1',
        ext: <String, dynamic>{'tenant': 'acme'},
      );

      final decoded = CredentialRecord.decode(record.encode());

      expect(decoded, isNotNull);
      expect(decoded!.value, 'sk-secret-value');
      expect(decoded.type, CredentialType.apiKey);
      expect(decoded.id, 'provider_1');
      expect(decoded.ext['tenant'], 'acme');
      expect(decoded.createdAt, isNotNull);
    });

    test('未知 type 回落为 custom，保证向前兼容', () {
      const raw = '{"type":"oauthToken","value":"abc"}';
      final decoded = CredentialRecord.decode(raw);
      expect(decoded, isNotNull);
      expect(decoded!.type, CredentialType.custom);
      expect(decoded.value, 'abc');
    });

    test('损坏或空数据返回 null 而不抛异常', () {
      expect(CredentialRecord.decode('not-json'), isNull);
      expect(CredentialRecord.decode(''), isNull);
      expect(CredentialRecord.decode(null), isNull);
      expect(CredentialRecord.decode('{"value":123}'), isNull);
    });

    test('touch / markRotated 正确更新生命周期字段', () {
      final record = CredentialRecord.create(
        type: CredentialType.apiKey,
        value: 'v',
      );
      expect(record.lastUsedAt, isNull);
      expect(record.lastRotatedAt, isNull);

      final touched = record.touch();
      expect(touched.lastUsedAt, isNotNull);
      expect(touched.lastRotatedAt, isNull);

      final rotated = touched.markRotated();
      expect(rotated.lastRotatedAt, isNotNull);
      // 不可变：原对象不被修改
      expect(record.lastUsedAt, isNull);
    });
  });

  group('SecureStorageRegistry（预留接口②）', () {
    test('首个注册的后端自动成为默认', () {
      final registry = SecureStorageRegistry();
      registry.register(FakeBackend(id: 'a'));
      expect(registry.defaultBackend?.id, 'a');
    });

    test('asDefault 可切换默认后端，且旧后端仍可查得', () {
      final registry = SecureStorageRegistry();
      registry.register(FakeBackend(id: 'a'));
      registry.register(FakeBackend(id: 'b'), asDefault: true);

      expect(registry.defaultBackend?.id, 'b');
      expect(registry.get('a'), isNotNull);
      expect(registry.backendIds, containsAll(<String>['a', 'b']));
    });

    test('无后端时 defaultBackend 为 null、hasBackend 为 false', () {
      final registry = SecureStorageRegistry();
      expect(registry.defaultBackend, isNull);
      expect(registry.hasBackend, isFalse);
    });
  });

  group('SecureStorageService', () {
    test('读写删与 contains / readAll 正常', () async {
      final backend = FakeBackend();
      final service = buildService(backend);

      await service.write('k1', 'v1');
      expect(await service.read('k1'), 'v1');
      expect(await service.contains('k1'), isTrue);

      await service.write('k2', 'v2');
      final all = await service.readAll();
      expect(all, <String, String>{'k1': 'v1', 'k2': 'v2'});

      await service.delete('k1');
      expect(await service.read('k1'), isNull);
      expect(await service.contains('k1'), isFalse);
    });

    test('类型化凭证读写与 touchCredential', () async {
      final service = buildService(FakeBackend());
      final record = CredentialRecord.create(
        type: CredentialType.apiKey,
        value: 'sk-1',
      );

      await service.writeCredential('cred', record);
      final back = await service.readCredential('cred');
      expect(back?.value, 'sk-1');
      expect(back?.lastUsedAt, isNull);

      await service.touchCredential('cred');
      final touched = await service.readCredential('cred');
      expect(touched?.lastUsedAt, isNotNull);
      expect(touched?.value, 'sk-1');

      // 不存在的凭证 touch 不报错
      await service.touchCredential('missing');
    });

    test('未注册后端时抛 SecureStorageException（快速失败）', () async {
      final service = SecureStorageService(SecureStorageRegistry());
      expect(
        service.read('any'),
        throwsA(isA<SecureStorageException>()),
      );
    });

    test('读取失败 fail-soft 返回 null，并触发 onError', () async {
      final errors = <String>[];
      final service = buildService(
        FakeBackend(failOnRead: true),
        errorSink: errors,
      );

      expect(await service.read('k'), isNull);
      expect(errors, isNotEmpty);
    });

    test('写入失败抛出，且异常与日志均不含凭证值', () async {
      final errors = <String>[];
      const secret = 'sk-SUPER-SECRET-VALUE';
      final service = buildService(
        FakeBackend(failOnWrite: true),
        errorSink: errors,
      );

      expect(
        service.write('k', secret),
        throwsA(isA<SecureStorageException>()),
      );

      for (final message in errors) {
        expect(message.contains(secret), isFalse);
      }
      expect(errors.join(' '), contains('key=k'));
    });

    test('isDegraded 反映后端降级状态', () {
      expect(buildService(FakeBackend()).isDegraded, isFalse);
      expect(
        buildService(FakeBackend(degraded: true)).isDegraded,
        isTrue,
      );
    });
  });
}
