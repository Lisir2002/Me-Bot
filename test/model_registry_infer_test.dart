import 'package:flutter_test/flutter_test.dart';
import 'package:minime_core/core/providers/model_provider.dart';

void main() {
  Set<ModelAbility> ab(String id) =>
      ModelRegistry.infer(ModelInfo(id: id, displayName: id)).abilities.toSet();
  bool has(Set<ModelAbility> s, ModelAbility a) => s.contains(a);

  test('tool calling inferred for major chat models', () {
    const ids = [
      'gpt-4o', 'gpt-4.1', 'gpt-4.1-mini', 'gpt-4o-mini', 'o3-mini', 'gpt-5',
      'claude-sonnet-4-20250514', 'claude-3-7-sonnet', 'claude-3.5-sonnet',
      'gemini-2.5-pro', 'gemini-2.0-flash', 'deepseek-chat', 'deepseek-reasoner',
      'deepseek-ai/DeepSeek-R1', 'qwen2.5-72b-instruct', 'qwen3-8b',
      'Qwen/Qwen3-8B', 'qwen-turbo', 'moonshot-v1-8k', 'kimi-k2-turbo-preview',
      'glm-4-air', 'glm-4.5', 'doubao-seed-1.6-250615', 'grok-4-fast',
      'mistral-large-latest', 'llama-3.3-70b-versatile', 'intern-s1',
      'step-3-mini', 'hunyuan-large', 'ernie-4.5', 'phi-4-mini-instruct',
      'command-r-plus', 'spark-v4.0', 'openrouter-openai/gpt-4o',
    ];
    for (final id in ids) {
      expect(has(ab(id), ModelAbility.tool), isTrue, reason: 'tool: $id');
    }
  });

  test('reasoning inferred for thinking models', () {
    const ids = [
      'o3-mini', 'gpt-5', 'claude-sonnet-4-20250514', 'claude-3-7-sonnet',
      'gemini-2.5-pro', 'deepseek-reasoner', 'deepseek-ai/DeepSeek-R1',
      'qwen3-8b', 'Qwen/Qwen3-8B', 'qwq-32b', 'kimi-k2-thinking',
      'glm-4.5', 'glm-z1-air', 'doubao-seed-1.6-250615', 'grok-4-reasoner',
      'intern-s1', 'step-3', 'hunyuan-t1', 'ernie-x1', 'minimax-reasoner',
    ];
    for (final id in ids) {
      expect(has(ab(id), ModelAbility.reasoning), isTrue, reason: 'reasoning: $id');
    }
  });

  test('vision inferred for multimodal models', () {
    const ids = [
      'gpt-4o', 'gpt-4.1', 'claude-sonnet-4-20250514', 'gemini-2.5-pro',
      'qwen2.5-vl-72b-instruct', 'qwen3-vl-plus', 'glm-4.5v', 'glm-4v-plus',
      'doubao-1.6-vl-pro-256k', 'moonshot-v1-8k-vision-preview', 'kimi-k2.5',
      'grok-4', 'pixtral-large-latest', 'llama-3.2-11b-vision-instruct',
      'internvl2-8b', 'step-1v', 'yi-vl-plus', 'hunyuan-vision',
    ];
    for (final id in ids) {
      final info = ModelRegistry.infer(ModelInfo(id: id, displayName: id));
      expect(info.input.contains(Modality.image), isTrue, reason: 'vision: $id');
    }
  });

  test('no tool for image/embedding/legacy models', () {
    const ids = [
      'gpt-image-1', 'dall-e-3', 'text-embedding-3-large', 'text-embedding-ada-002',
      'bge-m3', 'gpt-3.5-turbo-instruct', 'text-davinci-003',
      'black-forest-labs/flux', 'stable-diffusion-xl-base-1.0',
      'claude-2.1',
    ];
    for (final id in ids) {
      expect(has(ab(id), ModelAbility.tool), isFalse, reason: 'no-tool: $id');
    }
  });

  test('unknown chat model defaults to tool support', () {
    expect(has(ab('some-custom-chat-model'), ModelAbility.tool), isTrue);
    expect(has(ab('custom-router/mega-model-v7'), ModelAbility.tool), isTrue);
    expect(has(ab('my-instruct-model'), ModelAbility.tool), isFalse);
  });
}
