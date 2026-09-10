import 'dart:async';

import 'package:mcp_client/mcp_client.dart' as mcp;

/// 内置内存 MCP 服务器引擎的抽象接口。
///
/// 所有内置（inmemory）服务器引擎都必须实现：
/// - [handleMessage]：处理一条 JSON-RPC 2.0 消息，返回响应（通知类消息可返回 null）；
/// - [close]：关闭引擎，释放资源。
///
/// 通用的 [InMemoryClientTransport] 会通过该接口把 mcp.Client 的消息转发给本地引擎，
/// 无需每个服务器各自实现一份 transport。
abstract class InMemoryMcpServer {
  /// 处理一条 JSON-RPC 消息。支持批量数组输入（返回响应数组）。
  Future<dynamic> handleMessage(dynamic message);

  /// 关闭引擎；之后 [handleMessage] 应直接返回 null。
  void close();
}

/// 通用内存 ClientTransport：直接把消息转发给本地 [InMemoryMcpServer] 引擎。
///
/// 与真实网络 transport 行为对齐：
/// - [send] 内部用 microtask 异步处理，避免阻塞调用栈；
/// - 通过 [onMessage] 广播引擎返回的响应；
/// - [close] 同时关闭引擎与流，[onClose] 完成。
class InMemoryClientTransport implements mcp.ClientTransport {
  InMemoryClientTransport(this._server);

  final InMemoryMcpServer _server;
  final _messageController = StreamController<dynamic>.broadcast();
  final _closeCompleter = Completer<void>();
  bool _closed = false;

  @override
  Stream<dynamic> get onMessage => _messageController.stream;

  @override
  Future<void> get onClose => _closeCompleter.future;

  @override
  void send(dynamic message) {
    if (_closed) return;
    // 异步处理，模拟真实 transport 的延迟语义
    Future.microtask(() async {
      final resp = await _server.handleMessage(message);
      if (_closed) return;
      if (resp != null) {
        _messageController.add(resp);
      }
    });
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _server.close();
    } catch (_) {}
    if (!_messageController.isClosed) _messageController.close();
    if (!_closeCompleter.isCompleted) _closeCompleter.complete();
  }
}
