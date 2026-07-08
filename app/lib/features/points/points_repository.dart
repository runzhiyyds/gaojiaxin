import 'package:love_story/core/cache/app_cache.dart';
import 'package:love_story/core/supabase_guard.dart';
import 'package:love_story/features/points/point_item_model.dart';
import 'package:love_story/features/points/point_record_model.dart';
import 'package:love_story/features/points/random_bonus_util.dart';
import 'package:love_story/features/points/love_dimension.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 心意值数据源抽象，便于单测 Mock 与后续换数据源。
abstract class IPointsRepository {
  Future<List<PointItemModel>> getItems(String coupleSpaceId);
  Future<List<PointRecordModel>> getRecords({
    required String coupleSpaceId,
    DateTime? from,
    DateTime? to,
    String? pointItemId,
    int limit = 50,
  });
  void invalidateForSpace(String coupleSpaceId);
}

class PointsRepository implements IPointsRepository {
  PointsRepository(this._client, [AppCache? cache]) : _cache = cache ?? AppCache.instance;

  final SupabaseClient _client;
  final AppCache _cache;

  static const _kItems = 'pi:';
  static const _kItemsAll = 'pia:';
  static const _kDefaultItem = 'pid:';
  static const _kRandomBonusItem = 'piri:';
  static const _kInterestItem = 'piint:';
  static const _kRecords = 'pr:';
  static const _kEarned = 'pe:';
  static const _kCycleTotals = 'pc:';

  /// 系统心意项名称，用于随机奖励记录，不在记一笔项目列表中供用户选择
  static const randomBonusItemName = '随机奖励';
  /// 系统心意项名称，用于存储到期利息入账
  static const interestItemName = '利息';

  void _invalidatePoints(String coupleSpaceId) {
    _cache.remove('$_kItems$coupleSpaceId');
    _cache.remove('$_kItemsAll$coupleSpaceId');
    _cache.remove('$_kDefaultItem$coupleSpaceId');
    _cache.remove('$_kRandomBonusItem$coupleSpaceId');
    _cache.remove('$_kInterestItem$coupleSpaceId');
    _cache.removeByPrefix('$_kRecords$coupleSpaceId:');
    _cache.removeByPrefix('$_kEarned$coupleSpaceId:');
    _cache.removeByPrefix('$_kCycleTotals$coupleSpaceId:');
  }

  /// 获取或创建本空间的「随机奖励」积分项（用于记一笔随机回馈）
  Future<String> getOrCreateRandomBonusItem(String coupleSpaceId) async {
    final key = '$_kRandomBonusItem$coupleSpaceId';
    final cached = _cache.get<String>(key);
    if (cached != null) return cached;
    final all = await getItemsIncludingDisabled(coupleSpaceId);
    PointItemModel? existing;
    for (final e in all) {
      if (e.name == randomBonusItemName) {
        existing = e;
        break;
      }
    }
    if (existing != null) {
      _cache.set(key, existing.id);
      return existing.id;
    }
    final created = await createItem(
      coupleSpaceId: coupleSpaceId,
      name: randomBonusItemName,
      iconName: 'auto_awesome',
      pointsPerUnit: 1,
      cycleType: CycleType.month,
      sortOrder: 9999,
      isPreset: false,
      isDefault: false,
    );
    if (created != null) _cache.set(key, created.id);
    return created!.id;
  }

  /// 获取或创建本空间的「利息」积分项（用于存储到期利息入账）
  Future<String> getOrCreateInterestItem(String coupleSpaceId) async {
    final key = '$_kInterestItem$coupleSpaceId';
    final cached = _cache.get<String>(key);
    if (cached != null) return cached;
    final all = await getItemsIncludingDisabled(coupleSpaceId);
    PointItemModel? existing;
    for (final e in all) {
      if (e.name == interestItemName) {
        existing = e;
        break;
      }
    }
    if (existing != null) {
      _cache.set(key, existing.id);
      return existing.id;
    }
    final created = await createItem(
      coupleSpaceId: coupleSpaceId,
      name: interestItemName,
      iconName: 'savings',
      pointsPerUnit: 1,
      cycleType: CycleType.month,
      sortOrder: 9998,
      isPreset: false,
      isDefault: false,
    );
    if (created != null) _cache.set(key, created.id);
    return created!.id;
  }

