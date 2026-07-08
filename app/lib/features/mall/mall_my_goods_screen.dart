import 'package:flutter/material.dart';
import 'package:love_story/core/theme.dart';
import 'package:love_story/core/user_error.dart';
import 'package:love_story/features/mall/mall_good_model.dart';
import 'package:love_story/features/mall/mall_repository.dart';
import 'package:love_story/features/points/random_bonus_util.dart';
import 'package:love_story/features/mall/preset_mall_goods.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:love_story/features/auth/auth_service.dart';
import 'package:love_story/features/couple/couple_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 管理商城：情侣空间内双方均可对兑换项新增、修改、删除
class MallMyGoodsScreen extends StatefulWidget {
  const MallMyGoodsScreen({super.key});

  @override
  State<MallMyGoodsScreen> createState() => _MallMyGoodsScreenState();
}

class _MallMyGoodsScreenState extends State<MallMyGoodsScreen> {
  List<MallGoodModel> _goods = [];
  bool _loading = true;
  RealtimeChannel? _channel;

  Future<void> _load() async {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId == null) return;
    setState(() => _loading = true);
    try {
      final list = await context.read<MallRepository>().getGoods(spaceId);
      if (mounted) setState(() {
        _goods = list;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _subscribeRealtime();
    });
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  void _subscribeRealtime() {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId == null) return;
    _channel?.unsubscribe();
    _channel = Supabase.instance.client
        .channel('mall-my-$spaceId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'mall_goods',
          callback: (payload) {
            if (!mounted) return;
            context.read<MallRepository>().invalidateForSpace(spaceId);
            _load();
          },
        )
        .subscribe();
  }

  void _showPresetSheet(BuildContext context) {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    final userId = context.read<AuthService>().currentUser?.id;
    if (spaceId == null || userId == null) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) => _PresetList(
          scrollController: scrollController,
          onAdd: (PresetMallGood preset) async {
            try {
              await context.read<MallRepository>().createGood(
                    coupleSpaceId: spaceId,
                    ownerId: userId,
                    name: preset.name,
                    description: preset.description,
                    pointsRequired: preset.pointsRequired,
                    category: preset.category,
                  );
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text('已添加：${preset.name}')),
                );
              }
              if (mounted) _load();
            } catch (e) {
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(content: Text(toUserMessage(e, context: 'Preset.add'))),
                );
              }
            }
          },
        ),
      ),
    );
  }

  Future<void> _confirmDelete(MallGoodModel good) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除兑换项'),
        content: Text('确定删除「${good.name}」？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<MallRepository>().deleteGood(good.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已删除')));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toUserMessage(e, context: 'MallMyGoodsScreen._confirmDelete'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('管理商城'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.library_add),
            tooltip: '从预设添加',
            onPressed: () => _showPresetSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '添加兑换项',
            onPressed: () async {
              await context.push('/home/mall/goods/edit');
              if (mounted) _load();
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _goods.isEmpty
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Icon(Icons.card_giftcard_outlined, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              '暂无兑换项',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '点击右上角添加，或从预设中批量添加',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: AppTheme.secondary,
                                  ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () async {
                                await context.push('/home/mall/goods/edit');
                                if (mounted) _load();
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('添加兑换项'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _goods.length,
                    itemBuilder: (context, index) {
                      final good = _goods[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: CircleAvatar(
                            backgroundColor: AppTheme.primary.withOpacity(0.2),
                            child: const Icon(Icons.card_giftcard, color: AppTheme.primary),
                          ),
                          title: Text(good.name),
                          subtitle: Text(
                          '${formatHeartValueDisplay(good.pointsRequired)} 心意值'
                            '${good.isUnlimited ? '' : ' · 库存 ${good.stock}'}',
                          ),
                          trailing: PopupMenuButton<String>(
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(value: 'edit', child: Text('编辑')),
                              const PopupMenuItem(value: 'delete', child: Text('删除')),
                            ],
                            onSelected: (v) async {
                              if (v == 'edit') {
                                await context.push('/home/mall/goods/edit/${good.id}');
                                if (mounted) _load();
                              } else if (v == 'delete') {
                                _confirmDelete(good);
                              }
                            },
                          ),
                          onTap: () async {
                            await context.push('/home/mall/goods/${good.id}');
                            if (mounted) _load();
                          },
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

class _PresetList extends StatelessWidget {
  const _PresetList({
    required this.scrollController,
    required this.onAdd,
  });

  final ScrollController scrollController;
  final void Function(PresetMallGood preset) onAdd;

  @override
  Widget build(BuildContext context) {
    final presets = presetMallGoods;
    final byCategory = <String, List<PresetMallGood>>{};
    for (final p in presets) {
      byCategory.putIfAbsent(p.category, () => []).add(p);
    }
    final order = MallCategory.all;
    final ordered = order.where((c) => (byCategory[c]?.length ?? 0) > 0).toList();
    final tiles = <Widget>[];
    for (final cat in ordered) {
      tiles.add(Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(
          cat,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: AppTheme.secondary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ));
      for (final preset in byCategory[cat]!) {
        tiles.add(Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: Text(preset.name),
            subtitle: preset.description != null
                ? Text(preset.description!)
                : Text('${formatHeartValueDisplay(preset.pointsRequired)} 心意值'),
            trailing: const Icon(Icons.add_circle_outline),
            onTap: () {
              onAdd(preset);
              Navigator.pop(context);
            },
          ),
        ));
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('从预设添加'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView.builder(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        itemCount: tiles.length,
        itemBuilder: (context, index) => tiles[index],
      ),
    );
  }
}
