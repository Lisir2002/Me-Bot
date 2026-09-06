import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'settings_provider.dart';
import '../services/api_key_manager.dart';
import 'package:minime_core/secrets/fallback.dart';
import '../services/api/google_service_account_auth.dart';

enum ModelType { chat, embedding }
enum Modality { text, image }
enum ModelAbility { tool, reasoning }

class ModelInfo {
  final String id;
  final String displayName;
  final ModelType type;
  final List<Modality> input;
  final List<Modality> output;
  final List<ModelAbility> abilities;
  ModelInfo({
    required this.id,
    required this.displayName,
    this.type = ModelType.chat,
    this.input = const [Modality.text],
    this.output = const [Modality.text],
    this.abilities = const [],
  });

  ModelInfo copyWith({
    String? id,
    String? displayName,
    ModelType? type,
    List<Modality>? input,
    List<Modality>? output,
    List<ModelAbility>? abilities,
  }) => ModelInfo(
        id: id ?? this.id,
        displayName: displayName ?? this.displayName,
        type: type ?? this.type,
        input: input ?? this.input,
        output: output ?? this.output,
        abilities: abilities ?? this.abilities,
      );
}

/// A capability entry in the known-model registry.
///
/// `re` is matched (substring, case-normalized) against the model id.
/// The first matching entry wins, so order matters: list specific models
/// before their generic families.
class _CapEntry {
  final RegExp re;
  final bool tool;
  final bool reasoning;
  final bool vision;
  const _CapEntry(this.re,
      {this.tool = false, this.reasoning = false, this.vision = false});
}

