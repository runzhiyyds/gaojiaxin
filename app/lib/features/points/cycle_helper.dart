import 'package:love_story/features/points/point_item_model.dart';

/// 积分 Tab 的统计视图：月 / 年 / 历史所有
enum PointsViewMode {
  month,
  year,
  all,
}

class CycleHelper {
  /// 当前周期起止（日/周/月/年/历史所有，与 TAB2 及项目统计周期对齐）
  static (DateTime start, DateTime end) periodFor(CycleType type, DateTime at) {
    final local = at.toLocal();
    switch (type) {
      case CycleType.day:
        final start = DateTime(local.year, local.month, local.day);
        return (start, start.add(const Duration(days: 1)));
      case CycleType.week:
        final weekday = local.weekday;
        final monday = local.subtract(Duration(days: weekday - 1));
        final start = DateTime(monday.year, monday.month, monday.day);
        return (start, start.add(const Duration(days: 7)));
      case CycleType.month:
        final start = DateTime(local.year, local.month, 1);
        return (start, DateTime(local.year, local.month + 1, 1));
      case CycleType.year:
        final start = DateTime(local.year, 1, 1);
        return (start, DateTime(local.year + 1, 1, 1));
      case CycleType.all:
        return (DateTime(2000, 1, 1), DateTime(2100, 1, 1));
    }
  }

  static String periodLabel(CycleType type, DateTime at) {
    final (start, end) = periodFor(type, at);
    switch (type) {
      case CycleType.day:
        return '${start.month}月${start.day}日';
      case CycleType.week:
        return '${start.month}/${start.day} - ${end.month}/${end.day}';
      case CycleType.month:
        return '${start.year}年${start.month}月';
      case CycleType.year:
        return '${start.year}年';
      case CycleType.all:
        return '历史所有';
    }
  }

  /// 积分页「月 / 年 / 历史所有」对应的起止时间
  static (DateTime start, DateTime end) periodForView(PointsViewMode mode, DateTime at) {
    final local = at.toLocal();
    switch (mode) {
      case PointsViewMode.month:
        return (
          DateTime(local.year, local.month, 1),
          DateTime(local.year, local.month + 1, 1),
        );
      case PointsViewMode.year:
        return (
          DateTime(local.year, 1, 1),
          DateTime(local.year + 1, 1, 1),
        );
      case PointsViewMode.all:
        return (DateTime(2000, 1, 1), DateTime(2100, 1, 1));
    }
  }

  /// 积分页 Tab 的标题
  static String viewModeLabel(PointsViewMode mode, DateTime at) {
    switch (mode) {
      case PointsViewMode.month:
        return '${at.year}年${at.month}月';
      case PointsViewMode.year:
        return '${at.year}年';
      case PointsViewMode.all:
        return '历史所有';
    }
  }
}