  /// 使当前空间下所有心意值相关缓存失效（Realtime/App 恢复时调用，保证下次读取为最新）
  void invalidateForSpace(String coupleSpaceId) {
    _invalidatePoints(coupleSpaceId);
  }

  Future<List<PointItemModel>> getItems(String coupleSpaceId) async {
    final key = '$_kItems$coupleSpaceId';
    final cached = _cache.get<List<PointItemModel>>(key);
    if (cached != null) return cached;
    final res = await withSupabaseCall(
      () => _client
          .from('point_items')
          .select()
          .eq('couple_space_id', coupleSpaceId)
          .eq('is_enabled', true)
          .order('sort_order'),
      isRead: true,
    );
    final list = (res as List)
        .map((e) => PointItemModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    _cache.set(key, list);
    return list;
  }

  Future<List<PointItemModel>> getItemsIncludingDisabled(String coupleSpaceId) async {
    final key = '$_kItemsAll$coupleSpaceId';
    final cached = _cache.get<List<PointItemModel>>(key);
    if (cached != null) return cached;
    final res = await withSupabaseCall(
      () => _client
          .from('point_items')
          .select()
          .eq('couple_space_id', coupleSpaceId)
          .order('sort_order'),
      isRead: true,
    );
    final list = (res as List)
        .map((e) => PointItemModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    _cache.set(key, list);
    return list;
  }

  Future<PointItemModel?> createItem({
    required String coupleSpaceId,
    required String name,
    String iconName = 'star',
    int pointsPerUnit = 1,
    CycleType cycleType = CycleType.month,
    int sortOrder = 0,
    bool isPreset = false,
    bool isDefault = false,
    LoveDimension? loveDimension,
  }) async {
    if (isDefault) {
      await _client.from('point_items').update({
        'is_default': false,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('couple_space_id', coupleSpaceId);
    }
    final res = await _client.from('point_items').insert({
      'couple_space_id': coupleSpaceId,
      'name': name,
      'icon_name': iconName,
      'points_per_unit': pointsPerUnit,
      'cycle_type': cycleType.value,
      'sort_order': sortOrder,
      'is_preset': isPreset,
      'is_enabled': true,
      'is_default': isDefault,
      if (loveDimension != null) 'love_dimension': loveDimension.dbValue,
    }).select().single();
    _invalidatePoints(coupleSpaceId);
    return PointItemModel.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// 获取当前空间的默认心意项目（用于记一笔一键记录）
  Future<PointItemModel?> getDefaultItem(String coupleSpaceId) async {
    final key = '$_kDefaultItem$coupleSpaceId';
    final cached = _cache.get<PointItemModel>(key);
    if (cached != null) return cached;
    try {
      final res = await _client
          .from('point_items')
          .select()
          .eq('couple_space_id', coupleSpaceId)
          .eq('is_enabled', true)
          .eq('is_default', true)
          .maybeSingle();
      if (res == null) return null;
      final item = PointItemModel.fromJson(Map<String, dynamic>.from(res as Map));
      _cache.set(key, item);
      return item;
    } catch (_) {
      return null;
    }
  }

  /// 将指定项目设为默认（同空间内仅一个默认）
  Future<void> setDefaultItem(String coupleSpaceId, String itemId) async {
    await _client.from('point_items').update({
      'is_default': false,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('couple_space_id', coupleSpaceId);
    await _client.from('point_items').update({
      'is_default': true,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', itemId);
    _invalidatePoints(coupleSpaceId);
  }

  Future<void> updateItem({
    required String id,
    String? name,
    String? iconName,
    int? pointsPerUnit,
    CycleType? cycleType,
    int? sortOrder,
    bool? isEnabled,
    bool? isDefault,
    LoveDimension? loveDimension,
  }) async {
    final map = <String, dynamic>{
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (name != null) map['name'] = name;
    if (iconName != null) map['icon_name'] = iconName;
    if (pointsPerUnit != null) map['points_per_unit'] = pointsPerUnit;
    if (cycleType != null) map['cycle_type'] = cycleType.value;
    if (sortOrder != null) map['sort_order'] = sortOrder;
    if (isEnabled != null) map['is_enabled'] = isEnabled;
    if (loveDimension != null) map['love_dimension'] = loveDimension.dbValue;
    if (isDefault != null) {
      map['is_default'] = isDefault;
      if (isDefault) {
        final row = await _client.from('point_items').select('couple_space_id').eq('id', id).maybeSingle();
        if (row != null) {
          await _client.from('point_items').update({
            'is_default': false,
            'updated_at': DateTime.now().toIso8601String(),
          }).eq('couple_space_id', row['couple_space_id']).neq('id', id);
        }
      }
    }
    await _client.from('point_items').update(map).eq('id', id);
    final row = await _client.from('point_items').select('couple_space_id').eq('id', id).maybeSingle();
    if (row != null) _invalidatePoints(row['couple_space_id'] as String);
  }

  Future<void> updateItemsOrder(String coupleSpaceId, List<String> orderedIds) async {
    for (var i = 0; i < orderedIds.length; i++) {
      await _client
          .from('point_items')
          .update({'sort_order': i, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', orderedIds[i])
          .eq('couple_space_id', coupleSpaceId);
    }
    _invalidatePoints(coupleSpaceId);
  }

  Future<void> deleteItem(String id) async {
    final row = await _client.from('point_items').select('couple_space_id').eq('id', id).maybeSingle();
    await _client.from('point_items').delete().eq('id', id);
    if (row != null) _invalidatePoints(row['couple_space_id'] as String);
  }

  Future<PointRecordModel?> addRecord({
    required String coupleSpaceId,
    required String userId,
    required String pointItemId,
    required int points,
    DateTime? recordAt,
    String? note,
    LoveDimension? loveDimension,
  }) async {
    final res = await _client.from('point_records').insert({
      'couple_space_id': coupleSpaceId,
      'user_id': userId,
      'point_item_id': pointItemId,
      'points': points,
      'record_at': (recordAt ?? DateTime.now()).toIso8601String(),
      if (note != null && note.isNotEmpty) 'note': note,
      if (loveDimension != null) 'love_dimension': loveDimension.dbValue,
    }).select().single();
    _invalidatePoints(coupleSpaceId);
    return PointRecordModel.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// 记一笔给伴侣，并给当前用户一条随机奖励（方案 B）。返回 (主记录, 奖励分, 奖励是否写入成功)。
  /// [sourceLabel] 随机奖励的来源说明，写入奖励记录的 note，便于展示「来自：项目标题」或「来自：项目标题：备注」
  Future<({PointRecordModel? record, int bonus, bool bonusOk})> addRecordWithRandomBonus({
    required String coupleSpaceId,
    required String partnerId,
    required String currentUserId,
    required String pointItemId,
    required int points,
    DateTime? recordAt,
    String? note,
    String? sourceLabel,
    LoveDimension? loveDimension,
  }) async {
    final now = recordAt ?? DateTime.now();
    final main = await addRecord(
      coupleSpaceId: coupleSpaceId,
      userId: partnerId,
      pointItemId: pointItemId,
      points: points,
      recordAt: now,
      note: note,
      loveDimension: loveDimension,
    );
    final bonus = sampleRandomBonus(points);
    var bonusOk = false;
    try {
      final bonusItemId = await getOrCreateRandomBonusItem(coupleSpaceId);
      await addRecord(
        coupleSpaceId: coupleSpaceId,
        userId: currentUserId,
        pointItemId: bonusItemId,
        points: bonus,
        recordAt: now,
        note: sourceLabel != null && sourceLabel.isNotEmpty ? sourceLabel : null,
      );
      bonusOk = true;
    } catch (_) {
      // 主记录已写入，不回滚；仅奖励写入失败
    }
    return (record: main, bonus: bonus, bonusOk: bonusOk);
  }

  Future<List<PointRecordModel>> getRecords({
    required String coupleSpaceId,
    DateTime? from,
    DateTime? to,
    String? pointItemId,
    int limit = 50,
  }) async {
    final fromStr = from?.toIso8601String() ?? 'n';
    final toStr = to?.toIso8601String() ?? 'n';
    final key = '$_kRecords$coupleSpaceId:$fromStr:$toStr:${pointItemId ?? 'n'}:$limit';
    final cached = _cache.get<List<PointRecordModel>>(key);
    if (cached != null) return cached;
    var queryBuilder = _client
        .from('point_records')
        .select()
        .eq('couple_space_id', coupleSpaceId);
    if (from != null) {
      queryBuilder = queryBuilder.gte('record_at', from.toIso8601String());
    }
    if (to != null) {
      queryBuilder = queryBuilder.lte('record_at', to.toIso8601String());
    }
    if (pointItemId != null) {
      queryBuilder = queryBuilder.eq('point_item_id', pointItemId);
    }
    final res = await withSupabaseCall(
      () => queryBuilder
          .order('record_at', ascending: false)
          .limit(limit),
      isRead: true,
    );
    final list = (res as List)
        .map((e) => PointRecordModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    _cache.set(key, list);
    return list;
  }

  /// 爱情心意线：该用户累计获得心意值（只增不减）
  Future<int> getTotalPointsEarned(String coupleSpaceId, String userId) async {
    final key = '$_kEarned$coupleSpaceId:$userId';
    final cached = _cache.get<int>(key);
    if (cached != null) return cached;
    final res = await withSupabaseCall(
      () => _client
          .from('point_records')
          .select('points')
          .eq('couple_space_id', coupleSpaceId)
          .eq('user_id', userId),
      isRead: true,
    );
    var sum = 0;
    for (final row in res as List) {
      sum += (row['points'] as num).toInt();
    }
    _cache.set(key, sum);
    return sum;
  }

  /// 周期内总心意值（按用户汇总）
  Future<Map<String, int>> getCycleTotals({
    required String coupleSpaceId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    final key = '$_kCycleTotals$coupleSpaceId:${periodStart.toIso8601String()}:${periodEnd.toIso8601String()}';
    final cached = _cache.get<Map<String, int>>(key);
    if (cached != null) return cached;
    final res = await withSupabaseCall(
      () => _client
          .from('point_records')
          .select('user_id, points')
          .eq('couple_space_id', coupleSpaceId)
          .gte('record_at', periodStart.toIso8601String())
          .lte('record_at', periodEnd.toIso8601String()),
      isRead: true,
    );
    final map = <String, int>{};
    for (final row in res as List) {
      final uid = row['user_id'] as String;
      final p = (row['points'] as num).toInt();
      map[uid] = (map[uid] ?? 0) + p;
    }
    _cache.set(key, map);
    return map;
  }

  /// 一次性编辑一条心意记录：只允许在尚未使用编辑机会时调用。
  /// 若 [edit_used_at] 已非空，则本次更新将不会生效并抛出异常。
  Future<void> updateRecord({
    required String recordId,
    required String coupleSpaceId,
    required int points,
    String? note,
    required String pointItemId,
  }) async {
    final now = DateTime.now().toIso8601String();
    final updateMap = <String, dynamic>{
      'points': points,
      'point_item_id': pointItemId,
      'edit_used_at': now,
    };
    if (note != null) {
      if (note.isEmpty) {
        updateMap['note'] = null;
      } else {
        updateMap['note'] = note;
      }
    }

    final res = await withSupabaseCall(
      () => _client
          .from('point_records')
          .update(updateMap)
          .eq('id', recordId)
          .filter('edit_used_at', 'is', null)
          .select()
          .maybeSingle(),
      isRead: false,
    );

    if (res == null) {
      throw PostgrestException(
        message: '编辑机会已被使用，无法再次修改这条记录',
        details: null,
        hint: null,
        code: 'edit_used',
      );
    }

    _invalidatePoints(coupleSpaceId);
  }

  /// 删除一条心意记录：与「一次编辑」互不影响，编辑过的记录仍可被删除。
  /// 删除成功后，该记录将彻底消失，无法再恢复。
  Future<void> deleteRecord({
    required String recordId,
    required String coupleSpaceId,
  }) async {
    await withSupabaseCall(
      () => _client
          .from('point_records')
          .delete()
          .eq('id', recordId),
      isRead: false,
    );
    _invalidatePoints(coupleSpaceId);
  }

  /// 收件人（该条记录的 user_id）写/改/清除回应；仅服务端 RPC 校验权限。
  Future<void> setRecipientComment({
    required String recordId,
    required String coupleSpaceId,
    String? comment,
  }) async {
    await withSupabaseCall(
      () => _client.rpc(
            'set_point_record_recipient_comment',
            params: {
              'p_record_id': recordId,
              'p_comment': comment?.trim() ?? '',
            },
          ),
      isRead: false,
    );
    _invalidatePoints(coupleSpaceId);
  }
}
