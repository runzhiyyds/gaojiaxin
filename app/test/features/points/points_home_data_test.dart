import 'package:flutter_test/flutter_test.dart';
import 'package:love_story/features/points/points_repository.dart';

void main() {
  test('RPC home payload parses identities, records and totals', () {
    final data = PointsHomeData.fromJson({
      'couple_space_id': 'space-1',
      'current_user_id': 'user-a',
      'partner_user_id': 'user-b',
      'items': [
        {
          'id': 'item-1',
          'couple_space_id': 'space-1',
          'name': '关心',
          'icon_name': 'favorite',
          'points_per_unit': 10,
          'cycle_type': 'month',
          'sort_order': 1,
          'is_preset': true,
          'is_enabled': true,
          'is_default': false,
          'created_at': '2026-10-31T00:00:00Z',
          'updated_at': '2026-10-31T00:00:00Z',
        },
      ],
      'records': [
        {
          'id': 'record-1',
          'couple_space_id': 'space-1',
          'user_id': 'user-a',
          'point_item_id': 'item-1',
          'points': 12,
          'row_version': 7,
          'record_at': '2026-10-31T00:00:00Z',
          'created_at': '2026-10-31T00:00:00Z',
        },
      ],
      'my_total_earned': 123,
      'partner_total_earned': 456,
      'my_total_spent': 20,
      'partner_total_spent': 30,
      'my_locked': 40,
      'partner_locked': 50,
    });

    expect(data.coupleSpaceId, 'space-1');
    expect(data.currentUserId, 'user-a');
    expect(data.partnerUserId, 'user-b');
    expect(data.items.single.name, '关心');
    expect(data.records.single.points, 12);
    expect(data.records.single.rowVersion, 7);
    expect(data.myTotalEarned, 123);
    expect(data.partnerTotalSpent, 30);
    expect(data.myLocked, 40);
  });

  test('RPC home payload treats missing totals and arrays as zero and empty',
      () {
    final data = PointsHomeData.fromJson({
      'couple_space_id': 'space-1',
      'current_user_id': 'user-a',
      'partner_user_id': null,
    });

    expect(data.items, isEmpty);
    expect(data.records, isEmpty);
    expect(data.partnerUserId, isNull);
    expect(data.myTotalEarned, 0);
    expect(data.partnerLocked, 0);
  });
}