class ModelRegistry {
  /// Known-model capability registry.
  ///
  /// Industry practice (LobeChat / Cherry Studio) is to declare capabilities
  /// explicitly instead of guessing from the model id. The entries below cover
  /// the major model families across providers so that tool calling, reasoning
  /// and vision are surfaced correctly in the model picker without requiring
  /// the user to enable them manually.
  static final List<_CapEntry> _knownModels = [
    // ---- OpenAI ----
    _CapEntry(RegExp(r'gpt-5'), tool: true, reasoning: true, vision: true),
    _CapEntry(RegExp(r'gpt-oss'), tool: true, reasoning: true),
    _CapEntry(RegExp(r'o4-mini'), tool: true, reasoning: true, vision: true),
    _CapEntry(RegExp(r'o3'), tool: true, reasoning: true, vision: true),
    _CapEntry(RegExp(r'o1'), tool: true, reasoning: true, vision: true),
    _CapEntry(RegExp(r'gpt-4\.1'), tool: true, vision: true),
    _CapEntry(RegExp(r'gpt-4o'), tool: true, vision: true),
    _CapEntry(RegExp(r'gpt-4-turbo'), tool: true, vision: true),
    _CapEntry(RegExp(r'gpt-4-vision'), tool: true, vision: true),
    _CapEntry(RegExp(r'gpt-4'), tool: true),
    // Legacy completions models expose no function calling.
    _CapEntry(RegExp(r'gpt-3\.5-turbo-instruct|gpt-3\.5-instruct'),
        tool: false),
    _CapEntry(RegExp(r'gpt-3\.5'), tool: true),
    // ---- Anthropic Claude ----
    _CapEntry(RegExp(r'claude-(opus|sonnet|haiku)-4'),
        tool: true, reasoning: true, vision: true),
    _CapEntry(RegExp(r'claude-3-7|claude-3\.7'),
        tool: true, reasoning: true, vision: true),
    _CapEntry(RegExp(r'claude-3-5|claude-3\.5'), tool: true, vision: true),
    _CapEntry(RegExp(r'claude-3'), tool: true, vision: true),
    _CapEntry(RegExp(r'claude-2|claude-instant|claude-1'), tool: false),
    _CapEntry(RegExp(r'claude'), tool: true, vision: true),
    // ---- Google Gemini ----
    _CapEntry(RegExp(r'gemini-3'), tool: true, reasoning: true, vision: true),
    _CapEntry(RegExp(r'gemini-2\.5'),
        tool: true, reasoning: true, vision: true),
    _CapEntry(RegExp(r'gemini-2'), tool: true, vision: true),
    _CapEntry(RegExp(r'gemini-1\.5'), tool: true, vision: true),
    _CapEntry(RegExp(r'gemini-1'), tool: true, vision: true),
    _CapEntry(RegExp(r'gemini'), tool: true, vision: true),
    // ---- DeepSeek ----
    _CapEntry(RegExp(r'deepseek-reasoner|deepseek-r1|deepseek-rs'),
        tool: true, reasoning: true),
    _CapEntry(RegExp(r'deepseek-chat|deepseek-v3|deepseek-coder|deepseek-v2'),
        tool: true),
    _CapEntry(RegExp(r'deepseek'), tool: true),
    // ---- Qwen (Alibaba / DashScope) ----
    _CapEntry(RegExp(r'qwen3.*vl'),
        tool: true, reasoning: true, vision: true),
    _CapEntry(RegExp(r'qwen[^/]*vl|qwen[^/]*-omni'), tool: true, vision: true),
    _CapEntry(RegExp(r'qwq'), tool: true, reasoning: true),
    _CapEntry(RegExp(r'qwen3'), tool: true, reasoning: true),
    _CapEntry(RegExp(
        r'qwen2\.5|qwen2|qwen-turbo|qwen-plus|qwen-max|qwen-long|qwen-coder|qwen-math'),
        tool: true),
    _CapEntry(RegExp(r'qwen'), tool: true),
    // ---- Moonshot / Kimi ----
    _CapEntry(RegExp(r'kimi-k2\.5'),
        tool: true, reasoning: true, vision: true),
    _CapEntry(RegExp(r'kimi-k2'), tool: true, reasoning: true),
    _CapEntry(RegExp(r'moonshot-v1.*vision|kimi-vl|kimi-.*vl'),
        tool: true, vision: true),
    _CapEntry(RegExp(r'moonshot-v1|kimi-latest|kimi'), tool: true),
    // ---- Zhipu GLM ----
    _CapEntry(RegExp(r'glm-4\.5v|glm-4\.6v|glm-4\.5-v|glm-4\.6-v|glm-z1'),
        tool: true, reasoning: true, vision: true),
    _CapEntry(RegExp(r'glm-4v|glm-4-v'), tool: true, vision: true),
    _CapEntry(RegExp(r'glm-4\.6|glm-4\.5'), tool: true, reasoning: true),
    _CapEntry(RegExp(r'glm-4'), tool: true),
    _CapEntry(RegExp(r'glm'), tool: true),
    // ---- Doubao (Volcengine) ----
    _CapEntry(RegExp(r'doubao.*vl|doubao.*vision'), tool: true, vision: true),
    _CapEntry(RegExp(r'doubao-seed-1\.6|doubao-1\.6|doubao-seed-2'),
        tool: true, reasoning: true),
    _CapEntry(RegExp(r'doubao'), tool: true),
    // ---- xAI Grok ----
    _CapEntry(RegExp(r'grok-4'), tool: true, reasoning: true, vision: true),
    _CapEntry(RegExp(r'grok-3-reasoner|grok-3-mini-reasoner'),
        tool: true, reasoning: true, vision: true),
    _CapEntry(RegExp(r'grok-3'), tool: true, vision: true),
    _CapEntry(RegExp(r'grok-2'), tool: true, vision: true),
    _CapEntry(RegExp(r'grok'), tool: true),
    // ---- Mistral ----
    _CapEntry(RegExp(r'pixtral'), tool: true, vision: true),
    _CapEntry(RegExp(r'mistral'), tool: true),
    // ---- Meta Llama ----
    _CapEntry(RegExp(r'llama-3\.2.*vision|llama-4-maverick|llama-4-scout'),
        tool: true, vision: true),
    _CapEntry(RegExp(r'llama'), tool: true),
    // ---- InternLM ----
    _CapEntry(RegExp(r'intern.*s1|intern-s2|intern3|internlm3'),
        tool: true, reasoning: true),
    _CapEntry(RegExp(r'intern.*vl|internvl|intern.*vision'),
        tool: true, vision: true),
    _CapEntry(RegExp(r'intern'), tool: true),
    // ---- StepFun ----
    _CapEntry(RegExp(r'step-4|step-3|step-2'), tool: true, reasoning: true),
    _CapEntry(RegExp(r'step-1v|step-1\.5v'), tool: true, vision: true),
    _CapEntry(RegExp(r'step-1'), tool: true),
    // ---- Yi ----
    _CapEntry(RegExp(r'yi-vl|yi-.*vision'), tool: true, vision: true),
    _CapEntry(RegExp(r'yi-'), tool: true),
    // ---- MiniMax ----
    _CapEntry(RegExp(r'minimax-reasoner'), tool: true, reasoning: true),
    _CapEntry(RegExp(r'minimax.*vl'), tool: true, vision: true),
    _CapEntry(RegExp(r'minimax'), tool: true),
    // ---- Baidu Ernie ----
    _CapEntry(RegExp(r'ernie-x1'), tool: true, reasoning: true),
    _CapEntry(RegExp(r'ernie-4\.5'), tool: true, vision: true),
    _CapEntry(RegExp(r'ernie'), tool: true),
    // ---- Tencent Hunyuan ----
    _CapEntry(RegExp(r'hunyuan-t1'), tool: true, reasoning: true),
    _CapEntry(RegExp(r'hunyuan.*vl|hunyuan.*vision'), tool: true, vision: true),
    _CapEntry(RegExp(r'hunyuan'), tool: true),
    // ---- iFlytek Spark ----
    _CapEntry(RegExp(r'spark-v4|spark-4'), tool: true),
    _CapEntry(RegExp(r'spark'), tool: true),
    // ---- Cohere ----
    _CapEntry(RegExp(r'command-r'), tool: true),
    _CapEntry(RegExp(r'command'), tool: true),
    // ---- Microsoft Phi / Gemma ----
    _CapEntry(RegExp(r'phi-4-multimodal|phi-3\.5.*vision|phi-4\.1.*vision'),
        tool: true, vision: true),
    _CapEntry(RegExp(r'phi'), tool: true),
    _CapEntry(RegExp(r'gemma-3'), tool: true, vision: true),
    _CapEntry(RegExp(r'gemma'), tool: true),
    // ---- Other open / aggregator models ----
    _CapEntry(RegExp(r'baichuan'), tool: true),
    _CapEntry(RegExp(r'chatglm'), tool: true),
    _CapEntry(RegExp(r'ministral'), tool: true),
    // Image-generation models whose id does not contain "image"
    _CapEntry(RegExp(r'midjourney|dall-e|stable-diffusion|sdxl|flux'),
        tool: false),
  ];

