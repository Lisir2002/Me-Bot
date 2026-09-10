import 'package:mcp_client/mcp_client.dart' as mcp;

import '../inmemory_transport.dart';
import 'minime_chat_server.dart';

/// 构造函数调用友好的工具名（对齐 Cherry Studio 策略）。
String buildFunctionCallToolName(String serverName, String toolName) {
  String sanitizedServer = serverName.trim().replaceAll('-', '_');
  String sanitizedTool = toolName.trim().replaceAll('-', '_');
  String name = sanitizedTool;
  if (!sanitizedTool.contains(sanitizedServer.substring(0, sanitizedServer.length.clamp(0, 7)))) {
    final head = sanitizedServer.length >= 7 ? sanitizedServer.substring(0, 7) : sanitizedServer;
    name = '${head.isNotEmpty ? head : ''}-${sanitizedTool.isNotEmpty ? sanitizedTool : ''}';
  }
  name = name.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
  if (!RegExp(r'^[a-zA-Z]').hasMatch(name)) name = 'tool-$name';
  name = name.replaceAll(RegExp(r'[_-]{2,}'), '_');
  if (name.length > 63) name = name.substring(0, 63);
  if (name.endsWith('_') || name.endsWith('-')) name = name.substring(0, name.length - 1);
  return name;
}

/// 启动内置 MiniMe-Chat MCP 服务器并连接一个客户端。
/// 返回已连接的 client 与 stop() 用于同时释放两端。
Future<({mcp.Client client, Future<void> Function() stop})> startChatMcpInMemory() async {
  final server = MiniMeChatMcpServerEngine();
  final transport = InMemoryClientTransport(server);

  final client = mcp.McpClient.createClient(
    mcp.McpClient.simpleConfig(name: 'MiniMe-Core App', version: '1.0.0'),
  );
  await client.connect(transport);

  return (
    client: client,
    stop: () async {
      try {
        client.disconnect();
      } catch (_) {}
      try {
        transport.close();
      } catch (_) {}
    },
  );
}

/// 从已连接的内存客户端列出工具，并映射为稳定 id。
Future<List<(mcp.Tool tool, String id)>> listChatTools(mcp.Client client) async {
  final tools = await client.listTools();
  const serverName = 'MiniMe-Chat';
  return tools.map((t) => (t, buildFunctionCallToolName(serverName, t.name))).toList(growable: false);
}

/// 调用内存 fetch 工具。name 必须为 'fetch'。
Future<mcp.CallToolResult> callChatTool(
  mcp.Client client,
  String name, {
  required String url,
  String method = 'GET',
  Map<String, String>? headers,
  String? body,
}) async {
  final result = await client.callTool(name, {
    'url': url,
    'method': method,
    if (headers != null && headers.isNotEmpty) 'headers': headers,
    if (body != null) 'body': body,
  });
  return result;
}
