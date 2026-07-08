import 'package:flutter_test/flutter_test.dart';
import 'package:love_story/features/points/cycle_helper.dart';

void main() {
  group('CycleHelper.periodForView', () {
    final at = DateTime(2025, 3, 15, 12, 0, 0);

    test('month: first day to next month first day', () {
      final (start, end) = CycleHelper.periodForView(PointsViewMode.month, at);
      expect(start, DateTime(2025, 3, 1));
      expect(end, DateTime(2025, 4, 1));
    });

    test('year: Jan 1 to next year Jan 1', () {
      final (start, end) = CycleHelper.periodForView(PointsViewMode.year, at);
      expect(start, DateTime(2025, 1, 1));
      expect(end, DateTime(2026, 1, 1));
    });

    test('all: fixed range', () {
      final (start, end) = CycleHelper.periodForView(PointsViewMode.all, at);
      expect(start, DateTime(2000, 1, 1));
      expect(end, DateTime(2100, 1, 1));
    });
  });

  group('CycleHelper.viewModeLabel', () {
    final at = DateTime(2025, 3, 15);

    test('month', () {
      expect(
        CycleHelper.viewModeLabel(PointsViewMode.month, at),
        '2025年3月',
      );
    });

    test('year', () {
      expect(
        CycleHelper.viewModeLabel(PointsViewMode.year, at),
        '2025年',
      );
    });

    test('all', () {
      expect(
        CycleHelper.viewModeLabel(PointsViewMode.all, at),
        '历史所有',
      );
    });
  });
}
