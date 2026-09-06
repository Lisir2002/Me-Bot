
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'log_level.dart';
import 'log_tags.dart';
import 'logger.dart';

/// API 请求专用日志封装：自动脱敏 API key、记耗时、标准化请求/响应格式。
///
/// 使用：
/// ```dart
/// final req = ApiLogger.logRequest(
///   provider: 'SiliconFlow',
///   model: 'qwen3-8b',
///   method: 'POST',
///   url: '/v1/chat/completions',
///   body: {'messages': [...], 'api_key': 'sk-xxx'},
/// );
/// final response = await _send(url, body);
/// ApiLogger.logResponse(req, body: response.body);
/// ```
///
/// [ApiRequest] 返回一个句柄，包含时间戳和 session id，
/// 后续 logResponse / logError 会用同一个 session id 串起来。
class ApiLogger {
  ApiLogger._();

  /// 记录一次请求，返回句柄供响应/错误日志复用。
  static ApiRequest logRequest({
    required String provider,
    required String model,
    required String method,
    required String url,
    dynamic body,
    Map<String, String>? headers,
    String? sessionId,
  }) {
    final start = DateTime.now();
    final sid = sessionId ?? _shortId();

    final buf = StringBuffer();
    buf.writeln('REQUEST $sid  [$provider/$model] $method $url');
    if (headers != null && headers.isNotEmpty) {
      buf.writeln('  headers: ${_redactMap(headers)}');
    }
    buf.writeln('  body: ${_stringifyAndRedact(body)}');
    Logger.i(LogTags.apiReq, buf.toString());

    return ApiRequest(
      sessionId: sid,
      provider: provider,
      model: model,
      method: method,
      url: url,
      startedAt: start,
    );
  }

  /// 记录成功响应（非流式 / 流式都能接）。
  static void logResponse(
    ApiRequest req, {
    dynamic body,
    int? statusCode,
    String? rawSse,
  }) {
    final elapsedMs = DateTime.now().difference(req.startedAt).inMilliseconds;
    final buf = StringBuffer();
    buf.writeln('RESPONSE ${req.sessionId}  [$req.provider/${req.model}] '
        '${req.statusLabel} status=${statusCode ?? '-'} took=${elapsedMs}ms');
    if (rawSse != null) {
      buf.writeln('  raw SSE:\n${_truncate(_redactString(rawSse))}');
    } else {
      buf.writeln('  body: ${_truncate(_stringifyAndRedact(body))}');
    }
    Logger.i(LogTags.apiRes, buf.toString());
  }

  /// 记录请求失败（网络异常 / HTTP 错误）。
  static void logError(
    ApiRequest req, {
    Object? error,
    StackTrace? stack,
    int? statusCode,
    String? message,
  }) {
    final elapsedMs = DateTime.now().difference(req.startedAt).inMilliseconds;
    final buf = StringBuffer();
    buf.writeln('ERROR ${req.sessionId}  [${req.provider}/${req.model}] '
        '${req.method} ${req.url} status=${statusCode ?? '-'} took=${elapsedMs}ms');
    if (message != null) buf.writeln('  message: $message');
    Logger.e(LogTags.apiErr, buf.toString(), error, stack);
  }

  /// 记录非 HTTP 层的 Provider/模型相关操作（模型切换、API key 选择、Header 覆盖等）。
  static void logProviderEvent({
    required String action,
    required String provider,
    String? model,
    String? detail,
  }) {
    final buf = StringBuffer();
    buf.write('$action [$provider');
    if (model != null) buf.write('/$model');
    buf.write(']');
    if (detail != null) buf.write(' $detail');
    Logger.d(LogTags.provider, buf.toString());
  }

  // ── 脱敏工具 ──
  static String _stringifyAndRedact(dynamic body) {
    if (body == null) return 'null';
    String raw;
    if (body is String) {
      raw = body;
    } else {
      raw = jsonEncode(body);
    }
    return _truncate(_redactString(raw));
  }

  static String _redactMap(Map<String, String> map) {
    final out = <String, String>{};
    for (final k in map.keys) {
      out[k] = _redactHeaderValue(k, map[k]!);
    }
    return jsonEncode(out);
  }

  static String _redactHeaderValue(String key, String value) {
    final lk = key.toLowerCase();
    if (lk.contains('authorization') ||
        lk.contains('api-key') ||
        lk.contains('apikey') ||
        lk.contains('x-api') ||
        lk == 'cookie' ||
        lk.contains('secret') ||
        lk.contains('token')) {
      if (value.length <= 8) return '[redacted]';
      return '${value.substring(0, 4)}[redacted len=${value.length}]${value.substring(value.length - 4)}';
    }
    return value;
  }

  static String _redactString(String text) {
    if (text.length < 100) return text;
    var out = text;
    // Bearer / Authorization 头
    out = out.replaceAllMapped(
      RegExp(r'"(?:Authorization|Bearer|api[_-]?key|apikey|x-api-key|secret|token)"\s*:\s*"([^"]{4,})"', caseSensitive: false),
      (m) {
        final key = m.group(1)!;
        final masked = key.length <= 8 ? '[redacted]' : '${key.substring(0, 4)}...${key.substring(key.length - 4)}';
        return '"${m.group(1)}": "$masked"';
      },
    );
    // 裸 Bearer 字符串
    out = out.replaceAllMapped(
      RegExp(r'(Bearer\s+)([A-Za-z0-9_\-\.]{10,})'),
      (m) => '${m.group(1)}${_maskToken(m.group(2)!)}',
    );
    return out;
  }

  static String _maskToken(String token) {
    if (token.length <= 12) return '[redacted]';
    return '${token.substring(0, 4)}[redacted len=${token.length}]${token.substring(token.length - 4)}';
  }

  static String _truncate(String text, {int max = 4000}) {
    if (text.length <= max) return text;
    return '${text.substring(0, max)}\n  ... [truncated ${text.length - max} chars]';
  }

  static String _shortId() {
    final t = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
    return t.substring(t.length - 6);
  }
}

/// 一次 API 请求的上下文句柄，用来把请求/响应/错误串起来。
class ApiRequest {
  final String sessionId;
  final String provider;
  final String model;
  final String method;
  final String url;
  final DateTime startedAt;

  const ApiRequest({
    required this.sessionId,
    required this.provider,
    required this.model,
    required this.method,
    required this.url,
    required this.startedAt,
  });

  String get statusLabel => method;
}
