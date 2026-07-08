import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:love_story/core/theme.dart';
import 'package:love_story/core/user_error.dart';
import 'package:love_story/core/bind_prompt.dart';
import 'package:love_story/features/mall/mall_good_model.dart';
import 'package:love_story/features/mall/mall_repository.dart';
import 'package:love_story/features/points/points_repository.dart';
import 'package:love_story/features/points/random_bonus_util.dart';
import 'package:love_story/features/deposits/deposits_repository.dart';
import 'package:provider/provider.dart';
import 'package:love_story/features/auth/auth_service.dart';
import 'package:love_story/features/couple/couple_service.dart';

class MallGoodDetailScreen extends StatefulWidget {
  const MallGoodDetailScreen({super.key, required this.goodId});

  final String goodId;

  @override
  State<MallGoodDetailScreen> createState() => _MallGoodDetailScreenState();
}

class _MallGoodDetailScreenState extends State<MallGoodDetailScreen> {
  MallGoodModel? good;
  bool _loading = true;
  bool _exchanging = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final g = await context.read<MallRepository>().getGood(widget.goodId);
    if (mounted) setState(() {
      good = g;
      _loading = false;
    });
  }

  Future<void> _onRefresh() async {
    context.read<MallRepository>().invalidateGood(widget.goodId);
    await _load();
  }

  /// 可用兑换余额 = 累计获得心意值 - 累计兑换消耗 - 定期锁定本金
  Future<int> _currentBalance(BuildContext context) async {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    final userId = context.read<AuthService>().currentUser?.id;
    if (spaceId == null || userId == null) return 0;
    final pointsRepo = context.read<PointsRepository>();
    final mallRepo = context.read<MallRepository>();
    final depositsRepo = context.read<DepositsRepository>();
    final earned = await pointsRepo.getTotalPointsEarned(spaceId, userId);
    final spent = await mallRepo.getTotalPointsSpent(spaceId, userId);
    final locked = await depositsRepo.getLockedPrincipal(spaceId, userId);
    return earned - spent - locked;
  }

  Future<void> _exchange(BuildContext context, MallGoodModel good) async {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    final userId = context.read<AuthService>().currentUser?.id;
    if (spaceId == null || userId == null) return;
    final balance = await _currentBalance(context);
    if (balance < good.pointsRequired) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('可用兑换余额不足，当前：${formatHeartValueDisplay(balance)}')),
        );
      }
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认兑换'),
        content: Text('使用 ${formatHeartValueDisplay(good.pointsRequired)} 心意值（可用兑换余额）兑换「${good.name}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('兑换')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    if (context.mounted) setState(() => _exchanging = true);
    try {
      await context.read<MallRepository>().exchange(
        coupleSpaceId: spaceId,
        userId: userId,
        mallGoodId: good.id,
        pointsRequired: good.pointsRequired,
        userBalance: balance,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('兑换成功')));
        context.pop();
      }
    } catch (e) {
      if (context.mounted) {
        setState(() => _exchanging = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toUserMessage(e, context: 'MallGoodDetailScreen.exchange'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading || good == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('商品详情'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final g = good!;
    final userId = context.watch<AuthService>().currentUser?.id;
    final hasPartner = context.watch<CoupleService>().hasPartner;

    return Scaffold(
      appBar: AppBar(
        title: const Text('商品详情'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit),
            tooltip: '编辑',
            onPressed: userId != null ? () => context.push('/home/mall/goods/edit/${g.id}') : null,
          ),
        ],
      ),
      body: FutureBuilder<int>(
        future: _currentBalance(context),
        builder: (context, snapshot) {
          final balance = snapshot.data ?? 0;
          final canExchangeNow = userId != null &&
              balance >= g.pointsRequired &&
              (g.isUnlimited || (g.stock ?? 0) > 0);
          return RefreshIndicator(
            onRefresh: _onRefresh,
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          g.name,
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                        if (g.description != null && g.description!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            g.description!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                        const SizedBox(height: 16),
                        Text(
                          '${formatHeartValueDisplay(g.pointsRequired)} 心意值',
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                color: AppTheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        if (!g.isUnlimited)
                          Text('库存 ${g.stock} 件', style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                ),
                if (userId != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    '我的可用兑换余额：${formatHeartValueDisplay(balance)} 心意值',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: !_exchanging && canExchangeNow
                        ? () => _exchange(context, g)
                        : (!hasPartner ? () => showBindPrompt(context) : null),
                    child: _exchanging
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            canExchangeNow
                                ? '用我的兑换余额兑换'
                                : (!hasPartner
                                    ? '对方未关联，点击去关联'
                                    : balance < g.pointsRequired
                                        ? '可用兑换余额不足'
                                        : '库存不足'),
                          ),
                  ),
                ],
              ],
            ),
          ),
          );
        },
      ),
    );
  }
}