  /// Legacy instruct / completions models: no function calling.
  static final RegExp _legacyNoTool = RegExp(
      r'(-instruct|davinci|curie|babbage|ada-002|text-davinci|text-curie|text-babbage|text-ada|rerank|re-rank)');

  /// Embedding / rerank models: text-only, no tool calling.
  static final RegExp _embeddingLike = RegExp(
      r'(embedding|embed-|bge-|m3e-|jina-embedding|text-embedding|rerank)');

  /// Fallback heuristics for reasoning / vision on unrecognized model ids.
  static final RegExp _fallbackReasoning =
      RegExp(r'(reasoner|thinking|think-|qwq|z1|s1|r1|r2|t1|x1|step-[2-4])');
  static final RegExp _fallbackVision =
      RegExp(r'(-vl|-vision|vision-|omni|pixtral|maverick)');

  static ModelInfo infer(ModelInfo base) {
    final id = base.id.toLowerCase();
    final inMods = <Modality>[...base.input];
    final outMods = <Modality>[...base.output];
    final ab = <ModelAbility>[...base.abilities];
    // If model id contains 'image', treat it as an image model:
    // - Input and output both include image
    // - No tool or reasoning abilities
    if (id.contains('image')) {
      if (!inMods.contains(Modality.image)) inMods.add(Modality.image);
      if (!outMods.contains(Modality.image)) outMods.add(Modality.image);
      ab.removeWhere((x) => x == ModelAbility.tool || x == ModelAbility.reasoning);
      return base.copyWith(input: inMods, output: outMods, abilities: ab);
    }
    // Embedding / rerank models expose no tool or reasoning capabilities.
    if (_embeddingLike.hasMatch(id)) {
      return base.copyWith(input: inMods, output: outMods, abilities: ab);
    }

    // Known-model capability registry (first match wins).
    bool tool = false, reasoning = false, vision = false;
    var matched = false;
    for (final c in _knownModels) {
      if (c.re.hasMatch(id)) {
        tool = c.tool;
        reasoning = c.reasoning;
        vision = c.vision;
        matched = true;
        break;
      }
    }

    if (!matched) {
      // Legacy instruct / completions models expose no function calling.
      if (_legacyNoTool.hasMatch(id)) {
        return base.copyWith(input: inMods, output: outMods, abilities: ab);
      }
      // Fallback for unrecognized models:
      // Chat models on OpenAI-compatible providers almost universally support
      // function calling, so default tool=true instead of hiding the capability
      // and forcing the user to enable it manually.
      tool = true;
      reasoning = _fallbackReasoning.hasMatch(id);
      vision = _fallbackVision.hasMatch(id);
    }

    if (tool && !ab.contains(ModelAbility.tool)) ab.add(ModelAbility.tool);
    if (reasoning && !ab.contains(ModelAbility.reasoning)) ab.add(ModelAbility.reasoning);
    if (vision && !inMods.contains(Modality.image)) inMods.add(Modality.image);
    return base.copyWith(input: inMods, output: outMods, abilities: ab);
  }
}

