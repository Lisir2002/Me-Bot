import 'package:flutter_test/flutter_test.dart';

import 'package:minime_core/core/services/backup/backup_encryptor.dart';

void main() {
  final settings = <String, dynamic>{
    'theme': 'dark',
    'provider_configs_v1': '{"OpenAI":{"apiKey":"sk-secret-123"}}',
    'nested': <String, dynamic>{'count': 3, 'on': true},
  };

  const pass = 'Sup3rSecret!';

  test('isEnvelope 对明文/旧格式/空返回 false', () {
    expect(BackupEncryptor.isEnvelope({'provider_configs_v1': 'x'}), isFalse);
    expect(BackupEncryptor.isEnvelope(null), isFalse);
    expect(BackupEncryptor.isEnvelope(<String, dynamic>{}), isFalse);
  });

  test('加密往返一致（含嵌套结构）', () async {
    final env = await BackupEncryptor.seal(settings, passphrase: pass);
    expect(BackupEncryptor.isEnvelope(env), isTrue);
    expect(env['format'], BackupEncryptor.format);
    expect(env['version'], BackupEncryptor.version);
    final crypto = env['crypto'] as Map<String, dynamic>;
    expect(crypto['alg'], BackupEncryptor.contentAlg);
    expect(crypto['kdf'], BackupEncryptor.kdf);
    expect(crypto['iterations'], BackupEncryptor.kdfIterations);

    final out = await BackupEncryptor.open(env, passphrase: pass);
    expect(out, equals(settings));
  });

  test('错误口令被拒绝（wrongPassphrase）', () async {
    final env = await BackupEncryptor.seal(settings, passphrase: pass);
    expect(
      () => BackupEncryptor.open(env, passphrase: 'WrongPass!!99'),
      throwsA(isA<BackupCryptoError>().having((e) => e.kind, 'kind', BackupCryptoErrorKind.wrongPassphrase)),
    );
  });

  test('缺口令抛 needPassphrase', () async {
    final env = await BackupEncryptor.seal(settings, passphrase: pass);
    expect(
      () => BackupEncryptor.open(env, passphrase: ''),
      throwsA(isA<BackupCryptoError>().having((e) => e.kind, 'kind', BackupCryptoErrorKind.needPassphrase)),
    );
  });

  test('盐与 IV 随机：同口令两次密文/盐均不同', () async {
    final a = await BackupEncryptor.seal(settings, passphrase: pass);
    final b = await BackupEncryptor.seal(settings, passphrase: pass);
    expect(a['crypto']['jwe'], isNot(equals(b['crypto']['jwe'])));
    expect(a['crypto']['salt'], isNot(equals(b['crypto']['salt'])));
  });

  test('未知版本明确报错（unsupported）', () async {
    final env = <String, dynamic>{
      'format': BackupEncryptor.format,
      'version': 1,
      'crypto': <String, dynamic>{'alg': BackupEncryptor.contentAlg, 'jwe': 'x'},
    };
    expect(
      () => BackupEncryptor.open(env, passphrase: pass),
      throwsA(isA<BackupCryptoError>().having((e) => e.kind, 'kind', BackupCryptoErrorKind.unsupported)),
    );
  });

  test('未知算法明确报错（unsupported）', () async {
    final env = <String, dynamic>{
      'format': BackupEncryptor.format,
      'version': BackupEncryptor.version,
      'crypto': <String, dynamic>{
        'alg': 'A128CBC-HS256',
        'kdf': BackupEncryptor.kdf,
        'iterations': BackupEncryptor.kdfIterations,
        'salt': 'AAAA',
        'jwe': 'x',
      },
    };
    expect(
      () => BackupEncryptor.open(env, passphrase: pass),
      throwsA(isA<BackupCryptoError>().having((e) => e.kind, 'kind', BackupCryptoErrorKind.unsupported)),
    );
  });

  test('口令过短（<8 位）被拒绝（unsupported）', () {
    expect(
      () => BackupEncryptor.seal(settings, passphrase: 'short'),
      throwsA(isA<BackupCryptoError>().having((e) => e.kind, 'kind', BackupCryptoErrorKind.unsupported)),
    );
  });

  test('刚好 8 位口令可正常加密', () async {
    final env = await BackupEncryptor.seal(settings, passphrase: '12345678');
    final out = await BackupEncryptor.open(env, passphrase: '12345678');
    expect(out, equals(settings));
  });
}
