import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';

// ─────────────────────────────────────────────────────────────
// 统计页文案入口
//
// `AppLocalizations.of(context)` 返回的是可空类型，旧代码里到处散着
// `l10n?.xxx ?? '中文兜底'`，兜底值被复制了 N 份，改一处漏一处。
// 这里集中收口：默认值只写一遍，页面代码统一用 `StatsL10n.of(context)`。
// ─────────────────────────────────────────────────────────────

/// 统计页文案包装器。
class StatsL10n {
  final AppLocalizations? _l;

  const StatsL10n._(this._l);

  /// 从 context 取当前语言的统计文案。
  static StatsL10n of(BuildContext context) =>
      StatsL10n._(AppLocalizations.of(context));

  // ---------- 区间 ----------
  String get rangeAll => _l?.statsRangeAll ?? '全部';
  String get rangeLast30 => _l?.statsRangeLast30 ?? '最近30天';
  String get rangeLastMonth => _l?.statsRangeLastMonth ?? '上个月';
  String get rangeLastQuarter => _l?.statsRangeLastQuarter ?? '上个季度';

  // ---------- 区块标题 ----------
  String get sectionHeatmap => _l?.statsSectionHeatmap ?? '聊天热力图';
  String get sectionTrend => _l?.statsSectionTrend ?? '用量趋势';
  String get sectionOverview => _l?.statsSectionOverview ?? '总览';

  // ---------- 总览 ----------
  String get overviewConversations =>
      _l?.statsOverviewConversations ?? '总对话数';
  String get overviewMessages => _l?.statsOverviewMessages ?? '总消息数';
  String get overviewPromptTokens =>
      _l?.statsOverviewPromptTokens ?? '输入 Tokens';
  String get overviewCompletionTokens =>
      _l?.statsOverviewCompletionTokens ?? '输出 Tokens';
  String get overviewCachedTokens =>
      _l?.statsOverviewCachedTokens ?? '缓存 Tokens';
  String get overviewLaunchCount =>
      _l?.statsOverviewLaunchCount ?? '应用启动次数';

  // ---------- 表 ----------
  String get modelUsage => _l?.statsModelUsage ?? '模型使用率';
  String get assistantUsage => _l?.statsAssistantUsage ?? '助手使用率';
  String get topicUsage => _l?.statsTopicUsage ?? '话题内容量';

  String get colModel => _l?.statsColModel ?? '模型';
  String get colMessages => _l?.statsColMessages ?? '消息数';
  String get colAssistant => _l?.statsColAssistant ?? '助手';
  String get colTopicCount => _l?.statsColTopicCount ?? '话题数';
  String get colTopic => _l?.statsColTopic ?? '话题';

  // ---------- 占位 ----------
  String get unknownModel => _l?.statsUnknownModel ?? '未知';
  String get globalAssistant => _l?.statsGlobalAssistant ?? '全局';
  String get unnamedTopic => _l?.statsUnnamedTopic ?? '（未命名话题）';
  String get noData => _l?.statsNoData ?? '暂无数据';
  String get noActivity => _l?.statsNoActivity ?? '无记录';

  // ---------- 热力图 ----------
  String get legendLess => _l?.statsLegendLess ?? '少';
  String get legendMore => _l?.statsLegendMore ?? '多';

  String heatmapDayDetail(String date, int count) =>
      _l?.statsHeatmapDayDetail(date, count) ?? '$date · $count 条消息';

  // ---------- 趋势 ----------
  String get tokensUnit => _l?.statsTokensUnit ?? 'tokens';
  String get granularityDay => _l?.statsGranularityDay ?? '按天';
  String get granularityMonth => _l?.statsGranularityMonth ?? '按月';

  String trendTotal(String value) =>
      _l?.statsTrendTotal(value) ?? '合计 $value';

  String messageCount(int count) =>
      _l?.statsMessageCount(count) ?? '$count 条';

  String topicCount(int count) => _l?.statsTopicCount(count) ?? '$count 个话题';
}