abstract class BaseProvider {
  Future<List<ModelInfo>> listModels(ProviderConfig cfg);
}

class _Http {
  static http.Client clientFor(ProviderConfig cfg) {
    final enabled = cfg.proxyEnabled == true;
    final host = (cfg.proxyHost ?? '').trim();
    final portStr = (cfg.proxyPort ?? '').trim();
    final user = (cfg.proxyUsername ?? '').trim();
    final pass = (cfg.proxyPassword ?? '').trim();
    if (enabled && host.isNotEmpty && portStr.isNotEmpty) {
      final port = int.tryParse(portStr) ?? 8080;
      final io = HttpClient();
      io.findProxy = (uri) => 'PROXY $host:$port';
      if (user.isNotEmpty) {
        io.addProxyCredentials(host, port, '', HttpClientBasicCredentials(user, pass));
      }
      return IOClient(io);
    }
    return http.Client();
  }
}

class OpenAIProvider extends BaseProvider {
  @override
  Future<List<ModelInfo>> listModels(ProviderConfig cfg) async {
    final key = ProviderManager._effectiveApiKey(cfg);
    if (key.isEmpty) return [];
    final client = _Http.clientFor(cfg);
    try {
      final uri = Uri.parse('${cfg.baseUrl}/models');
      final res = await client.get(uri, headers: {
        'Authorization': 'Bearer $key',
      });
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final data = (jsonDecode(res.body)['data'] as List?) ?? [];
        return [
          for (final e in data)
            if (e is Map && e['id'] is String)
              ModelRegistry.infer(ModelInfo(id: e['id'] as String, displayName: e['id'] as String))
        ];
      }
      return [];
    } finally {
      client.close();
    }
  }
}

