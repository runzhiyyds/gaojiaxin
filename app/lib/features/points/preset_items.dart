import 'package:love_story/features/points/point_item_model.dart';
import 'package:love_story/features/points/love_dimension.dart';

class PresetItemDef {
  const PresetItemDef({
    required this.name,
    required this.iconName,
    this.pointsPerUnit = 1,
    this.cycleType = CycleType.month,
    this.loveDimension,
  });

  final String name;
  final String iconName;
  final int pointsPerUnit;
  final CycleType cycleType;
  final LoveDimension? loveDimension;
}

const List<PresetItemDef> presetItemDefs = [
  // 七个爱的维度型心意标签
  PresetItemDef(
    name: '关心',
    iconName: 'favorite',
    pointsPerUnit: 10,
    loveDimension: LoveDimension.care,
  ),
  PresetItemDef(
    name: '陪伴',
    iconName: 'schedule',
    pointsPerUnit: 10,
    loveDimension: LoveDimension.companionship,
  ),
  PresetItemDef(
    name: '理解',
    iconName: 'psychology',
    pointsPerUnit: 10,
    loveDimension: LoveDimension.understanding,
  ),
  PresetItemDef(
    name: '成长',
    iconName: 'trending_up',
    pointsPerUnit: 10,
    loveDimension: LoveDimension.growth,
  ),
  PresetItemDef(
    name: '责任',
    iconName: 'task_alt',
    pointsPerUnit: 10,
    loveDimension: LoveDimension.responsibility,
  ),
  PresetItemDef(
    name: '仪式感',
    iconName: 'celebration',
    pointsPerUnit: 10,
    loveDimension: LoveDimension.ritual,
  ),
  PresetItemDef(
    name: '激情',
    iconName: 'local_fire_department',
    pointsPerUnit: 10,
    loveDimension: LoveDimension.passion,
  ),

  // 原始两项：日常 & 纪念过去
  PresetItemDef(
    name: '日常',
    iconName: 'home',
    pointsPerUnit: 10,
    loveDimension: null,
  ),
  PresetItemDef(
    name: '纪念过去',
    iconName: 'photo_album',
    pointsPerUnit: 10,
    loveDimension: null,
  ),
];
