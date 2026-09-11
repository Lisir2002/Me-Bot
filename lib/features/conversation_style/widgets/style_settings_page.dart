// ignore_for_file: hardcoded_ui_string
import 'package:flutter/material.dart';
import '../data/style_settings_service.dart';
import '../framework/style_resolver.dart';
import '../models/conversation_state.dart';
import '../models/conversation_style.dart';

/// 正式对话样式设置页
///
/// - 自动/手动模式切换
/// - 手动模式：9 种样式预览网格（编号 / 名称 / 描述 / 选中态）
/// - 选中即持久化到 StyleSettingsService（全局默认）
/// - 自动模式下展示"为什么推荐这个样式"的说明
class StyleSettingsPage extends StatefulWidget {
  /// 外部传入的服务实例（可选）；不传则页面自建并加载
  final StyleSettingsService? service;

  const StyleSettingsPage({super.key, this.service});

  @override
  State<StyleSettingsPage> createState() => _StyleSettingsPageState();
}

class _StyleSettingsPageState extends State<StyleSettingsPage> {
  late final StyleSettingsService _service;
  bool _ownedService = false;

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? StyleSettingsService();
    _ownedService = widget.service == null;
    _service.addListener(_onChanged);
    if (!_service.isLoaded) {
      _service.load();
    }
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    if (_ownedService) _service.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = _service.settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('对话样式'),
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // 自动模式开关
          Card(
            elevation: 0,
            color: theme.colorScheme.surfaceContainerHighest,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: SwitchListTile(
              title: const Text('自动选择样式'),
              subtitle: const Text('根据对话内容特征自动推荐最合适的样式'),
              value: settings.autoModeEnabled,
              activeThumbColor: theme.colorScheme.primary,
              onChanged: (v) => _service.setAutoMode(v),
            ),
          ),
          const SizedBox(height: 16),

          // 自动模式：说明推荐理由
          if (settings.autoModeEnabled) ...[
            Builder(builder: (_) {
              final resolver = StyleResolver(stats: _service.usageStats);
              final recommended = resolver.resolve(
                  settings: settings, intent: const ConversationIntent());
              return _AutoHint(
                recommended: recommended,
                explain: resolver.getRecommendationReason(
                    const ConversationIntent(), settings),
              );
            }),
            const SizedBox(height: 12),
            _UsageStatsCard(service: _service),
          ] else ...[
            // 手动模式：当前选中 + 9 种样式网格
            Row(
              children: [
                Text('选择默认样式',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                Text(
                  '当前：${StyleMetaRegistry.get(settings.globalStyle).displayName}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                childAspectRatio: 0.85,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: StyleMetaRegistry.concreteStyles.length,
              itemBuilder: (context, index) {
                final meta = StyleMetaRegistry.concreteStyles[index];
                final selected = meta.style == settings.globalStyle;
                return _StyleCard(
                  meta: meta,
                  selected: selected,
                  onTap: () => _service.setGlobalStyle(meta.style),
                );
              },
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline,
                      size: 18, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      '也可以在对话页右上角随时切换，切换仅对当前会话生效。',
                      style: TextStyle(fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 自动模式推荐提示
class _AutoHint extends StatelessWidget {
  final ConversationStyle recommended;
  final String explain;

  const _AutoHint({required this.recommended, required this.explain});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = StyleMetaRegistry.get(recommended);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome,
                  size: 20, color: theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text('推荐：${meta.number} ${meta.displayName}',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 8),
          Text(explain,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              )),
          const SizedBox(height: 8),
          Text(meta.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
        ],
      ),
    );
  }
}

/// 样式预览卡片（与对话页底部 Sheet 中的卡片保持一致风格）
class _StyleCard extends StatelessWidget {
  final StyleMeta meta;
  final bool selected;
  final VoidCallback onTap;

  const _StyleCard({
    required this.meta,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
              : theme.colorScheme.surfaceContainerHighest,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    meta.number,
                    style: theme.textTheme.labelSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.check_circle,
                      size: 14, color: theme.colorScheme.primary),
                ],
              ],
            ),
            const SizedBox(height: 6),
            Text(
              meta.displayName,
              style: theme.textTheme.labelLarge
                  ?.copyWith(fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Text(
                meta.description,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 用户样式使用统计卡：最常用样式占比 + 重置学习数据
class _UsageStatsCard extends StatelessWidget {
  final StyleSettingsService service;
  const _UsageStatsCard({required this.service});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = service.usageStats;
    final fav = stats.mostUsed;
    final pct = fav == null ? 0.0 : stats.usagePercent(fav);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.insights, size: 18, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              fav == null
                  ? '暂无使用数据，切换行为将用于优化推荐'
                  : '你最常使用：${StyleMetaRegistry.get(fav).displayName}'
                      '（${(pct * 100).round()}%）',
              style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
            ),
          ),
          TextButton(
            onPressed: () => service.resetUsageStats(),
            child: const Text('重置学习数据'),
          ),
        ],
      ),
    );
  }
}
