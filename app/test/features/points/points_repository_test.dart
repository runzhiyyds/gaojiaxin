import 'package:flutter_test/flutter_test.dart';
import 'package:love_story/features/points/point_item_model.dart';
import 'package:love_story/features/points/point_record_model.dart';
import 'package:love_story/features/points/points_repository.dart';

void main() {
  group('IPointsRepository', () {
    test('FakePointsRepository getRecords returns given list', () async {
      final repo = FakePointsRepository(
        records: [
          PointRecordModel(
            id: 'r1',
            coupleSpaceId: 's1',
            userId: 'u1',
            pointItemId: 'i1',
            points: 10,
            recordAt: DateTime(2025, 1, 1),
          ),
        ],
      );
      final list = await repo.getRecords(
        coupleSpaceId: 's1',
        limit: 10,
      );
      expect(list.length, 1);
      expect(list.first.points, 10);
      expect(list.first.id, 'r1');
    });

    test('FakePointsRepository getItems returns given list', () async {
      final repo = FakePointsRepository(
        items: [
          PointItemModel(
            id: 'i1',
            coupleSpaceId: 's1',
            name: '测试',
            iconName: 'star',
            pointsPerUnit: 1,
            cycleType: CycleType.month,
            sortOrder: 0,
            isPreset: false,
            isEnabled: true,
            isDefault: false,
          ),
        ],
      );
      final list = await repo.getItems('s1');
      expect(list.length, 1);
      expect(list.first.name, '测试');
    });
  });
}

/// 用于单测的假实现，返回预设数据。
class FakePointsRepository implements IPointsRepository {
  FakePointsRepository({
    List<PointItemModel>? items,
    List<PointRecordModel>? records,
  })  : _items = items ?? [],
        _records = records ?? [];

  final List<PointItemModel> _items;
  final List<PointRecordModel> _records;

  @override
  Future<List<PointItemModel>> getItems(String coupleSpaceId) async {
    return _items
        .where((e) => e.coupleSpaceId == coupleSpaceId)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  @override
  Future<List<PointRecordModel>> getRecords({
    required String coupleSpaceId,
    DateTime? from,
    DateTime? to,
    String? pointItemId,
    int limit = 50,
  }) async {
    var list = _records.where((e) => e.coupleSpaceId == coupleSpaceId);
    if (pointItemId != null) {
      list = list.where((e) => e.pointItemId == pointItemId);
    }
    if (from != null) {
      list = list.where((e) => !e.recordAt.isBefore(from));
    }
    if (to != null) {
      list = list.where((e) => !e.recordAt.isAfter(to));
    }
    return list.take(limit).toList();
  }

  @override
  void invalidateForSpace(String coupleSpaceId) {}
}
