import 'package:flutter_test/flutter_test.dart';
import 'package:love_story/core/cache/persistent_snapshot_store.dart';
import 'package:love_story/features/points/point_item_model.dart';
import 'package:love_story/features/points/point_record_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late PersistentSnapshotStore store;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    store = PersistentSnapshotStore();
  });

  test('couple snapshot is isolated by account', () async {
    await store.writeCoupleBinding(CoupleBindingSnapshot(
      userId: 'user-a',
      savedAt: DateTime.utc(2026, 10, 31),
      profile: {'id': 'user-a', 'nickname': 'A'},
      spaceId: 'space-a',
      inviteCode: null,
      partnerId: 'user-b',
      partner: {'id': 'user-b', 'nickname': 'B'},
    ));

    expect((await store.readCoupleBinding('user-a'))?.spaceId, 'space-a');
    expect(await store.readCoupleBinding('user-b'), isNull);
  });

  test('points snapshot round-trips business values', () async {
    final savedAt = DateTime.utc(2026, 10, 31, 12);
    await store.writePointsHome(PointsHomeSnapshot(
      userId: 'user-a',
      spaceId: 'space-a',
      savedAt: savedAt,
      items: [
        PointItemModel(
          id: 'item-1',
          coupleSpaceId: 'space-a',
          name: '陪伴',
          iconName: 'favorite',
          pointsPerUnit: 10,
          cycleType: CycleType.month,
          sortOrder: 0,
          isPreset: true,
          isEnabled: true,
        ),
      ],
      records: [
        PointRecordModel(
          id: 'record-1',
          coupleSpaceId: 'space-a',
          userId: 'user-b',
          pointItemId: 'item-1',
          points: 35,
          recordAt: savedAt,
          note: '晚饭',
        ),
      ],
      partnerTotalEarned: 2703,
      partnerTotalSpent: 490,
      myTotalEarned: 2467,
      myTotalSpent: 200,
      myLocked: 0,
      partnerLocked: 200,
    ));

    final restored = await store.readPointsHome('user-a', 'space-a');
    expect(restored, isNotNull);
    expect(restored!.savedAt, savedAt);
    expect(restored.items.single.name, '陪伴');
    expect(restored.records.single.note, '晚饭');
    expect(restored.partnerTotalEarned, 2703);
    expect(restored.myTotalEarned, 2467);
  });

  test('corrupt snapshots fail closed and are removed', () async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      'love_story.snapshot.v1.couple.user-a',
      '{broken',
    );

    expect(await store.readCoupleBinding('user-a'), isNull);
    expect(
      preferences.containsKey('love_story.snapshot.v1.couple.user-a'),
      isFalse,
    );
  });

  test('clearing one account preserves another account', () async {
    for (final userId in ['user-a', 'user-b']) {
      await store.writeCoupleBinding(CoupleBindingSnapshot(
        userId: userId,
        savedAt: DateTime.utc(2026, 10, 31),
        profile: {'id': userId},
        spaceId: 'space-$userId',
        inviteCode: null,
        partnerId: null,
        partner: null,
      ));
    }

    await store.clearUser('user-a');

    expect(await store.readCoupleBinding('user-a'), isNull);
    expect(await store.readCoupleBinding('user-b'), isNotNull);
  });
}
