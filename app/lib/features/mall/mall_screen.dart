import 'dart:async';
import 'package:flutter/material.dart';
import 'package:love_story/core/load_feedback.dart';
import 'package:love_story/core/theme.dart';
import 'package:love_story/core/user_error.dart';
import 'package:love_story/core/bind_prompt.dart';
import 'package:love_story/features/auth/auth_service.dart';
import 'package:love_story/features/mall/mall_good_model.dart';
import 'package:love_story/features/mall/mall_repository.dart';
import 'package:love_story/features/points/points_repository.dart';
import 'package:love_story/features/points/random_bonus_util.dart';
import 'package:love_story/features/deposits/deposits_repository.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:love_story/features/couple/couple_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 积分商城：展示情侣空间内全部可兑换项，双方均可管理
class MallScreen extends StatefulWidget {
  const MallScreen({super.key});

  @override
  State<MallScreen> createState() => _MallScreenState();
}

class _MallScreenState extends State<MallScreen> with WidgetsBindingObserver {
  List<MallGoodModel> _goods = [];
  int _balance = 0;
  bool _loading = true;
  bool _hasData = false;
  String? _loadError;
  int _loadVersion = 0;
  Object? _lastIdentity;
  bool? _lastBindingLoading;
  Timer? _realtimeDebounce;
  RealtimeChannel? _channel;

