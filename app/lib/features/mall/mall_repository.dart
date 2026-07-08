import 'package:love_story/core/cache/app_cache.dart';
import 'package:love_story/core/supabase_guard.dart';
import 'package:love_story/features/mall/mall_good_model.dart';
import 'package:love_story/features/mall/exchange_record_model.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class MallRepository {
  MallRepository(this._client, [AppCache? cache]) : _cache = cache ?? AppCache.instance;

  final SupabaseClient _client;
  final AppCache _cache;

  static const _kGoods = 'mg:';
  static const _kGoodsOwner = 'mgo:';
  static const _kGood = 'mg1:';
  static const _kSpent = 'msp:';
  static const _kExchange = 'mex:';

  /// 获取指定用户（owner）的商城商品列表。
  Future<List<MallGoodModel>> getGoodsByOwner(String coupleSpaceId, String ownerUserId) async {
    final key = '$_kGoodsOwner$coupleSpaceId:$ownerUserId';
    final cached = _cache.get<List<MallGoodModel>>(key);
    if (cached != null) return cached;
    final res = await withSupabaseCall(
      () => _client
          .from('mall_goods')
          .select()
          .eq('couple_space_id', coupleSpaceId)
          .eq('owner_id', ownerUserId)
          .order('sort_order'),
      isRead: true,
    );
    final list = (res as List)
        .map((e) => MallGoodModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    _cache.set(key, list);
    return list;
  }

  /// 获取空间内全部商品（情侣空间双方可见、可管理）
  Future<List<MallGoodModel>> getGoods(String coupleSpaceId) async {
    final key = '$_kGoods$coupleSpaceId';
    final cached = _cache.get<List<MallGoodModel>>(key);
    if (cached != null) return cached;
    final res = await withSupabaseCall(
      () => _client
          .from('mall_goods')
          .select()
          .eq('couple_space_id', coupleSpaceId)
          .order('category', nullsFirst: false)
          .order('sort_order'),
      isRead: true,
    );
    final list = (res as List)
        .map((e) => MallGoodModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    _cache.set(key, list);
    return list;
  }

  Future<MallGoodModel?> getGood(String id) async {
    final key = '$_kGood$id';
    final cached = _cache.get<MallGoodModel>(key);
    if (cached != null) return cached;
    final res = await withSupabaseCall(
      () => _client.from('mall_goods').select().eq('id', id).maybeSingle(),
      isRead: true,
    );
    if (res == null) return null;
    final good = MallGoodModel.fromJson(Map<String, dynamic>.from(res as Map));
    _cache.set(key, good);
    return good;
  }

  Future<MallGoodModel?> createGood({
    required String coupleSpaceId,
    required String ownerId,
    required String name,
    String? description,
    required int pointsRequired,
    int? stock,
    String? imageUrl,
    int sortOrder = 0,
    String? category,
  }) async {
    final res = await _client.from('mall_goods').insert({
      'couple_space_id': coupleSpaceId,
      'owner_id': ownerId,
      'name': name,
      'description': description,
      'points_required': pointsRequired,
      'stock': stock,
      'image_url': imageUrl,
      'sort_order': sortOrder,
      'category': category,
    }).select().single();
    _invalidateMallGoods(coupleSpaceId);
    return MallGoodModel.fromJson(Map<String, dynamic>.from(res as Map));
  }

  Future<void> updateGood({
    required String id,
    String? name,
    String? description,
    int? pointsRequired,
    int? stock,
    String? imageUrl,
    int? sortOrder,
    String? category,
  }) async {
    final map = <String, dynamic>{'updated_at': DateTime.now().toIso8601String()};
    if (name != null) map['name'] = name;
    if (description != null) map['description'] = description;
    if (pointsRequired != null) map['points_required'] = pointsRequired;
    if (stock != null) map['stock'] = stock;
    if (imageUrl != null) map['image_url'] = imageUrl;
    if (sortOrder != null) map['sort_order'] = sortOrder;
    if (category != null) map['category'] = category;
    await _client.from('mall_goods').update(map).eq('id', id);
    _cache.remove('$_kGood$id');
    _cache.removeByPrefix(_kGoods);
    _cache.removeByPrefix(_kGoodsOwner);
  }

  Future<void> deleteGood(String id) async {
    await _client.from('mall_goods').delete().eq('id', id);
    _cache.remove('$_kGood$id');
    _cache.removeByPrefix(_kGoods);
    _cache.removeByPrefix(_kGoodsOwner);
  }

  void _invalidateMallGoods(String? coupleSpaceId) {
    _cache.removeByPrefix(_kGoods);
    _cache.removeByPrefix(_kGoodsOwner);
    if (coupleSpaceId != null) {
      _cache.removeByPrefix(_kSpent);
      _cache.removeByPrefix(_kExchange);
    }
  }

  /// 使当前空间下所有商城相关缓存失效（Realtime/App 恢复时调用，保证下次读取为最新）
  void invalidateForSpace(String coupleSpaceId) {
    _cache.remove('$_kGoods$coupleSpaceId');
    _cache.removeByPrefix('$_kGoodsOwner$coupleSpaceId:');
    _cache.removeByPrefix('$_kSpent$coupleSpaceId:');
    _cache.removeByPrefix('$_kExchange$coupleSpaceId:');
    _cache.removeByPrefix(_kGood);
  }

  /// 使单个商品缓存失效（详情页下拉刷新或 Realtime 时使用）
  void invalidateGood(String id) {
    _cache.remove('$_kGood$id');
  }

  /// 兑换余额线：该用户累计兑换消耗的积分
  Future<int> getTotalPointsSpent(String coupleSpaceId, String userId) async {
    final key = '$_kSpent$coupleSpaceId:$userId';
    final cached = _cache.get<int>(key);
    if (cached != null) return cached;
    final res = await _client
        .from('exchange_records')
        .select('points_spent')
        .eq('couple_space_id', coupleSpaceId)
        .eq('user_id', userId);
    var sum = 0;
    for (final row in res as List) {
      sum += (row['points_spent'] as num).toInt();
    }
    _cache.set(key, sum);
    return sum;
  }

  Future<List<ExchangeRecordModel>> getExchangeHistory(
    String coupleSpaceId, {
    int limit = 50,
  }) async {
    final key = '$_kExchange$coupleSpaceId:$limit';
    final cached = _cache.get<List<ExchangeRecordModel>>(key);
    if (cached != null) return cached;
    final res = await _client
        .from('exchange_records')
        .select()
        .eq('couple_space_id', coupleSpaceId)
        .order('created_at', ascending: false)
        .limit(limit);
    final list = (res as List)
        .map((e) => ExchangeRecordModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    _cache.set(key, list);
    return list;
  }

  /// 将 TA 的兑换记录标记为「已满足」。仅当记录属于对方时可调用。
  Future<void> markFulfilled({
    required String recordId,
    required String currentUserId,
  }) async {
    final res = await _client
        .from('exchange_records')
        .select('user_id, couple_space_id')
        .eq('id', recordId)
        .maybeSingle();
    if (res == null) throw Exception('记录不存在');
    final recordUserId = res['user_id'] as String;
    if (recordUserId == currentUserId) {
      throw Exception('只能对 TA 的兑换标记满足');
    }
    final coupleSpaceId = res['couple_space_id'] as String;
    await _client.from('exchange_records').update({
      'fulfilled_at': DateTime.now().toIso8601String(),
      'fulfilled_by': currentUserId,
    }).eq('id', recordId);
    _cache.removeByPrefix('$_kExchange$coupleSpaceId:');
  }

  /// 兑换：校验兑换余额与库存后写入兑换记录并扣减库存。
  Future<void> exchange({
    required String coupleSpaceId,
    required String userId,
    required String mallGoodId,
    required int pointsRequired,
    required int userBalance,
  }) async {
    if (userBalance < pointsRequired) {
      throw Exception('兑换余额不足，当前余额：$userBalance');
    }
    final good = await getGood(mallGoodId);
    if (good == null) throw Exception('商品不存在');
    if (!good.isUnlimited && (good.stock ?? 0) < 1) {
      throw Exception('库存不足');
    }
    await _client.from('exchange_records').insert({
      'couple_space_id': coupleSpaceId,
      'user_id': userId,
      'mall_good_id': mallGoodId,
      'points_spent': pointsRequired,
    });
    if (!good.isUnlimited) {
      await _client
          .from('mall_goods')
          .update({
            'stock': (good.stock! - 1),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', mallGoodId);
    }
    _cache.remove('$_kGood$mallGoodId');
    _cache.remove('$_kGoods$coupleSpaceId');
    _cache.removeByPrefix('$_kGoodsOwner$coupleSpaceId:');
    _cache.remove('$_kSpent$coupleSpaceId:$userId');
    _cache.removeByPrefix('$_kExchange$coupleSpaceId:');
  }
}
