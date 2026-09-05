import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:html2md/html2md.dart' as html2md;
import 'package:mcp_client/mcp_client.dart' as mcp;

/// @minime-core/fetch — In-memory MCP server engine and transport (Flutter/Dart)
///
/// Provides a single `fetch` tool that mirrors industry practice (e.g. the
/// kelivo_fetch tool):
///   - GET or POST (with body)
///   - Markdown output by default, raw HTML via raw=true
///   - max_length truncation + start_index pagination
///   - JSON responses are auto pretty-printed
///
/// The server implements a minimal subset of MCP over JSON-RPC 2.0:
/// initialize, tools/list, tools/call. It is intended to run in the same
/// isolate as the Flutter app and connect to a standard mcp.Client via an
/// in-memory ClientTransport.

class MiniMeCoreFetchRequestPayload {
  final Uri url;
  final String method; // 'GET' | 'POST'
  final Map<String, String> headers;
  final String? body; // POST body
  final int maxLength; // output char cap
  final int startIndex; // pagination offset (chars)
  final bool raw; // if true, return raw HTML; else Markdown

  MiniMeCoreFetchRequestPayload({
    required this.url,
    this.method = 'GET',
    Map<String, String>? headers,
    this.body,
    this.maxLength = 20000,
    this.startIndex = 0,
    this.raw = false,
  }) : headers = headers ?? const {};

  static MiniMeCoreFetchRequestPayload parse(Object? args) {
    if (args is! Map) {
      throw ArgumentError('Invalid arguments: expected object with url[, method, headers, body, max_length, start_index, raw]');
    }
    final map = args.cast<String, dynamic>();
    final urlRaw = (map['url'] ?? '').toString().trim();
    final uri = Uri.tryParse(urlRaw);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw ArgumentError('Invalid url: $urlRaw');
    }
    final method = (map['method'] ?? 'GET').toString().toUpperCase();
    final headers = <String, String>{};
    final headersAny = map['headers'];
    if (headersAny is Map) {
      headersAny.forEach((k, v) {
        if (k == null || v == null) return;
        headers[k.toString()] = v.toString();
      });
    }
    final body = map['body']?.toString();
    final maxLength = (map['max_length'] as num?)?.toInt() ?? 20000;
    final startIndex = (map['start_index'] as num?)?.toInt() ?? 0;
    final raw = map['raw'] == true;
    return MiniMeCoreFetchRequestPayload(
      url: uri,
      method: method == 'POST' ? 'POST' : 'GET',
      headers: headers,
      body: body,
      maxLength: maxLength > 0 ? maxLength : 20000,
      startIndex: startIndex > 0 ? startIndex : 0,
      raw: raw,
    );
  }
}

class MiniMeCoreFetcher {
  static const _defaultUA =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

  static Future<http.Response> _fetch(MiniMeCoreFetchRequestPayload payload) async {
    try {
      final merged = <String, String>{
        'User-Agent': _defaultUA,
        ...payload.headers,
      };
      final http.Response resp;
      if (payload.method == 'POST') {
        resp = await http.post(payload.url, headers: merged, body: payload.body);
      } else {
        resp = await http.get(payload.url, headers: merged);
      }
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      return resp;
    } catch (e) {
      throw Exception('Failed to fetch ${payload.url}: ${e is Exception ? e.toString() : 'Unknown error'}');
    }
  }

  static Future<Map<String, dynamic>> fetch(MiniMeCoreFetchRequestPayload payload) async {
    try {
      final resp = await _fetch(payload);
      final contentType = (resp.headers['content-type'] ?? '').toLowerCase();

      // Decide output format:
      //  - JSON response -> pretty JSON
      //  - raw=true        -> raw HTML
      //  - otherwise       -> compact Markdown
      String text;
      if (contentType.contains('application/json')) {
        final dynamic data = jsonDecode(resp.body);
        text = const JsonEncoder.withIndent('  ').convert(data);
      } else if (payload.raw) {
        text = resp.body;
      } else {
        text = html2md.convert(resp.body);
      }

      // Truncate + paginate by character index.
      final total = text.length;
      final start = payload.startIndex.clamp(0, total);
      final end = (start + payload.maxLength).clamp(0, total);
      final chunk = text.substring(start, end);

      final buf = StringBuffer();
      buf.write(chunk);
      if (end < total) {
        buf.write('\n\n[... truncated: total $total characters; '
            're-run with start_index=$end to continue ...]');
      }
      return _ok(buf.toString().trim());
    } catch (e) {
      return _err(e.toString());
    }
  }