  Future<void> _refresh() async {
    if (!mounted) return;
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId != null) {
      context.read<MallRepository>().invalidateForSpace(spaceId);
      context.read<PointsRepository>().invalidateForSpace(spaceId);
      context.read<DepositsRepository>().invalidateForSpace(spaceId);
    }
    await context.read<CoupleService>().refresh();
    if (mounted) await _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!mounted) return;
    final version = ++_loadVersion;
    final couple = context.read<CoupleService>();
    final spaceId = couple.coupleSpaceId;
    final userId = context.read<AuthService>().currentUser?.id;
    if (couple.loading) return;
    if (couple.error != null) {
      setState(() {
        _loading = false;
        _loadError = couple.error;
      });
      return;
    }
    if (spaceId == null || userId == null) {
      setState(() {
        _goods = [];
        _balance = 0;
        _hasData = false;
        _loading = false;
        _loadError = null;
      });
      return;
    }
    setState(() {
      _loading = !_hasData;
      _loadError = null;
    });
    bool isCurrent() => mounted && version == _loadVersion &&
        context.read<AuthService>().currentUser?.id == userId &&
        context.read<CoupleService>().coupleSpaceId == spaceId;
    try {
      final mallRepo = context.read<MallRepository>();
      final pointsRepo = context.read<PointsRepository>();
      final depositsRepo = context.read<DepositsRepository>();
      final results = await Future.wait<Object>([
        mallRepo.getGoods(spaceId),
        pointsRepo.getTotalPointsEarned(spaceId, userId),
        mallRepo.getTotalPointsSpent(spaceId, userId),
        depositsRepo.getLockedPrincipal(spaceId, userId),
      ], eagerError: true);
      if (!isCurrent()) return;
      setState(() {
        _goods = results[0] as List<MallGoodModel>;
        _balance = (results[1] as int) - (results[2] as int) - (results[3] as int);
        _hasData = true;
        _loading = false;
      });
    } catch (error) {
      if (!isCurrent()) return;
      setState(() {
        _loading = false;
        _loadError = toUserMessage(error, context: '商城页加载');
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = context.watch<AuthService>();
    final couple = context.watch<CoupleService>();
    final identity = (auth.currentUser?.id, couple.coupleSpaceId, couple.partnerId);
    final changed = identity != _lastIdentity;
    if (!changed && _lastBindingLoading == couple.loading) return;
    _lastIdentity = identity;
    _lastBindingLoading = couple.loading;
    if (changed) {
      _loadVersion++;
      _goods = [];
      _balance = 0;
      _hasData = false;
      _loadError = null;
      _loading = couple.loading;
      _channel?.unsubscribe();
      _channel = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || identity != _lastIdentity || couple.loading) return;
      if (changed) _subscribeRealtime();
      _load(silent: _hasData);
    });
  }

  void _scheduleRealtimeReload() {
    _realtimeDebounce?.cancel();
    _realtimeDebounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) _load(silent: true);
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

  }

  @override
  void dispose() {
    _loadVersion++;
    _realtimeDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _channel?.unsubscribe();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId == null) return;
    context.read<MallRepository>().invalidateForSpace(spaceId);
    context.read<PointsRepository>().invalidateForSpace(spaceId);
    context.read<DepositsRepository>().invalidateForSpace(spaceId);
    _load(silent: true);
  }

  void _subscribeRealtime() {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId == null) return;
    _channel?.unsubscribe();
    _channel = Supabase.instance.client
        .channel('mall-$spaceId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'mall_goods',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq,
              column: 'couple_space_id', value: spaceId),
          callback: (payload) {
            if (!mounted) return;
            context.read<MallRepository>().invalidateForSpace(spaceId);
            context.read<PointsRepository>().invalidateForSpace(spaceId);
            _scheduleRealtimeReload();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'exchange_records',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq,
              column: 'couple_space_id', value: spaceId),
          callback: (payload) {
            if (!mounted) return;
            context.read<MallRepository>().invalidateForSpace(spaceId);
            context.read<PointsRepository>().invalidateForSpace(spaceId);
            _scheduleRealtimeReload();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all, schema: 'public', table: 'point_records',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq,
              column: 'couple_space_id', value: spaceId),
          callback: (_) {
            if (!mounted) return;
            context.read<PointsRepository>().invalidateForSpace(spaceId);
            _scheduleRealtimeReload();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all, schema: 'public', table: 'point_deposits',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq,
              column: 'couple_space_id', value: spaceId),
          callback: (_) {
            if (!mounted) return;
            context.read<DepositsRepository>().invalidateForSpace(spaceId);
            _scheduleRealtimeReload();
          },
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = context.watch<AuthService>().isLoggedIn;
    final couple = context.watch<CoupleService>();
    final hasPartner = couple.hasPartner;
    final partnerName = couple.partnerProfile?['nickname']?.toString() ?? 'TA';

    return Scaffold(
      appBar: AppBar(
        title: const Text('心意商城'),
        actions: [
          IconButton(
            icon: const Icon(Icons.storefront_outlined),
            tooltip: '管理商城',
            onPressed: () {
              if (!isLoggedIn) {
                showLoginPrompt(context);
                return;
              }
              context.push('/home/mall/my-goods').then((_) => _load());
            },
          ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '兑换记录',
            onPressed: () {
              if (!isLoggedIn) {
                showLoginPrompt(context);
                return;
              }
              context.push('/home/mall/history').then((_) => _load());
            },
          ),
        ],
      ),
      body: _loadError != null && !_hasData
          ? LoadFeedback(message: _loadError!, onRetry: _refresh)
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  if (_loadError != null)
                    RefreshNotice(message: _loadError!, onRetry: _refresh),
                  Expanded(child: _buildBody(context, isLoggedIn, hasPartner, partnerName)),
                ]),
    );
  }

  Widget _buildBody(BuildContext context, bool isLoggedIn, bool hasPartner, String partnerName) {
    if (!isLoggedIn) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.shopping_bag_outlined, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(
                    '登录后使用心意商城',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '登录后可查看情侣空间心意商城、兑换记录，双方均可管理兑换项',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.secondary,
                        ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => context.go('/login'),
                    icon: const Icon(Icons.login),
                    label: const Text('去登录'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    if (!hasPartner) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '可用心意余额',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(
                    '${formatHeartValueDisplay(_balance)} 心意值',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppTheme.primary,
                        ),
                  ),
                ],
              ),
            ),
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Icon(Icons.person_off_outlined, size: 48, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text(
                    '对方尚未关联账号',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '等待对方注册并绑定后，将开启情侣空间积分商城，双方可添加兑换项并用积分兑换',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.secondary,
                        ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => showBindPrompt(context),
                    icon: const Icon(Icons.link),
                    label: const Text('去关联情侣空间'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (_goods.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '可用心意余额',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${formatHeartValueDisplay(_balance)} 心意值',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.primary,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(Icons.card_giftcard_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        '空间内暂无兑换项',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '在「管理商城」中添加或从预设中添加兑换项，即可用心意值兑换',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppTheme.secondary,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final tiers = _goodsByPointTier().where((t) => t.goods.isNotEmpty).toList();
    final itemCount = 2 + tiers.fold<int>(0, (s, t) => s + 1 + t.goods.length);

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: itemCount,
        itemBuilder: (context, index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '情侣空间 · 心意兑换',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.secondary,
                    ),
              ),
            );
          }
          if (index == 1) {
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '可用心意余额',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      '${formatHeartValueDisplay(_balance)} 心意值',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary,
                          ),
                    ),
                  ],
                ),
              ),
            );
          }
          var i = index - 2;
          for (final tier in tiers) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      tier.icon,
                      size: 20,
                      color: tier.color ?? AppTheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      tier.label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: tier.color ?? AppTheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
              );
            }
            i--;
            if (i < tier.goods.length) {
              final good = tier.goods[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: CircleAvatar(
                    backgroundColor: (tier.color ?? AppTheme.primary).withOpacity(0.2),
                    child: Icon(Icons.card_giftcard, color: tier.color ?? AppTheme.primary),
                  ),
                  title: Text(good.name),
                  subtitle: Text(
                    '${formatHeartValueDisplay(good.pointsRequired)} 心意值'
                    '${good.isUnlimited ? '' : ' · 库存 ${good.stock}'}',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    if (!isLoggedIn) {
                      showLoginPrompt(context);
                      return;
                    }
                    context.push('/home/mall/goods/${good.id}').then((_) => _load());
                  },
                ),
              );
            }
            i -= tier.goods.length;
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  /// 按心意值分值分层（内部单位为十分之一）：低分段(0.0-9.9)、中分段(10.0-49.9)、高分段(50.0-99.9)、超高分段(100.0+)
  List<({String label, List<MallGoodModel> goods, IconData icon, Color? color})> _goodsByPointTier() {
    const tiers = [
      (label: '低分段 · 0.0～9.9 心意值', min: 0, max: 99, icon: Icons.star_outline, color: null),
      (label: '中分段 · 10.0～49.9 心意值', min: 100, max: 499, icon: Icons.star_half, color: null),
      (label: '高分段 · 50.0～99.9 心意值', min: 500, max: 999, icon: Icons.star, color: null),
      (label: '超高分段 · 100.0+ 心意值', min: 1000, max: 999999, icon: Icons.diamond_outlined, color: null),
    ];
    final result = <({String label, List<MallGoodModel> goods, IconData icon, Color? color})>[];
    for (final t in tiers) {
      final list = _goods
          .where((g) => g.pointsRequired >= t.min && g.pointsRequired <= t.max)
          .toList()
        ..sort((a, b) => a.pointsRequired.compareTo(b.pointsRequired));
      result.add((label: t.label, goods: list, icon: t.icon, color: t.color));
    }
    return result;
  }
}
