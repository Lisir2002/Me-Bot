import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:minime_core/core/services/security/policy_provider.dart';
import 'package:minime_core/core/services/security/url_policy.dart';
import 'package:minime_core/core/services/security/mcp_command_policy.dart';

/// 纯内存策略桩，用于守卫单元测试（不依赖 SharedPreferences）。
class _FakePolicy implements PolicyProvider {
  _FakePolicy({
    this.enabled = true,
    this.allowWebViewHttp = false,
    this.allowedWebViewHosts = const {},
    this.mcpServers = const {},
  });
  @override
  final bool enabled;
  @override
  final Set<String> allowedMcpCommands = const {
    'node',
    'npx',
    'python',
    'python3',
    'uvx',
    'docker',
    'bun',
  };
  @override
  final Set<String> defaultMcpCommands = const {'node', 'npx', 'python', 'python3', 'uvx', 'docker', 'bun'};
  @override
  final bool allowWebViewHttp;
  @override
  final Set<String> allowedWebViewHosts;
  final Map<String, bool> mcpServers;

  @override
  bool isMcpServerAllowed(String serverId) => mcpServers[serverId] ?? true;
  @override
  Future<void> setEnabled(bool value) async {}
  @override
  Future<void> setAllowedMcpCommands(Set<String> commands) async {}
  @override
  Future<void> setMcpServerEnabled(String serverId, bool allowed) async {}
  @override
  Future<void> setWebViewHosts(Set<String> hosts) async {}
  @override
  Future<void> setAllowWebViewHttp(bool value) async {}
}

void main() {
  group('UrlGuard（验收矩阵）', () {
    final policy = _FakePolicy();
    final guard = UrlGuard(policy);

    test('https 放行', () {
      expect(guard.checkString('https://example.com/page').allowed, isTrue);
    });
    test('file / javascript / data 一律拦截', () {
      expect(guard.checkString('file:///etc/passwd').denied, isTrue);
      expect(guard.checkString('javascript:alert(1)').denied, isTrue);
      expect(guard.checkString('data:text/html,<script>').denied, isTrue);
      expect(guard.check(Uri.parse('content://media/external')).denied, isTrue);
    });
    test('http 默认拦截', () {
      expect(guard.checkString('http://example.com').denied, isTrue);
      expect(guard.checkString('http://example.com').reason, contains('https'));
    });
    test('http 在 allowWebViewHttp 时放行', () {
      final p = _FakePolicy(allowWebViewHttp: true);
      expect(UrlGuard(p).checkString('http://example.com').allowed, isTrue);
    });
    test('http 命中例外主机放行', () {
      final p = _FakePolicy(allowedWebViewHosts: {'intranet.local'});
      expect(UrlGuard(p).checkString('http://intranet.local/api').allowed, isTrue);
      expect(UrlGuard(p).checkString('http://other.com').denied, isTrue);
    });
    test('相对/无 scheme URL 不在此守卫拦截范围（放行）', () {
      // Dart 会把 'not a url' 解析为无 scheme 的相对 URL，非危险 scheme，放行。
      expect(guard.checkString('not a url').allowed, isTrue);
      expect(guard.check(Uri.parse('/relative/path')).allowed, isTrue);
    });
  });

  group('McpCommandGuard', () {
    test('白名单命令放行（含带路径/参数）', () {
      final guard = McpCommandGuard(_FakePolicy());
      expect(guard.check('/usr/bin/node', serverId: 's1').allowed, isTrue);
      expect(guard.check('npx -y some-server', serverId: 's1').allowed, isTrue);
      expect(guard.check('python3 script.py', serverId: 's1').allowed, isTrue);
    });
    test('非白名单命令拦截', () {
      final guard = McpCommandGuard(_FakePolicy());
      final r = guard.check('curl http://evil', serverId: 's1');
      expect(r.denied, isTrue);
      expect(r.reason, contains('curl'));
    });
    test('空命令拦截', () {
      final guard = McpCommandGuard(_FakePolicy());
      expect(guard.check('', serverId: 's1').denied, isTrue);
      expect(guard.check(null, serverId: 's1').denied, isTrue);
    });
    test('单服务器被停用 stdio → 拦截', () {
      final guard = McpCommandGuard(_FakePolicy(mcpServers: {'bad': false}));
      expect(guard.check('node', serverId: 'bad').denied, isTrue);
      expect(guard.check('node', serverId: 'good').allowed, isTrue);
    });
    test('策略未启用 → 全部放行（宽松默认）', () {
      final guard = McpCommandGuard(_FakePolicy(enabled: false));
      expect(guard.check('curl http://evil', serverId: 's1').allowed, isTrue);
    });
    test('baseName 解析', () {
      expect(McpCommandGuard.baseName('/usr/local/bin/node'), 'node');
      expect(McpCommandGuard.baseName('npx -y x'), 'npx');
      expect(McpCommandGuard.baseName('node'), 'node');
    });
  });

  group('LocalPolicyProvider 持久化', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('默认值与持久化往返', () async {
      final p = await LocalPolicyProvider.load();
      expect(p.enabled, isFalse); // 默认关
      expect(p.defaultMcpCommands.contains('node'), isTrue);
      expect(p.isMcpServerAllowed('x'), isTrue); // 默认允许

      await p.setEnabled(true);
      await p.setAllowedMcpCommands({'node', 'python3'});
      await p.setMcpServerEnabled('s2', false);
      await p.setAllowWebViewHttp(true);
      await p.setWebViewHosts({'intranet.local'});

      // 重新 load 应读回
      final p2 = await LocalPolicyProvider.load();
      expect(p2.enabled, isTrue);
      expect(p2.allowedMcpCommands, {'node', 'python3'});
      expect(p2.isMcpServerAllowed('s2'), isFalse);
      expect(p2.allowWebViewHttp, isTrue);
      expect(p2.allowedWebViewHosts, {'intranet.local'});
    });
  });
}
