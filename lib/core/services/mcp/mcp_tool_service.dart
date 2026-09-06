import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:provider/provider.dart';
import 'package:mcp_client/mcp_client.dart' as mcp;
import '../../providers/mcp_provider.dart';
import '../chat/chat_service.dart';
import '../../providers/assistant_provider.dart';

class McpToolService extends ChangeNotifier {
  McpToolService();

  /// UI 提供的审批回调：返回 true 允许执行，false 拒绝。
  /// 当某个工具 requireApproval=true 时，执行前会先询问。
  typedef ToolApprovalGate = Future<bool> Function(
    String serverName,
    String toolName,
    Map<String, dynamic> arguments,
  );

  String _deniedText(String serverName, String toolName) =>
      '{"type":"tool_denied","message":"User declined to run this tool",'
      '"tool":"$toolName","server":"$serverName",'
      '"instruction":"Do not call this tool again unless the user explicitly asks."}';

  /// 返回 true 表示通过审批（未开启审批直接通过）。
  Future<bool> _checkApproval(
    McpToolConfig tool,
    String serverName,
    String toolName,
    Map<String, dynamic> arguments,
    ToolApprovalGate? gate,
  ) async {
    if (!tool.requireApproval) return true;
    if (gate == null) return true; // 无审批 UI 时视为自动放行
    return await gate(serverName, toolName, arguments);
  }

  List<McpToolConfig> listAvailableToolsForConversation(
    McpProvider mcpProvider,
    ChatService chat,
    String conversationId,
  ) {
    final selected = chat.getConversationMcpServers(conversationId).toSet();
    return mcpProvider.getEnabledToolsForServers(selected);
  }

  List<McpToolConfig> listAvailableToolsForAssistant(
    McpProvider mcpProvider,
    AssistantProvider assistants,
    String? assistantId,
  ) {
    final a = (assistantId != null) ? assistants.getById(assistantId) : assistants.currentAssistant;
    final selected = (a?.mcpServerIds ?? const <String>[]).toSet();
    return mcpProvider.getEnabledToolsForServers(selected);
  }

  Future<mcp.CallToolResult?> callToolForConversation(
    McpProvider mcpProvider,
    ChatService chat, {
      required String conversationId,
      required String toolName,
      Map<String, dynamic> arguments = const {},
      ToolApprovalGate? approvalGate,
  }) async {
    final selected = chat.getConversationMcpServers(conversationId).toSet();
    // debugPrint('[MCP/Call/Select] convo=$conversationId tool=$toolName selectedServers=${selected.join(',')}');
    if (selected.isEmpty) return null;

    // Find a server that has this tool enabled
    final connected = mcpProvider.connectedServers.where((s) => selected.contains(s.id)).toList();
    // debugPrint('[MCP/Call/Select] connectedAndSelected=${connected.map((s)=>s.id).join(',')}');
    for (final s in connected) {
      McpToolConfig? tool;
      for (final t in s.tools) {
        if (t.enabled && t.name == toolName) {
          tool = t;
          break;
        }
      }
      if (tool != null) {
        // debugPrint('[MCP/Call/Select] using server=${s.id} name=${s.name} transport=${s.transport.name}');
        final ok = await _checkApproval(tool, s.name, toolName, arguments, approvalGate);
        if (!ok) {
          return mcp.CallToolResult(
            [mcp.TextContent(text: _deniedText(s.name, toolName))],
            isError: false,
          );
        }
        return await mcpProvider.callTool(s.id, toolName, arguments);
      }
    }
    return null;
  }

  // Convenience: call tool and flatten result contents to plain text
  Future<String> callToolTextForConversation(
    McpProvider mcpProvider,
    ChatService chat, {
      required String conversationId,
      required String toolName,
      Map<String, dynamic> arguments = const {},
      ToolApprovalGate? approvalGate,
  }) async {
    // Attempt call via selected server
    final selected = chat.getConversationMcpServers(conversationId).toSet();
    final connected = mcpProvider.connectedServers.where((s) => selected.contains(s.id)).toList();
    mcp.CallToolResult? res;
    McpServerConfig? usedServer;
    for (final s in connected) {
      McpToolConfig? tool;
      for (final t in s.tools) {
        if (t.enabled && t.name == toolName) {
          tool = t;
          break;
        }
      }
      if (tool == null) continue;
      usedServer = s;
      final ok = await _checkApproval(tool, s.name, toolName, arguments, approvalGate);
      if (!ok) return _deniedText(s.name, toolName);
      res = await mcpProvider.callTool(s.id, toolName, arguments);
      break;
    }
    if (res == null) {
      if (usedServer != null) {
        final errMsg = mcpProvider.errorFor(usedServer.id) ?? 'Unknown error';
        final schema = usedServer.tools.firstWhere((t) => t.name == toolName).schema;
        return _renderToolErrorForModel(
          serverName: usedServer.name,
          toolName: toolName,
          arguments: arguments,
          errorMessage: errMsg,
          schema: schema,
        );
      }
      return '';
    }
    final buf = StringBuffer();
    // Be liberal in what we accept: many servers return different content variants.
    for (final c in res.content) {
      try {
        // Known types from mcp_client
        if (c is mcp.TextContent) {
          if ((c.text).trim().isNotEmpty) buf.writeln(c.text);
          continue;
        }
        if (c is mcp.ResourceContent) {
          final t = (c.text ?? '').toString();
          if (t.trim().isNotEmpty) {
            buf.writeln(t);
          } else {
            final uri = (c.uri).toString();
            if (uri.isNotEmpty) buf.writeln('resource: $uri');
          }
          continue;
        }
        if (c is mcp.ImageContent) {
          final url = (c.url ?? '').toString();
          final mime = (c.mimeType ?? '').toString();
          buf.writeln('[image:${url.isNotEmpty ? url : mime}]');
          continue;
        }
        // Try dynamic accessors that some adapters may expose
        final dyn = c as dynamic;
        try {
          final txt = (dyn.text as String?);
          if (txt != null && txt.trim().isNotEmpty) {
            buf.writeln(txt);
            continue;
          }
        } catch (_) {}
        try {
          final uri = (dyn.uri as String?);
          if (uri != null && uri.isNotEmpty) {
            buf.writeln('resource: $uri');
            continue;
          }
        } catch (_) {}
        // As a last resort, serialize to JSON if available
        try {
          final json = (dyn.toJson as dynamic).call();
          buf.writeln(const JsonEncoder.withIndent('  ').convert(json));
          continue;
        } catch (_) {}
        // Fallback to a readable string (avoid Instance of ... when possible)
        final s = c.toString();
        if (!s.startsWith('Instance of')) buf.writeln(s);
      } catch (_) {
        // ignore single content parse errors and continue
      }
    }
    return buf.toString().trim();
  }