class ClaudeProvider extends BaseProvider {
  static const String anthropicVersion = '2023-06-01';
  @override
  Future<List<ModelInfo>> listModels(ProviderConfig cfg) async {
    final key = ProviderManager._effectiveApiKey(cfg);
    if (key.isEmpty) return [];
    final client = _Http.clientFor(cfg);
    try {
      final uri = Uri.parse('${cfg.baseUrl}/models');
      final res = await client.get(uri, headers: {
        'x-api-key': key,
        'anthropic-version': anthropicVersion,
      });
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final obj = jsonDecode(res.body) as Map<String, dynamic>;
        final data = (obj['data'] as List?) ?? [];
        return [
          for (final e in data)
            if (e is Map && e['id'] is String)
              ModelRegistry.infer(ModelInfo(
                id: e['id'] as String,
                displayName: (e['display_name'] as String?) ?? (e['id'] as String),
              ))
        ];
      }
      return [];
    } finally {
      client.close();
    }
  }
}

class GoogleProvider extends BaseProvider {
  String _buildUrl(ProviderConfig cfg) {
    if (cfg.vertexAI == true && (cfg.location?.isNotEmpty == true) && (cfg.projectId?.isNotEmpty == true)) {
      final loc = cfg.location!;
      final proj = cfg.projectId!;
      return 'https://aiplatform.googleapis.com/v1/projects/$proj/locations/$loc/publishers/google/models';
    }
    final base = cfg.baseUrl.endsWith('/') ? cfg.baseUrl.substring(0, cfg.baseUrl.length - 1) : cfg.baseUrl;
    final key = ProviderManager._effectiveApiKey(cfg);
    if (key.isNotEmpty) {
      return '$base/models?key=${Uri.encodeQueryComponent(key)}';
    }
    return '$base/models';
  }

  @override
  Future<List<ModelInfo>> listModels(ProviderConfig cfg) async {
    final client = _Http.clientFor(cfg);
    try {
      final url = _buildUrl(cfg);
      final headers = <String, String>{};
      if (cfg.vertexAI == true) {
        final jsonStr = (cfg.serviceAccountJson ?? '').trim();
        if (jsonStr.isNotEmpty) {
          try {
            final token = await GoogleServiceAccountAuth.getAccessTokenFromJson(jsonStr);
            headers['Authorization'] = 'Bearer $token';
            final proj = (cfg.projectId ?? '').trim();
            if (proj.isNotEmpty) headers['X-Goog-User-Project'] = proj;
          } catch (_) {}
        } else {
          final key = ProviderManager._effectiveApiKey(cfg);
          if (key.isNotEmpty) {
            // Fallback: treat apiKey as a bearer token if user pasted one
            headers['Authorization'] = 'Bearer $key';
          }
        }
      }
      final res = await client.get(Uri.parse(url), headers: headers);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        final obj = jsonDecode(res.body) as Map<String, dynamic>;
        final arr = (obj['models'] as List?) ?? [];
        final out = <ModelInfo>[];
        for (final e in arr) {
          if (e is Map) {
            final name = (e['name'] as String?) ?? '';
            final id = name.contains('/') ? name.split('/').last : name;
            final displayName = (e['displayName'] as String?) ?? id;
            final methods = (e['supportedGenerationMethods'] as List?)?.map((m) => m.toString()).toSet() ?? {};
            if (!(methods.contains('generateContent') || methods.contains('embedContent'))) continue;
            out.add(ModelRegistry.infer(ModelInfo(
              id: id,
              displayName: displayName,
              type: methods.contains('generateContent') ? ModelType.chat : ModelType.embedding,
            )));
          }
        }
        return out;
      }
      return [];
    } finally {
      client.close();
    }
  }
}

class ProviderManager {
  static String _effectiveApiKey(ProviderConfig cfg) {
    try {
      if (cfg.multiKeyEnabled == true && (cfg.apiKeys?.isNotEmpty == true)) {
        final sel = ApiKeyManager().selectForProvider(cfg);
        if (sel.key != null) return sel.key!.key;
      }
    } catch (_) {}
    return cfg.apiKey;
  }
  // Per-model override helpers (duplicated logic from ChatApiService)
  static Map<String, dynamic> _modelOverride(ProviderConfig cfg, String modelId) {
    final ov = cfg.modelOverrides[modelId];
    if (ov is Map<String, dynamic>) return ov;
    return const <String, dynamic>{};
  }

