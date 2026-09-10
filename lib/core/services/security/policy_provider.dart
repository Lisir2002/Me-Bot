import 'package:shared_preferences/shared_preferences.dart';

/// 白名单策略层契约（预留接口⑤）。
///
/// 服务于「企业级密钥管理」方向的未来接入：远程下发白名单（KMS/SSO）、
/// 按动作/时段门禁策略。当前首个实现 [LocalPolicyProvider] 用本地 SharedPreferences 存，
/// 未来只需再实现一个 `RemotePolicyProvider` 注册进来即可，门禁/白名单调用点零改动。
///
/// 设计：策略状态在应用启动时 [load] 一次进内存，[check] 类方法**同步读取**，
/// 因为门禁/导航回调要求同步返回（NavigationDelegate 不能 await）。写操作回写 SharedPreferences。
abstract class PolicyProvider {
  /// 是否启用白名单拦截（关闭则 MCP / WebView 走宽松默认）。
  bool get enabled;

  /// MCP stdio 允许执行的基础命令（如 node / npx / python）。
  Set<String> get allowedMcpCommands;

  /// 默认允许的基础命令（白名单为空时回退到这份保守清单）。
  Set<String> get defaultMcpCommands;

  /// 某 MCP 服务器是否允许使用 stdio 传输（按 id 开关，默认 true）。
  bool isMcpServerAllowed(String serverId);

  /// WebView 额外放行的主机（例外站点；用于放行特定 http 源等）。
  Set<String> get allowedWebViewHosts;

  /// 是否允许 WebView 加载 http（默认 false，仅 https）。
  bool get allowWebViewHttp;

  // ── 写操作（回写持久化）──
  Future<void> setEnabled(bool value);
  Future<void> setAllowedMcpCommands(Set<String> commands);
  Future<void> setMcpServerEnabled(String serverId, bool allowed);
  Future<void> setWebViewHosts(Set<String> hosts);
  Future<void> setAllowWebViewHttp(bool value);
}

/// 本地白名单策略（预留接口⑤ 首个实现）。
///
/// 数据落在 `policy_*` 前缀的 SharedPreferences 键下，启动期 [load] 进内存。
class LocalPolicyProvider implements PolicyProvider {
  LocalPolicyProvider._(this._prefs);

  static LocalPolicyProvider? _instance;
  static bool _loaded = false;

  final SharedPreferences _prefs;

  /// 单例（已 load）。未 load 时不要直接读字段，先 await [load]。
  static LocalPolicyProvider? get instance => _loaded ? _instance : null;

  static const String _kEnabled = 'policy_enabled';
  static const String _kMcpCommands = 'policy_mcp_commands';
  static const String _kMcpServers = 'policy_mcp_servers';
  static const String _kWebViewHosts = 'policy_webview_hosts';
  static const String _kWebViewHttp = 'policy_webview_http';

  bool _enabled = false;
  Set<String> _allowedMcpCommands = _defaultMcpCommands;
  final Map<String, bool> _mcpServerEnabled = <String, bool>{};
  Set<String> _allowedWebViewHosts = const {};
  bool _allowWebViewHttp = false;

  static const Set<String> _defaultMcpCommands = {
    'node',
    'npx',
    'python',
    'python3',
    'uvx',
    'docker',
    'bun',
  };

  /// MCP 命令名校验：字母数字开头，后续允许字母数字、点、下划线、连字符。
  static final RegExp cmdPattern = RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]*$');

  /// WebView 主机名校验：字母数字开头和结尾，中间允许字母数字、点、连字符。
  static final RegExp hostPattern =
      RegExp(r'^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$');

  /// 校验命令名是否合法。
  static bool isValidCommand(String cmd) => cmdPattern.hasMatch(cmd);

  /// 校验主机名是否合法。
  static bool isValidHost(String host) => hostPattern.hasMatch(host);

  /// 从 SharedPreferences 装配单例（幂等，已 load 直接返回内存态）。
  static Future<LocalPolicyProvider> load() async {
    if (_loaded && _instance != null) return _instance!;
    final prefs = await SharedPreferences.getInstance();
    _instance = LocalPolicyProvider._(prefs);
    _instance!._read();
    _loaded = true;
    return _instance!;
  }

  void _read() {
    _enabled = _prefs.getBool(_kEnabled) ?? false;
    final cmds = _prefs.getStringList(_kMcpCommands);
    _allowedMcpCommands =
        cmds != null && cmds.isNotEmpty ? Set.from(cmds) : _defaultMcpCommands;
    final servers = _prefs.getStringList(_kMcpServers);
    if (servers != null) {
      for (final s in servers) {
        final kv = s.split(':');
        if (kv.length == 2) _mcpServerEnabled[kv[0]] = kv[1] == '1';
      }
    }
    _allowedWebViewHosts = Set.from(_prefs.getStringList(_kWebViewHosts) ?? const []);
    _allowWebViewHttp = _prefs.getBool(_kWebViewHttp) ?? false;
  }

  @override
  bool get enabled => _enabled;

  @override
  Set<String> get allowedMcpCommands => _allowedMcpCommands;

  @override
  Set<String> get defaultMcpCommands => _defaultMcpCommands;

  @override
  bool isMcpServerAllowed(String serverId) => _mcpServerEnabled[serverId] ?? true;

  @override
  Set<String> get allowedWebViewHosts => _allowedWebViewHosts;

  @override
  bool get allowWebViewHttp => _allowWebViewHttp;

  @override
  Future<void> setEnabled(bool value) async {
    _enabled = value;
    await _prefs.setBool(_kEnabled, value);
  }

  @override
  Future<void> setAllowedMcpCommands(Set<String> commands) async {
    // 服务端校验：过滤掉不合法的命令名，防止注入危险命令。
    _allowedMcpCommands = commands.where(isValidCommand).toSet();
    await _prefs.setStringList(_kMcpCommands, _allowedMcpCommands.toList());
  }

  @override
  Future<void> setMcpServerEnabled(String serverId, bool allowed) async {
    _mcpServerEnabled[serverId] = allowed;
    final list = _mcpServerEnabled.entries.map((e) => '${e.key}:${e.value ? 1 : 0}').toList();
    await _prefs.setStringList(_kMcpServers, list);
  }

  @override
  Future<void> setWebViewHosts(Set<String> hosts) async {
    // 服务端校验：过滤掉不合法的主机名，统一小写。
    _allowedWebViewHosts =
        hosts.map((h) => h.trim().toLowerCase()).where(isValidHost).toSet();
    await _prefs.setStringList(_kWebViewHosts, _allowedWebViewHosts.toList());
  }

  @override
  Future<void> setAllowWebViewHttp(bool value) async {
    _allowWebViewHttp = value;
    await _prefs.setBool(_kWebViewHttp, value);
  }
}
