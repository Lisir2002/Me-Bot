import 'dart:async';
import 'package:flutter/material.dart';
import '../data/conversation_data_source.dart';
import '../models/conversation_style.dart';
import '../models/style_settings.dart';

/// 样式渲染器抽象接口 —— 每种样式实现此接口
///
/// 渲染器不持有任何数据，只持有 ConversationDataSource 引用。
/// 所有数据必须通过 dataSource 获取，禁止直接访问 Hive/Provider/数据库/API。
abstract class StyleRenderer {
  /// 数据源引用（由 StyleSwitcher 统一注入）
  @protected
  late final ConversationDataSource dataSource;

  /// UI 状态引用（由 StyleSwitcher 统一注入）
  @protected
  late final ConversationUIState uiState;

  /// UI 状态更新回调
  @protected
  late final void Function(ConversationUIState) onUIStateChanged;

  /// 此渲染器对应的样式
  ConversationStyle get style;

  /// 初始化时注入 DataSource（由 StyleSwitcher 统一注入）
  void attach(
    ConversationDataSource source,
    ConversationUIState initialUiState,
    void Function(ConversationUIState) uiStateCallback,
  ) {
    dataSource = source;
    uiState = initialUiState;
    onUIStateChanged = uiStateCallback;
    onAttach();
  }

  /// 样式被激活时调用（可订阅流）
  @protected
  void onAttach();

  /// 样式被停用时调用（必须取消所有订阅）
  void onDetach();

  /// 构建 UI —— 只能从 dataSource 读取数据
  Widget build(BuildContext context);

  /// 更新 UI 状态（便捷方法）
  @protected
  void updateUIState(ConversationUIState newState) {
    uiState = newState;
    onUIStateChanged(newState);
  }
}

/// 基础样式渲染器 —— 提供通用的 StreamBuilder 模式
///
/// 所有样式渲染器可以继承此类，获得自动订阅 messageStream 和
/// stateStream 的能力，减少重复代码。
abstract class BaseStyleRenderer extends StyleRenderer {
  /// 流订阅列表（onDetach 时自动取消）
  final List<StreamSubscription> _subscriptions = [];

  @protected
  void addSubscription(StreamSubscription sub) {
    _subscriptions.add(sub);
  }

  @override
  void onAttach() {
    // 子类可覆盖以添加流订阅
  }

  @override
  void onDetach() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }
}
