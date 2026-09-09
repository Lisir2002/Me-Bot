import 'package:flutter_test/flutter_test.dart';

import 'package:minime_core/core/models/service_credentials.dart';
import 'package:minime_core/core/services/secure_storage/credential_record.dart';

void main() {
  final sample = <String, dynamic>{
    'id': 's1',
    'type': 'tavily',
    'apiKey': 'sk-live',
    'password': 'pw',
  };

  test('抽取命中敏感字段名，空值忽略', () {
    final secrets = ServiceCredentials.extract(sample);
    expect(secrets, <String, String>{'apiKey': 'sk-live', 'password': 'pw'});
    expect(
      ServiceCredentials.extract(<String, dynamic>{'apiKey': ''}),
      isEmpty,
    );
  });

  test('剥离后不含敏感字段，其余保留', () {
    final stripped = ServiceCredentials.strip(sample);
    expect(stripped.containsKey('apiKey'), isFalse);
    expect(stripped.containsKey('password'), isFalse);
    expect(stripped['type'], 'tavily');
    expect(stripped['id'], 's1');
  });

  test('剥离 + 回填无损往返', () {
    final secrets = ServiceCredentials.extract(sample);
    final restored =
        ServiceCredentials.merge(ServiceCredentials.strip(sample), secrets);
    expect(restored['apiKey'], 'sk-live');
    expect(restored['password'], 'pw');
  });

  test('record 往返：apiKey 为主值，其余进 ext', () {
    final secrets = ServiceCredentials.extract(sample);
    final record = ServiceCredentials.toRecord('s1', secrets);
    expect(record.value, 'sk-live');
    expect(record.type, CredentialType.apiKey);
    expect(ServiceCredentials.fromRecord(record), secrets);
  });

  test('无 apiKey 时以 password 为主值', () {
    final record = ServiceCredentials.toRecord(
      'x',
      <String, String>{'password': 'pw', 'username': 'u'},
    );
    expect(record.value, 'pw');
    expect(record.type, CredentialType.password);
  });

  test('record 为 null 返回空集合', () {
    expect(ServiceCredentials.fromRecord(null), isEmpty);
  });
}
