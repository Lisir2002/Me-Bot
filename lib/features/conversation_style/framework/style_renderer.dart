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

/// 智能滚动控制器 —— 封装"是否应自动滚到底部"的判断
///
/// - 用户停留在距底部 [nearBottomThreshold] 以内时视为"在底部"，新消息自动跟随
/// - 用户上翻超过阈值时暂停自动滚动，并通过 [onUserScrolledAway] 通知显示跳转按钮
/// - 不持有任何消息数据，只管滚动位置
class SmartScrollController extends ScrollController {
  /// 距底部多少 px 以内算"在底部"
  final double nearBottomThreshold;

  /// 用户上翻离开底部时回调（用于显示"跳转到底部"按钮）
  void Function(bool away)? onUserScrolledAway;

  bool _isNearBottom = true;

  /// 当前是否应自动滚动到底部
  bool get shouldAutoScroll => _isNearBottom;

  SmartScrollController({
    this.nearBottomThreshold = 100.0,
  });

  @override
  void addListener(listener) {
    super.addListener(listener);
    // 内部监听：更新"是否在底部"
    void inner() {
      final wasAway = !_isNearBottom;
      _isNearBottom = _computeNearBottom();
      final nowAway = !_isNearBottom;
      if (wasAway != nowAway) {
        onUserScrolledAway?.call(nowAway);
      }
    }

    super.addListener(inner);
  }

  bool _computeNearBottom() {
    if (!hasClients) return true;
    final pos = position;
    if (!pos.hasContentDimensions) return true;
    final remaining = pos.maxScrollExtent - pos.pixels;
    return remaining <= nearBottomThreshold;
  }

  /// 平滑滚动到底部（仅当用户在底部附近时才跟随）
  void smartJumpToBottom() {
    if (!hasClients) return;
    animateTo(
      position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }
}
