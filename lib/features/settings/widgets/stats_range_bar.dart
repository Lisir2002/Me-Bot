import 'package:flutter/material.dart';

import '../../../core/services/stats/stats_aggregator.dart';
import '../../../shared/widgets/ios_tactile.dart';
import '../../../theme/design_tokens.dart';
import 'stats_l10n.dart';

// ─────────────────────────────────────────────────────────────
// 区间筛选条
//
// 旧实现是裸 GestureDetector + AnimatedContainer：没有按压反馈、
// 没有语义标签、选中与否只差一个背景色（对比度极低）。
// 这里换成带触感与缩放反馈的胶囊，并把文案交给 l10n。
// ─────────────────────────────────────────────────────────────

/// 横向可滚动的时间区间选择条。
class StatsRangeBar extends StatelessWidget {
  final StatsRange value;
  final ValueChanged<StatsRange> onChanged;

  const StatsRangeBar({
    super.key,
    required this.value,
    required this.onChanged,
  });

  static String _label(StatsL10n t, StatsRange r) => switch (r) {
        StatsRange.all => t.rangeAll,
        StatsRange.last30 => t.rangeLast30,
        StatsRange.lastMonth => t.rangeLastMonth,
        StatsRange.lastQuarter => t.rangeLastQuarter,
      };

  @override
  Widget build(BuildContext context) {
    final t = StatsL10n.of(context);
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        itemCount: StatsRange.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppGap.xs),
        itemBuilder: (context, i) {
          final r = StatsRange.values[i];
          final selected = r == value;
          return IosCardPress(
            onTap: () => onChanged(r),
            pressedScale: 0.96,
            borderRadius: BorderRadius.circular(20),
            baseColor: selected ? cs.primary : cs.surfaceContainerLow,
            child: SizedBox(
              height: 40,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Text(
                    _label(t, r),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? cs.onPrimary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