  static Map<String, dynamic> _ok(String text) => {
        'content': [
          {'type': 'text', 'text': text}
        ],
        'isStreaming': false,
        'isError': false,
      };

  static Map<String, dynamic> _err(String message) => {
        'content': [
          {'type': 'text', 'text': message}
        ],
        'isStreaming': false,
        'isError': true,
      };
}

/// Minimal JSON-RPC server for MCP that serves @minime-core/fetch tools.
class MiniMeCoreFetchMcpServerEngine {
  bool _closed = false;

  Future<dynamic> handleMessage(dynamic message) async {
    if (_closed) return null;

    // Support batch arrays defensively (return array of responses)
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
              'name': '@minime-core/fetch',
              'version': '0.2.0',
            },
            'protocolVersion': mcp.McpProtocol.defaultVersion,
            'capabilities': {
              'tools': {'listChanged': false},
            },
          });

        case mcp.McpProtocol.methodListTools:
          return _ok(id, result: {
            'tools': _toolDefinitions(),
          });

        case mcp.McpProtocol.methodCallTool:
          final name = (params['name'] ?? '').toString();
          final arguments = (params['arguments'] is Map)
              ? (params['arguments'] as Map).cast<String, dynamic>()
              : <String, dynamic>{};

          if (name == 'fetch') {
            MiniMeCoreFetchRequestPayload payload;
            try {
              payload = MiniMeCoreFetchRequestPayload.parse(arguments);
            } catch (e) {
              return _ok(id, result: MiniMeCoreFetcher._err(e.toString()));
            }
            return _ok(id, result: await MiniMeCoreFetcher.fetch(payload));
          }
          return _error(id, code: -32101, message: 'Tool not found: $name');

        default:
          if (id == null) {
            return _noop();
          }
          return _error(id, code: -32601, message: 'Method not found: $method');
      }
    } catch (e) {
      return _error(null, code: -32603, message: 'Internal error: $e');
    }
  }

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

  static const String _fetchDescription = '''
Fetch the public contents of a web page or API endpoint.

Guidelines for the model:
- Only fetch a URL that already appears in the conversation: one provided by
  the user or returned by a prior web_search, fetch, or other tool.
- Cannot access content that requires authentication, including private
  documents or pages behind login walls.
- By default, HTML is converted to compact Markdown to save tokens. Use
  raw=true only when the exact HTML source is required.
- Output is bounded by max_length (default 20000 chars). If the result is
  truncated, continue by calling fetch again with start_index set to the
  value shown in the truncation notice.
- method=POST with a body calls an API endpoint the user has asked for. A
  POST response cannot be continued with start_index; raise max_length if
  the response is truncated.
- If the response Content-Type is JSON, it is automatically pretty-printed.
''';

  List<Map<String, dynamic>> _toolDefinitions() {
    return [
      {
        'name': 'fetch',
        'description': _fetchDescription.trim(),
        'inputSchema': {
          'type': 'object',
          'properties': {
            'url': {
              'type': 'string',
              'description': 'URL of the page or API endpoint to fetch',
            },
            'method': {
              'type': 'string',
              'enum': ['GET', 'POST'],
              'default': 'GET',
              'description': 'HTTP method. Use POST for API calls that need a body.',
            },
            'headers': {
              'type': 'object',
              'description': 'Optional HTTP headers to include in the request',
            },
            'body': {
              'type': 'string',
              'description': 'Request body for POST requests',
            },
            'max_length': {
              'type': 'integer',
              'default': 20000,
              'description': 'Maximum number of characters to return',
            },
            'start_index': {
              'type': 'integer',
              'default': 0,
              'description': 'Character offset to start from, for paginating long content',
            },
            'raw': {
              'type': 'boolean',
              'default': false,
              'description': 'If true, return raw HTML instead of Markdown',
            },
          },
          'required': ['url'],
        },
      },
    ];
  }
}

/// In-memory ClientTransport that directly invokes the local server engine.
class MiniMeCoreInMemoryClientTransport implements mcp.ClientTransport {
  final MiniMeCoreFetchMcpServerEngine _server;
  final _messageController = StreamController<dynamic>.broadcast();
  final _closeCompleter = Completer<void>();
  bool _closed = false;

  MiniMeCoreInMemoryClientTransport(this._server);

  @override
  Stream<dynamic> get onMessage => _messageController.stream;

  @override
  Future<void> get onClose => _closeCompleter.future;

  @override
  void send(dynamic message) {
    if (_closed) return;
    // Process asynchronously to mimic real transport
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