  static Map<String, String> _customHeaders(ProviderConfig cfg, String modelId) {
    final ov = _modelOverride(cfg, modelId);
    final list = (ov['headers'] as List?) ?? const <dynamic>[];
    final out = <String, String>{};
    for (final e in list) {
      if (e is Map) {
        final name = (e['name'] ?? e['key'] ?? '').toString().trim();
        final value = (e['value'] ?? '').toString();
        if (name.isNotEmpty) out[name] = value;
      }
    }
    return out;
  }

  static dynamic _parseOverrideValue(String v) {
    final s = v.trim();
    if (s.isEmpty) return s;
    if (s == 'true') return true;
    if (s == 'false') return false;
    if (s == 'null') return null;
    final i = int.tryParse(s);
    if (i != null) return i;
    final d = double.tryParse(s);
    if (d != null) return d;
    if ((s.startsWith('{') && s.endsWith('}')) || (s.startsWith('[') && s.endsWith(']'))) {
      try { return jsonDecode(s); } catch (_) {}
    }
    return v;
  }

  static Map<String, dynamic> _customBody(ProviderConfig cfg, String modelId) {
    final ov = _modelOverride(cfg, modelId);
    final list = (ov['body'] as List?) ?? const <dynamic>[];
    final out = <String, dynamic>{};
    for (final e in list) {
      if (e is Map) {
        final key = (e['key'] ?? e['name'] ?? '').toString().trim();
        final val = (e['value'] ?? '').toString();
        if (key.isNotEmpty) out[key] = _parseOverrideValue(val);
      }
    }
    return out;
  }
  static BaseProvider forConfig(ProviderConfig cfg) {
    final kind = ProviderConfig.classify(cfg.id, explicitType: cfg.providerType);
    switch (kind) {
      case ProviderKind.google:
        return GoogleProvider();
      case ProviderKind.claude:
        return ClaudeProvider();
      case ProviderKind.openai:
        return OpenAIProvider();
    }
  }

  static Future<List<ModelInfo>> listModels(ProviderConfig cfg) {
    return forConfig(cfg).listModels(cfg);
  }

