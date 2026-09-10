import 'dart:convert';

import '../jsonrpc_engine_base.dart';

/// MiniMe-Code — 占位内置 MCP 服务器引擎。
///
/// 这是预设占位，后续会扩展代码相关工具（代码搜索/片段生成/解释等）。
/// 当前仅提供两个简单工具用于验证多内置服务器链路：
/// - `ping`：存活探测
/// - `version`：版本信息
class MiniMeCodeMcpServerEngine extends BaseJsonRpcMcpEngine {
  @override
  String get serverName => 'MiniMe-Code';

  @override
  String get serverVersion => '0.1.0';

  @override
  List<Map<String, dynamic>> toolDefinitions() {
    return [
      {
        'name': 'ping',
        'description': '存活探测，返回服务器状态与当前时间。',
        'inputSchema': {
          'type': 'object',
          'properties': <String, dynamic>{},
          'required': <String>[],
        },
      },
      {
        'name': 'version',
        'description': '返回 MiniMe-Code 服务器的名称、版本与状态。',
        'inputSchema': {
          'type': 'object',
          'properties': <String, dynamic>{},
          'required': <String>[],
        },
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> callTool(
      String name, Map<String, dynamic> arguments) async {
    switch (name) {
      case 'ping':
        return BaseJsonRpcMcpEngine.jsonResult({
          'status': 'ok',
          'server': 'MiniMe-Code',
          'time': DateTime.now().toUtc().toIso8601String(),
        });
      case 'version':
        return BaseJsonRpcMcpEngine.jsonResult({
          'name': 'MiniMe-Code',
          'version': '0.1.0',
          'status': 'placeholder',
        });
      default:
        return BaseJsonRpcMcpEngine.errorResult('Tool not found: $name');
    }
  }
}

/// MiniMe-Code 内存连接辅助函数。
///
/// 与 minime_chat / minime_data 的模式保持一致，便于统一在
/// mcp_provider 中按 server id 分发。
Map<String, dynamic> miniMeCodeToolListRaw() {
  final engine = MiniMeCodeMcpServerEngine();
  final tools = engine.toolDefinitions();
  engine.close();
  return {
    'tools': tools.map((e) {
      return {
        'name': e['name'],
        'description': e['description'],
        'inputSchema': e['inputSchema'],
      };
    }).toList(),
  };
}

/// 便于调试：把工具定义序列化为 JSON 字符串。
String miniMeCodeToolsToJson() {
  return const JsonEncoder.withIndent('  ')
      .convert(miniMeCodeToolListRaw());
}