  Future<String> callToolTextForAssistant(
    McpProvider mcpProvider,
    AssistantProvider assistants, {
      required String? assistantId,
      required String toolName,
      Map<String, dynamic> arguments = const {},
      ToolApprovalGate? approvalGate,
  }) async {
    // try servers selected for the assistant
    final a = (assistantId != null) ? assistants.getById(assistantId) : assistants.currentAssistant;
    final selected = (a?.mcpServerIds ?? const <String>[]).toSet();
    // debugPrint('[MCP/Call/Select] assistant=${assistantId ?? a?.id ?? '(current)'} tool=$toolName selectedServers=${selected.join(',')}');
    if (selected.isEmpty) return '';
    for (final s in mcpProvider.connectedServers.where((s) => selected.contains(s.id))) {
      McpToolConfig? tool;
      for (final t in s.tools) {
        if (t.enabled && t.name == toolName) {
          tool = t;
          break;
        }
      }
      if (tool == null) continue;
      // debugPrint('[MCP/Call/Select] using server=${s.id} name=${s.name} transport=${s.transport.name}');
      final ok = await _checkApproval(tool, s.name, toolName, arguments, approvalGate);
      if (!ok) return _deniedText(s.name, toolName);
      final res = await mcpProvider.callTool(s.id, toolName, arguments);
      if (res == null) {
        final errMsg = mcpProvider.errorFor(s.id) ?? 'Unknown error';
        final schema = s.tools.firstWhere((t) => t.name == toolName).schema;
        return _renderToolErrorForModel(
          serverName: s.name,
          toolName: toolName,
          arguments: arguments,
          errorMessage: errMsg,
          schema: schema,
        );
      }
      final buf = StringBuffer();
      for (final c in res.content) {
        try {
          if (c is mcp.TextContent) {
            if ((c.text).trim().isNotEmpty) buf.writeln(c.text);
            continue;
          }
          if (c is mcp.ResourceContent) {
            final t = (c.text ?? '').toString();
            if (t.trim().isNotEmpty) {
              buf.writeln(t);
            } else {
              final uri = (c.uri).toString();
              if (uri.isNotEmpty) buf.writeln('resource: $uri');
            }
            continue;
          }
          if (c is mcp.ImageContent) {
            final url = (c.url ?? '').toString();
            final mime = (c.mimeType ?? '').toString();
            buf.writeln('[image:${url.isNotEmpty ? url : mime}]');
            continue;
          }
          final dyn = c as dynamic;
          try {
            final txt = (dyn.text as String?);
            if (txt != null && txt.trim().isNotEmpty) {
              buf.writeln(txt);
              continue;
            }
          } catch (_) {}
          try {
            final uri = (dyn.uri as String?);
            if (uri != null && uri.isNotEmpty) {
              buf.writeln('resource: $uri');
              continue;
            }
          } catch (_) {}
          try {
            final json = (dyn.toJson as dynamic).call();
            buf.writeln(const JsonEncoder.withIndent('  ').convert(json));
            continue;
          } catch (_) {}
          final s = c.toString();
          if (!s.startsWith('Instance of')) buf.writeln(s);
        } catch (e, st) {
          // debugPrint('[MCP/Call/TextParseError] server=${s.id} tool=$toolName type=${c.runtimeType} err=$e');
          // debugPrint(st.toString());
        }
      }
      return buf.toString().trim();
    }
    return '';
  }

  String _renderToolErrorForModel({
    required String serverName,
    required String toolName,
    required Map<String, dynamic> arguments,
    required String errorMessage,
    Map<String, dynamic>? schema,
  }) {
    // Provide a concise JSON for the model to self-correct and retry
    final map = <String, dynamic>{
      'type': 'tool_error',
      'error': 'invalid_arguments',
      'message': errorMessage,
      'tool': toolName,
      'server': serverName,
      'lastArguments': arguments,
      if (schema != null && schema.isNotEmpty) 'parametersSchema': schema,
      'instruction': 'Revise arguments to satisfy parametersSchema, then call the same tool again.'
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }
}
