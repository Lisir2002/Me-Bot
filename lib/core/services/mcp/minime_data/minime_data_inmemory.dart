import 'package:mcp_client/mcp_client.dart' as mcp;

import '../inmemory_transport.dart';
import 'minime_data_server.dart';

/// 启动内置 MiniMe-Data MCP 服务器并连接一个客户端。
/// 返回已连接的 client 与 stop() 用于同时释放两端。
Future<({mcp.Client client, Future<void> Function() stop})>
    startDataMcpInMemory() async {
  final server = MiniMeDataMcpServerEngine();
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