  static Future<void> testConnection(ProviderConfig cfg, String modelId) async {
    final kind = ProviderConfig.classify(cfg.id, explicitType: cfg.providerType);
    final client = _Http.clientFor(cfg);
    try {
      if (kind == ProviderKind.openai) {
        final base = cfg.baseUrl.endsWith('/') ? cfg.baseUrl.substring(0, cfg.baseUrl.length - 1) : cfg.baseUrl;
        final path = (cfg.useResponseApi == true) ? '/responses' : (cfg.chatPath ?? '/chat/completions');
        final url = Uri.parse('$base$path');
        final body = cfg.useResponseApi == true
            ? {
                'model': modelId,
                'input': [
                  {'role': 'user', 'content': 'hello'}
                ],
              }
            : {
                'model': modelId,
                'messages': [
                  {'role': 'user', 'content': 'hello'}
                ],
              };
        // Merge custom body overrides
        final extra = _customBody(cfg, modelId);
        if (extra.isNotEmpty) (body as Map<String, dynamic>).addAll(extra);
        // Merge custom headers overrides
        // SiliconFlow fallback key for built-in free models when no API key provided
        String apiKey = _effectiveApiKey(cfg);
        try {
          if ((cfg.id) == 'SiliconFlow') {
            final host = Uri.tryParse(cfg.baseUrl)?.host.toLowerCase() ?? '';
            if (host.contains('siliconflow') && apiKey.trim().isEmpty) {
              final m = modelId.toLowerCase();
              final allowed = m == 'thudm/glm-4-9b-0414' || m == 'qwen/qwen3-8b';
              final fb = siliconflowFallbackKey.trim();
              if (allowed && fb.isNotEmpty) apiKey = fb;
            }
          }
        } catch (_) {}
        final headers = <String, String>{
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        };
        headers.addAll(_customHeaders(cfg, modelId));
        final res = await client.post(url, headers: headers, body: jsonEncode(body));
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw HttpException('HTTP ${res.statusCode}: ${res.body}');
        }
        return;
      } else if (kind == ProviderKind.claude) {
        final base = cfg.baseUrl.endsWith('/') ? cfg.baseUrl.substring(0, cfg.baseUrl.length - 1) : cfg.baseUrl;
        final url = Uri.parse('$base/messages');
        final body = {
          'model': modelId,
          'max_tokens': 8,
          'messages': [
            {
              'role': 'user',
              'content': 'hello',
            }
          ]
        };
        final extra = _customBody(cfg, modelId);
        if (extra.isNotEmpty) (body as Map<String, dynamic>).addAll(extra);
        final headers = <String, String>{
          'x-api-key': cfg.apiKey,
          'anthropic-version': ClaudeProvider.anthropicVersion,
          'Content-Type': 'application/json',
        };
        headers.addAll(_customHeaders(cfg, modelId));
        final res = await client.post(url, headers: headers, body: jsonEncode(body));
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw HttpException('HTTP ${res.statusCode}: ${res.body}');
        }
        return;
      } else if (kind == ProviderKind.google) {
        // Generative Language API (default) or Vertex AI when vertexAI == true
        String url;
        if (cfg.vertexAI == true && (cfg.location?.isNotEmpty == true) && (cfg.projectId?.isNotEmpty == true)) {
          final loc = cfg.location!;
          final proj = cfg.projectId!;
          url = 'https://aiplatform.googleapis.com/v1/projects/$proj/locations/$loc/publishers/google/models/$modelId:generateContent';
        } else {
          final base = cfg.baseUrl.endsWith('/') ? cfg.baseUrl.substring(0, cfg.baseUrl.length - 1) : cfg.baseUrl;
          url = '$base/models/$modelId:generateContent';
          if (cfg.apiKey.isNotEmpty) {
            url = '$url?key=${Uri.encodeQueryComponent(cfg.apiKey)}';
          }
        }
        // Determine if model outputs images (override wins; otherwise inference)
        bool wantsImageOutput = false;
        final ov = _modelOverride(cfg, modelId);
        if (ov['output'] is List) {
          final outList = (ov['output'] as List).map((e) => e.toString().toLowerCase()).toList();
          wantsImageOutput = outList.contains('image');
        } else {
          wantsImageOutput = ModelRegistry.infer(ModelInfo(id: modelId, displayName: modelId)).output.contains(Modality.image);
        }
        final body = {
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': 'hello'}
              ]
            }
          ],
          if (wantsImageOutput)
            'generationConfig': {
              'responseModalities': ['TEXT', 'IMAGE'],
            },
        };
        final headers = <String, String>{'Content-Type': 'application/json'};
        if (cfg.vertexAI == true) {
          final jsonStr = (cfg.serviceAccountJson ?? '').trim();
          if (jsonStr.isNotEmpty) {
            try {
              final token = await GoogleServiceAccountAuth.getAccessTokenFromJson(jsonStr);
              headers['Authorization'] = 'Bearer $token';
            } catch (_) {}
          } else if (cfg.apiKey.isNotEmpty) {
            headers['Authorization'] = 'Bearer ${cfg.apiKey}';
          }
        }
        headers.addAll(_customHeaders(cfg, modelId));
        final extra = _customBody(cfg, modelId);
        if (extra.isNotEmpty) (body as Map<String, dynamic>).addAll(extra);
        final res = await client.post(Uri.parse(url), headers: headers, body: jsonEncode(body));
        if (res.statusCode < 200 || res.statusCode >= 300) {
          throw HttpException('HTTP ${res.statusCode}: ${res.body}');
        }
        return;
      }
    } finally {
      client.close();
    }
  }
}
