import 'package:flutter_test/flutter_test.dart';
import 'package:minime_core/core/services/stats/stats_aggregator.dart';

void main() {
  final now = DateTime(2026, 9, 15);

  group('StatsWindow.contains 边界', () {
    test('含首尾、不含首尾之外', () {
      final w = StatsWindow(start: DateTime(2026, 9, 1), end: DateTime(2026, 9, 10));
      expect(w.contains(DateTime(2026, 9, 1)), isTrue); // 起点
      expect(w.contains(DateTime(2026, 9, 10)), isTrue); // 终点
      expect(w.contains(DateTime(2026, 9, 5)), isTrue); // 中间
      expect(w.contains(DateTime(2026, 8, 31)), isFalse); // 起点前一天
      expect(w.contains(DateTime(2026, 9, 11)), isFalse); // 终点后一天
    });

    test('无起止的窗口（all）包含任意日', () {
      const w = StatsWindow();
      expect(w.contains(DateTime(2020, 1, 1)), isTrue);
      expect(w.contains(DateTime(2030, 12, 31)), isTrue);
    });
  });

  group('StatsRangeWindow.windowFor 各区间起止', () {
    test('all → 无限窗口', () {
      final w = StatsRange.all.windowFor(now);
      expect(w.start, isNull);
      expect(w.end, isNull);
    });

    test('last30 → [今天-29, 今天]', () {
      final w = StatsRange.last30.windowFor(now);
      expect(w.start, DateTime(2026, 8, 17));
      expect(w.end, DateTime(2026, 9, 15));
    });

    test('lastMonth → [上月1日, 上月末]', () {
      final w = StatsRange.lastMonth.windowFor(now);
      expect(w.start, DateTime(2026, 8, 1));
      expect(w.end, DateTime(2026, 8, 31));
    });

    test('lastQuarter → [3个月前1日, 上月末]', () {
      final w = StatsRange.lastQuarter.windowFor(now);
      expect(w.start, DateTime(2026, 6, 1));
      expect(w.end, DateTime(2026, 8, 31));
    });
  });
}
