import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:love_story/core/theme.dart';
import 'package:love_story/core/user_error.dart';
import 'package:love_story/features/auth/auth_service.dart';
import 'package:love_story/features/couple/couple_service.dart';
import 'package:love_story/features/deposits/point_deposit_model.dart';
import 'package:love_story/features/deposits/deposits_repository.dart';
import 'package:love_story/features/mall/mall_repository.dart';
import 'package:love_story/features/points/points_repository.dart';
import 'package:love_story/features/points/random_bonus_util.dart';
import 'package:provider/provider.dart';

/// 心意存储：活期说明 + 定期产品存入 + 我的定期列表（到期/提前支取）
class DepositsScreen extends StatefulWidget {
  const DepositsScreen({super.key});

  @override
  State<DepositsScreen> createState() => _DepositsScreenState();
}

class _DepositsScreenState extends State<DepositsScreen> {
  int _availableBalance = 0;
  List<PointDepositModel> _deposits = [];
  DepositProductType? _defaultProduct;
  bool _loading = true;

  /// 预计利息（与后端 redeemAtMaturity 一致：本金 × 期限利率，取整）
  static int _interestFor(int principal, double rate) {
    return (principal * rate).round();
  }

  Future<void> _load() async {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    final userId = context.read<AuthService>().currentUser?.id;
    if (spaceId == null || userId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final pointsRepo = context.read<PointsRepository>();
      final mallRepo = context.read<MallRepository>();
      final depositsRepo = context.read<DepositsRepository>();
      final earned = await pointsRepo.getTotalPointsEarned(spaceId, userId);
      final spent = await mallRepo.getTotalPointsSpent(spaceId, userId);
      final locked = await depositsRepo.getLockedPrincipal(spaceId, userId);
      final list = await depositsRepo.getDeposits(spaceId, userId);
      final defaultProduct = await depositsRepo.getDefaultDepositProduct(spaceId, userId);
      if (mounted) {
        setState(() {
          _availableBalance = earned - spent - locked;
          _deposits = list;
          _defaultProduct = defaultProduct;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(toUserMessage(e, context: 'DepositsScreen._load'))),
        );
      }
    }
  }

