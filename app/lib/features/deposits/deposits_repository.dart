import 'package:love_story/core/cache/app_cache.dart';
import 'package:love_story/features/deposits/point_deposit_model.dart';
import 'package:love_story/features/points/points_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DepositsRepository {
  DepositsRepository(this._client, this._pointsRepository, [AppCache? cache])
      : _cache = cache ?? AppCache.instance;

  final SupabaseClient _client;
  final PointsRepository _pointsRepository;
  final AppCache _cache;

  static const _kLocked = 'pdlocked:';
  static const _kList = 'pdlist:';
  static const _kDefault = 'pddefault:';

  void _invalidate(String coupleSpaceId, String userId) {
    _cache.remove('$_kLocked$coupleSpaceId:$userId');
    _cache.remove('$_kList$coupleSpaceId:$userId');
    _cache.remove('$_kDefault$coupleSpaceId:$userId');
  }

  /// 获取用户在本空间的「新奖励默认存入」产品，null 表示不自动存
  Future<DepositProductType?> getDefaultDepositProduct(String coupleSpaceId, String userId) async {
    final key = '$_kDefault$coupleSpaceId:$userId';
    final cached = _cache.get<String>(key);
    if (cached != null) {
      if (cached.isEmpty) return null;
      return DepositProductType.fromString(cached);
    }
    final res = await _client
        .from('user_deposit_defaults')
        .select('product_type')
        .eq('couple_space_id', coupleSpaceId)
        .eq('user_id', userId)
        .maybeSingle();
    final productType = res?['product_type'] as String?;
    if (productType == null || productType.isEmpty) {
      _cache.set(key, '');
      return null;
    }
    final product = DepositProductType.fromString(productType);
    _cache.set(key, productType);
    return product;
  }

  /// 设置用户在本空间的「新奖励默认存入」；productType 为 null 表示不自动存
  Future<void> setDefaultDepositProduct(
    String coupleSpaceId,
    String userId, {
    DepositProductType? productType,
  }) async {
    await _client.from('user_deposit_defaults').upsert({
      'user_id': userId,
      'couple_space_id': coupleSpaceId,
      'product_type': productType?.value,
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id,couple_space_id');
    _cache.remove('$_kDefault$coupleSpaceId:$userId');
  }

  /// 当前用户在该空间下锁定在定期中的本金总和（status=active）
  Future<int> getLockedPrincipal(String coupleSpaceId, String userId) async {
    final key = '$_kLocked$coupleSpaceId:$userId';
    final cached = _cache.get<int>(key);
    if (cached != null) return cached;
    final res = await _client
        .from('point_deposits')
        .select('principal')
        .eq('couple_space_id', coupleSpaceId)
        .eq('user_id', userId)
        .eq('status', 'active');
    var sum = 0;
    for (final row in res as List) {
      sum += (row['principal'] as num).toInt();
    }
    _cache.set(key, sum);
    return sum;
  }

  /// 当前用户的定期存款列表（含已兑付/提前支取），按创建时间倒序
  Future<List<PointDepositModel>> getDeposits(String coupleSpaceId, String userId) async {
    final key = '$_kList$coupleSpaceId:$userId';
    final cached = _cache.get<List<PointDepositModel>>(key);
    if (cached != null) return cached;
    final res = await _client
        .from('point_deposits')
        .select()
        .eq('couple_space_id', coupleSpaceId)
        .eq('user_id', userId)
        .order('created_at', ascending: false);
    final list = (res as List)
        .map((e) => PointDepositModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    _cache.set(key, list);
    return list;
  }

  /// 存入定期：仅写入 point_deposits，不扣减心意值（本金仍在总余额中，仅从可用变为锁定）
  /// 调用方需保证 availableBalance >= principal
  Future<PointDepositModel> createDeposit({
    required String coupleSpaceId,
    required String userId,
    required DepositProductType productType,
    required int principal,
  }) async {
    final now = DateTime.now();
    final months = productType.months;
    final endAt = DateTime(now.year, now.month + months, now.day, now.hour, now.minute, now.second);
    final res = await _client.from('point_deposits').insert({
      'couple_space_id': coupleSpaceId,
      'user_id': userId,
      'product_type': productType.value,
      'principal': principal,
      'interest_rate': productType.rate,
      'start_at': now.toIso8601String(),
      'end_at': endAt.toIso8601String(),
      'status': 'active',
    }).select().single();
    _invalidate(coupleSpaceId, userId);
    _cache.removeByPrefix(_kLocked);
    _cache.removeByPrefix(_kList);
    return PointDepositModel.fromJson(Map<String, dynamic>.from(res as Map));
  }

  /// 零存整取：新奖励并入已有同类型未到期定期，若无则新建一条
  /// 用于「新奖励默认存入」自动入账，保证同一产品类型只累积在一笔定期上
  Future<void> addToDepositOrCreate({
    required String coupleSpaceId,
    required String userId,
    required DepositProductType productType,
    required int principal,
  }) async {
    if (principal < 1) return;
    final existing = await _client
        .from('point_deposits')
        .select()
        .eq('couple_space_id', coupleSpaceId)
        .eq('user_id', userId)
        .eq('product_type', productType.value)
        .eq('status', 'active')
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
    if (existing != null) {
      final id = existing['id'] as String;
      final currentPrincipal = (existing['principal'] as num).toInt();
      await _client.from('point_deposits').update({
        'principal': currentPrincipal + principal,
      }).eq('id', id);
    } else {
      await createDeposit(
        coupleSpaceId: coupleSpaceId,
        userId: userId,
        productType: productType,
        principal: principal,
      );
    }
    _invalidate(coupleSpaceId, userId);
    _cache.removeByPrefix(_kLocked);
    _cache.removeByPrefix(_kList);
  }

  /// 到期支取：计算利息并写入一条心意值记录，更新存款状态
  Future<void> redeemAtMaturity(String coupleSpaceId, String depositId) async {
    final res = await _client
        .from('point_deposits')
        .select()
        .eq('id', depositId)
        .eq('couple_space_id', coupleSpaceId)
        .eq('status', 'active')
        .maybeSingle();
    if (res == null) throw Exception('存款不存在或已兑付');
    final d = PointDepositModel.fromJson(Map<String, dynamic>.from(res as Map));
    final interest = (d.principal * d.interestRate).round();
    final interestItemId = await _pointsRepository.getOrCreateInterestItem(coupleSpaceId);
    await _pointsRepository.addRecord(
      coupleSpaceId: coupleSpaceId,
      userId: d.userId,
      pointItemId: interestItemId,
      points: interest,
      recordAt: DateTime.now(),
      note: '定期${d.principal}心意值到期利息',
    );
    await _client.from('point_deposits').update({
      'status': 'redeemed',
    }).eq('id', depositId);
    _invalidate(coupleSpaceId, d.userId);
    _cache.removeByPrefix(_kLocked);
    _cache.removeByPrefix(_kList);
  }

  /// 提前支取：仅更新状态，不发放利息
  Future<void> redeemEarly(String coupleSpaceId, String depositId) async {
    final res = await _client
        .from('point_deposits')
        .select('user_id')
        .eq('id', depositId)
        .eq('couple_space_id', coupleSpaceId)
        .eq('status', 'active')
        .maybeSingle();
    if (res == null) throw Exception('存款不存在或已兑付');
    final userId = res['user_id'] as String;
    await _client.from('point_deposits').update({
      'status': 'redeemed_early',
    }).eq('id', depositId);
    _invalidate(coupleSpaceId, userId);
    _cache.removeByPrefix(_kLocked);
    _cache.removeByPrefix(_kList);
  }

  void invalidateForSpace(String coupleSpaceId) {
    _cache.removeByPrefix('$_kLocked$coupleSpaceId:');
    _cache.removeByPrefix('$_kList$coupleSpaceId:');
    _cache.removeByPrefix('$_kDefault$coupleSpaceId:');
  }
}
