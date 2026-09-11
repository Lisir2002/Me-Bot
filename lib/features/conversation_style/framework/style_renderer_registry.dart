import '../models/conversation_style.dart';
import 'style_renderer.dart';

/// 样式渲染器工厂函数类型
typedef StyleRendererFactory = StyleRenderer Function();

/// 样式渲染器注册表 —— 注册/查找渲染器，支持 lazy load
///
/// 所有样式渲染器在此注册，通过 ConversationStyle 查找。
/// 支持 lazy load：首次访问时才实例化渲染器，减少首屏体积。
class StyleRendererRegistry {
  final Map<ConversationStyle, StyleRendererFactory> _factories = {};
  final Map<ConversationStyle, StyleRenderer> _instances = {};

  /// 注册一个样式渲染器工厂
  void register(ConversationStyle style, StyleRendererFactory factory) {
    _factories[style] = factory;
  }

  /// 批量注册
  void registerAll(Map<ConversationStyle, StyleRendererFactory> factories) {
    _factories.addAll(factories);
  }

  /// 获取样式渲染器（lazy load：首次访问时实例化）
  StyleRenderer get(ConversationStyle style) {
    if (!_instances.containsKey(style)) {
      final factory = _factories[style];
      if (factory == null) {
        throw StateError('StyleRenderer not registered: $style');
      }
      _instances[style] = factory();
    }
    return _instances[style]!;
  }

  /// 检查样式是否已注册
  bool isRegistered(ConversationStyle style) =>
      _factories.containsKey(style);

  /// 获取所有已注册的样式
  List<ConversationStyle> get registeredStyles => _factories.keys.toList();

  /// 清除指定样式的缓存实例（用于热重载或内存清理）
  void invalidate(ConversationStyle style) {
    _instances.remove(style);
  }

  /// 清除所有缓存实例
  void invalidateAll() {
    _instances.clear();
  }

  /// 释放所有渲染器资源
  void disposeAll() {
    for (final renderer in _instances.values) {
      renderer.onDetach();
    }
    _instances.clear();
  }
}
