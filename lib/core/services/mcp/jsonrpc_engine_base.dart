import 'dart:async';
import 'dart:convert';

import 'package:mcp_client/mcp_client.dart' as mcp;

import 'inmemory_transport.dart';

/// 内置内存 MCP 服务器的 JSON-RPC 2.0 引擎基类。
///
/// 封装了所有内置服务器共用的样板：
/// - 解析 JSON-RPC 请求（支持批量数组）；
/// - 统一的 `_ok` / `_error` / `_noop` 响应封装；
/// - initialize / tools/list 的标准响应。
///
/// 子类只需提供：
/// - [serverName] / [serverVersion]：initialize 返回的 serverInfo；
/// - [toolDefinitions]：tools/list 返回的工具定义；
/// - [callTool]：分发 tools/call。
///
/// 所有错误均通过 [callTool] 返回 `isError: true` 的 content，
/// 不向 JSON-RPC 层抛异常。
abstract class BaseJsonRpcMcpEngine implements InMemoryMcpServer {
  bool _closed = false;

  /// initialize 响应中的 serverInfo.name。
  String get serverName;

  /// initialize 响应中的 serverInfo.version。
  String get serverVersion;

  /// tools/list 返回的工具定义列表（含 name / description / inputSchema）。
  List<Map<String, dynamic>> toolDefinitions();

  /// 分发 tools/call。返回的 map 形如
  /// `{'content': [...], 'isError': bool}`。
  Future<Map<String, dynamic>> callTool(String name, Map<String, dynamic> arguments);

  @override
  Future<dynamic> handleMessage(dynamic message) async {
    if (_closed) return null;
    if (message is List) {
      final out = <dynamic>[];
      for (final m in message) {
        out.add(await _handleSingle(m));
      }
      return out;
    }
    return await _handleSingle(message);
  }

  Future<Map<String, dynamic>> _handleSingle(dynamic raw) async {
    try {
      if (raw is! Map) {
        return _error(null, code: -32600, message: 'Invalid Request');
      }
      final req = raw.cast<String, dynamic>();
      final id = req['id'];
      final method = (req['method'] ?? '').toString();
      final params = (req['params'] is Map)
          ? (req['params'] as Map).cast<String, dynamic>()
          : <String, dynamic>{};

      switch (method) {
        case mcp.McpProtocol.methodInitialize:
          return _ok(id, result: {
            'serverInfo': {
              'name': serverName,
              'version': serverVersion,
            },
            'protocolVersion': mcp.McpProtocol.defaultVersion,
            'capabilities': {
              'tools': {'listChanged': false},
            },
          });

        case mcp.McpProtocol.methodListTools:
          return _ok(id, result: {'tools': toolDefinitions()});

        case mcp.McpProtocol.methodCallTool:
          final name = (params['name'] ?? '').toString();
          final arguments = (params['arguments'] is Map)
              ? (params['arguments'] as Map).cast<String, dynamic>()
              : <String, dynamic>{};
          final result = await callTool(name, arguments);
          return _ok(id, result: result);

        default:
          if (id == null) return _noop();
          return _error(id, code: -32601, message: 'Method not found: $method');
      }
    } catch (e) {
      return _error(null, code: -32603, message: 'Internal error: $e');
    }
  }

  @override
  void close() {
    _closed = true;
  }

  Map<String, dynamic> _ok(dynamic id, {required Map<String, dynamic> result}) {
    return {
      'jsonrpc': '2.0',
      if (id != null) 'id': id,
      'result': result,
    };
  }

  Map<String, dynamic> _error(dynamic id, {required int code, required String message}) {
    return {
      'jsonrpc': '2.0',
      if (id != null) 'id': id,
      'error': {'code': code, 'message': message},
    };
  }

  Map<String, dynamic> _noop() => {'jsonrpc': '2.0'};

  /// 构造成功的 content 响应。
  static Map<String, dynamic> textResult(String text, {bool isError = false}) {
    return {
      'content': [
        {'type': 'text', 'text': text}
      ],
      'isStreaming': false,
      'isError': isError,
    };
  }

  /// 构造成功的 JSON 响应（自动序列化）。
  static Map<String, dynamic> jsonResult(Object? data, {bool isError = false}) {
    final text = const JsonEncoder.withIndent('  ').convert(data);
    return textResult(text, isError: isError);
  }

  /// 构造错误 content 响应（不抛 JSON-RPC 错误，而是 isError=true 的工具结果）。
  static Map<String, dynamic> errorResult(String message) =>
      textResult(message, isError: true);
}
