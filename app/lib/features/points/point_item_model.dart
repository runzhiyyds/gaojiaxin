/// 统计周期：与 TAB2 积分视图一致为月/年/历史所有；保留 day/week 兼容旧数据
import 'package:love_story/features/points/love_dimension.dart';
enum CycleType {
  day,
  week,
  month,
  year,
  all;

  static CycleType fromString(String? v) {
    switch (v?.toLowerCase()) {
      case 'week':
        return CycleType.week;
      case 'month':
        return CycleType.month;
      case 'year':
        return CycleType.year;
      case 'all':
        return CycleType.all;
      default:
        return CycleType.day;
    }
  }

  String get value => name;
}

class PointItemModel {
  PointItemModel({
    required this.id,
    required this.coupleSpaceId,
    required this.name,
    required this.iconName,
    required this.pointsPerUnit,
    required this.cycleType,
    required this.sortOrder,
    required this.isPreset,
    required this.isEnabled,
    this.isDefault = false,
    this.loveDimension,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String coupleSpaceId;
  final String name;
  final String iconName;
  final int pointsPerUnit;
  final CycleType cycleType;
  final int sortOrder;
  final bool isPreset;
  final bool isEnabled;
  final bool isDefault;
  final DateTime createdAt;
  final DateTime updatedAt;
  final LoveDimension? loveDimension;

  factory PointItemModel.fromJson(Map<String, dynamic> json) {
    return PointItemModel(
      id: json['id'] as String,
      coupleSpaceId: json['couple_space_id'] as String,
      name: json['name'] as String,
      iconName: json['icon_name'] as String? ?? 'star',
      pointsPerUnit: (json['points_per_unit'] as num?)?.toInt() ?? 1,
      cycleType: CycleType.fromString(json['cycle_type'] as String?),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isPreset: json['is_preset'] as bool? ?? false,
      isEnabled: json['is_enabled'] as bool? ?? true,
      isDefault: json['is_default'] as bool? ?? false,
      loveDimension: LoveDimension.fromDb(json['love_dimension'] as String?),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'couple_space_id': coupleSpaceId,
        'name': name,
        'icon_name': iconName,
        'points_per_unit': pointsPerUnit,
        'cycle_type': cycleType.value,
        'sort_order': sortOrder,
        'is_preset': isPreset,
        'is_enabled': isEnabled,
        'is_default': isDefault,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
        if (loveDimension != null) 'love_dimension': loveDimension!.dbValue,
      };
}