  Future<void> _deposit(DepositProductType product) async {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    final userId = context.read<AuthService>().currentUser?.id;
    if (spaceId == null || userId == null) return;
    if (_availableBalance < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('可用兑换余额不足，无法存入')),
      );
      return;
    }
    final c = TextEditingController(text: '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final principalTenths = (double.tryParse(c.text.replaceAll(' ', '')) ?? 0) * 10;
          final principal = principalTenths.round();
          final interest = principal >= 10 ? _interestFor(principal, product.rate) : 0;
          final total = principal + interest;
          return AlertDialog(
            title: Text('存入${product.label}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('年化利率 ${(product.rate * 100).toInt()}%，到期本息一次给付；提前支取将扣除全部利息。'),
                  const SizedBox(height: 12),
                  TextField(
                    controller: c,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: '存入心意值',
                      hintText: '最多 ${formatHeartValueDisplay(_availableBalance)}',
                      suffixText: '心意值',
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  if (principal < 10)
                    Text(
                      '输入金额后显示预计收益',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: AppTheme.secondary,
                          ),
                    )
                  else ...[
                    Text(
                      '到期预计利息：${formatHeartValueDisplay(interest)} 心意值',
                      style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '到期本息合计：${formatHeartValueDisplay(total)} 心意值',
                      style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppTheme.primary,
                          ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
              FilledButton(
                onPressed: () {
                  final v = (double.tryParse(c.text.replaceAll(' ', '')) ?? 0) * 10;
                  final p = v.round();
                  if (p < 10) {
                    ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('请输入有效心意值（至少 1.0）')));
                    return;
                  }
                  if (p > _availableBalance) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('超过可用余额 ${formatHeartValueDisplay(_availableBalance)}')));
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: const Text('确认存入'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true || !mounted) return;
    final principal = ((double.tryParse(c.text.replaceAll(' ', '')) ?? 0) * 10).round();
    if (principal < 10 || principal > _availableBalance) return;
    try {
      await context.read<DepositsRepository>().createDeposit(
        coupleSpaceId: spaceId,
        userId: userId,
        productType: product,
        principal: principal,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('存入成功')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(toUserMessage(e, context: 'DepositsScreen._deposit'))),
        );
      }
    }
  }

  Future<void> _redeemAtMaturity(PointDepositModel d) async {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('到期支取'),
        content: Text(
          '本金 ${formatHeartValueDisplay(d.principal)} 心意值，利息 ${formatHeartValueDisplay((d.principal * d.interestRate).round())} 心意值将计入你的心意值账户。确认支取？',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('支取')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<DepositsRepository>().redeemAtMaturity(spaceId, d.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('支取成功，利息已到账')));
        context.read<PointsRepository>().invalidateForSpace(spaceId);
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(toUserMessage(e, context: 'DepositsScreen._redeemAtMaturity'))),
        );
      }
    }
  }

  Future<void> _redeemEarly(PointDepositModel d) async {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('提前支取'),
        content: const Text('提前支取将失去全部利息，仅退回本金。确定要提前支取吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('确认提前支取'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<DepositsRepository>().redeemEarly(spaceId, d.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已提前支取，本金已退回')));
        _load();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(toUserMessage(e, context: 'DepositsScreen._redeemEarly'))),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('心意存储'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => context.pop()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '可用兑换余额',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              formatHeartValueDisplay(_availableBalance),
                              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                    color: AppTheme.primary,
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '可存入定期的心意值（总余额 − 已锁定）',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.secondary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_availableBalance > 0) ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '预计收益',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 8),
                              RichText(
                                text: TextSpan(
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: Theme.of(context).textTheme.bodyMedium?.color,
                                      ),
                                  children: [
                                    const TextSpan(text: '以当前余额 '),
                                    TextSpan(
                                      text: formatHeartValueDisplay(_availableBalance),
                                      style: const TextStyle(
                                        color: AppTheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const TextSpan(text: ' 心意值为例，若存入定期：存一年预计利息约 '),
                                    TextSpan(
                                      text: formatHeartValueDisplay(_interestFor(_availableBalance, DepositProductType.oneYear.rate)),
                                      style: const TextStyle(
                                        color: AppTheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const TextSpan(text: ' 心意值，存两年约 '),
                                    TextSpan(
                                      text: formatHeartValueDisplay(_interestFor(_availableBalance, DepositProductType.twoYears.rate)),
                                      style: const TextStyle(
                                        color: AppTheme.primary,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const TextSpan(text: ' 心意值。'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ] else ...[
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            '有积分后可在此查看预计收益',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: AppTheme.secondary,
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    Text('活期', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.account_balance_wallet_outlined, color: AppTheme.primary),
                        title: const Text('不存定期'),
                        subtitle: Text(
                          '未存入定期的心意值随时可用于兑换，无利息。',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('新奖励默认存入', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '选好后，对方给你记的心意值将自动存入该定期。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.secondary),
                    ),
                    const SizedBox(height: 8),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<DepositProductType?>(
                            value: _defaultProduct,
                            isExpanded: true,
                            hint: const Text('不自动存'),
                            items: [
                              const DropdownMenuItem<DepositProductType?>(
                                value: null,
                                child: Text('不自动存'),
                              ),
                              ...DepositProductType.values.map(
                                (p) => DropdownMenuItem<DepositProductType?>(
                                  value: p,
                                  child: Text('默认存${p.label}'),
                                ),
                              ),
                            ],
                            onChanged: (DepositProductType? value) async {
                              final spaceId = context.read<CoupleService>().coupleSpaceId;
                              final userId = context.read<AuthService>().currentUser?.id;
                              if (spaceId == null || userId == null) return;
                              try {
                                await context.read<DepositsRepository>().setDefaultDepositProduct(
                                      spaceId,
                                      userId,
                                      productType: value,
                                    );
                                if (mounted) setState(() => _defaultProduct = value);
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(toUserMessage(e, context: 'DepositsScreen.onChanged'))),
                                  );
                                }
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text('定期 · 零存整取', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(
                      '到期本息一次给付；提前支取扣光利息。',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.secondary),
                    ),
                    const SizedBox(height: 8),
                    ...DepositProductType.values.map((product) {
                      final interestPreview = _availableBalance > 0
                          ? _interestFor(_availableBalance, product.rate)
                          : _interestFor(100, product.rate);
                      final subtitleLine2 = _availableBalance > 0
                          ? '当前余额全存到期约 +${formatHeartValueDisplay(interestPreview)} 心意值利息'
                          : '每 100 心意值到期约 +${formatHeartValueDisplay(interestPreview)} 心意值利息';
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.savings, color: AppTheme.primary),
                          title: Text(product.label),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('年化 ${(product.rate * 100).toInt()}%'),
                              const SizedBox(height: 2),
                              Text(
                                subtitleLine2,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: AppTheme.primary,
                                    ),
                              ),
                            ],
                          ),
                          trailing: FilledButton(
                            onPressed: _availableBalance < 1 ? null : () => _deposit(product),
                            child: const Text('存入'),
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('我的定期', style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_deposits.isEmpty)
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            '暂无定期存款',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.secondary),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      ..._deposits.map((d) {
                        final product = DepositProductType.fromString(d.productType);
                        final label = product?.label ?? d.productType;
                        final isMatured = d.endAt.isBefore(DateTime.now()) || d.endAt.isAtSameMomentAs(DateTime.now());
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    const Spacer(),
                                    Text('${formatHeartValueDisplay(d.principal)} 心意值', style: const TextStyle(color: AppTheme.primary)),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${(d.interestRate * 100).toInt()}% · 到期 ${d.endAt.year}/${d.endAt.month}/${d.endAt.day}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                                if (d.isActive) ...[
                                  const SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      if (isMatured)
                                        FilledButton(
                                          onPressed: () => _redeemAtMaturity(d),
                                          child: const Text('到期支取'),
                                        )
                                      else
                                        TextButton(
                                          onPressed: () => _redeemEarly(d),
                                          child: const Text('提前支取'),
                                        ),
                                    ],
                                  ),
                                ] else
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      d.isRedeemed ? '已到期兑付' : '已提前支取',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: AppTheme.secondary,
                                          ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
    );
  }
}
