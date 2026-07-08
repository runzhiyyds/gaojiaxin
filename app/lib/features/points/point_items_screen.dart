import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:love_story/core/theme.dart';
import 'package:love_story/core/user_error.dart';
import 'package:love_story/features/points/point_item_model.dart';
import 'package:love_story/features/points/points_repository.dart';
import 'package:love_story/features/points/preset_items.dart';
import 'package:love_story/features/points/love_dimension.dart';
import 'package:provider/provider.dart';
import 'package:love_story/features/couple/couple_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PointItemsScreen extends StatefulWidget {
  const PointItemsScreen({super.key});

  @override
  State<PointItemsScreen> createState() => _PointItemsScreenState();
}

class _PointItemsScreenState extends State<PointItemsScreen> {
  List<PointItemModel> _items = [];
  bool _loading = true;
  String? _error;
  RealtimeChannel? _channel;

  Future<void> _load() async {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final repo = context.read<PointsRepository>();
      final list = await repo.getItemsIncludingDisabled(spaceId);
      if (mounted) setState(() {
        _items = list;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = toUserMessage(e, context: 'PointItemsScreen._load');
        _loading = false;
      });
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
        .channel('point_items-$spaceId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'point_items',
          callback: (payload) {
            if (!mounted) return;
            context.read<PointsRepository>().invalidateForSpace(spaceId);
            _load();
          },
        )
        .subscribe();
  }

  Future<void> _setDefault(PointItemModel item) async {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId == null) return;
    try {
      await context.read<PointsRepository>().setDefaultItem(spaceId, item.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已设为默认项目')));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toUserMessage(e, context: 'PointItemsScreen.setDefault'))));
    }
  }

  Future<void> _addPreset(PresetItemDef def) async {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId == null) return;
    final repo = context.read<PointsRepository>();
    final nextOrder = _items.isEmpty ? 0 : (_items.map((e) => e.sortOrder).reduce((a, b) => a > b ? a : b) + 1);
    try {
      await repo.createItem(
        coupleSpaceId: spaceId,
        name: def.name,
        iconName: def.iconName,
        pointsPerUnit: def.pointsPerUnit,
        cycleType: def.cycleType,
        sortOrder: nextOrder,
        isPreset: true,
        loveDimension: def.loveDimension,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已添加')));
        _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toUserMessage(e, context: 'PointItemsScreen._addPreset'))));
    }
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId == null) return;
    final reordered = List<PointItemModel>.from(_items);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);
    setState(() => _items = reordered);
    try {
      await context.read<PointsRepository>().updateItemsOrder(
        spaceId,
        reordered.map((e) => e.id).toList(),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toUserMessage(e, context: 'PointItemsScreen._reorder'))));
        context.read<PointsRepository>().invalidateForSpace(spaceId);
        _load();
      }
    }
  }

  IconData _iconFor(String iconName) {
    switch (iconName) {
      case 'cleaning_services': return Icons.cleaning_services;
      case 'card_giftcard': return Icons.card_giftcard;
      case 'schedule': return Icons.schedule;
      case 'restaurant': return Icons.restaurant;
      case 'spa': return Icons.spa;
      case 'favorite': return Icons.favorite;
      case 'fitness_center': return Icons.fitness_center;
      case 'bedtime': return Icons.bedtime;
      case 'psychology': return Icons.psychology;
      case 'trending_up': return Icons.trending_up;
      case 'task_alt': return Icons.task_alt;
      case 'celebration': return Icons.celebration;
      case 'local_fire_department': return Icons.local_fire_department;
      case 'home': return Icons.home;
      case 'photo_album': return Icons.photo_album;
      default: return Icons.star;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('心意项目'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddMenu(context),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(_error!, style: const TextStyle(color: AppTheme.error)),
                      const SizedBox(height: 16),
                      TextButton(onPressed: _load, child: const Text('重试')),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            const Text('暂无心意项目，点击右上角添加预置或自定义项目'),
                            const SizedBox(height: 24),
                            FilledButton.icon(
                              onPressed: () => _showAddMenu(context),
                              icon: const Icon(Icons.add),
                              label: const Text('添加项目'),
                            ),
                          ],
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: _items.length,
                          onReorder: _reorder,
                          itemBuilder: (context, index) {
                            final item = _items[index];
                            return Card(
                              key: ValueKey(item.id),
                              margin: const EdgeInsets.only(bottom: 8),
                              child: ListTile(
                                leading: ReorderableDragStartListener(
                                  index: index,
                                  child: Icon(_iconFor(item.iconName), color: AppTheme.primary),
                                ),
                                title: Row(
                                  children: [
                                    Expanded(child: Text(item.name)),
                                    if (item.isDefault)
                                      Padding(
                                        padding: const EdgeInsets.only(left: 8),
                                        child: Text('默认', style: TextStyle(color: AppTheme.primary, fontSize: 12)),
                                      ),
                                  ],
                                ),
                                subtitle: Text(
                                  _cycleLabel(item.cycleType),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(item.isDefault ? Icons.star : Icons.star_border, color: AppTheme.primary),
                                      onPressed: () => _setDefault(item),
                                      tooltip: '设为默认',
                                    ),
                                    if (!item.isEnabled)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 8),
                                        child: Text('已关闭', style: TextStyle(color: AppTheme.secondary, fontSize: 12)),
                                      ),
                                    const Icon(Icons.chevron_right),
                                  ],
                                ),
                                onTap: () => context.push('/home/points/items/edit/${item.id}').then((_) => _load()),
                              ),
                            );
                          },
                        ),
                ),
    );
  }

  void _showAddMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.star),
              title: const Text('从预置添加'),
              onTap: () {
                Navigator.pop(ctx);
                _showPresetPicker(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_circle_outline),
              title: const Text('自定义项目'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/home/points/items/edit');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showPresetPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择预置项目', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ),
            ...presetItemDefs.map((def) {
              final already = _items.any((e) => e.name == def.name);
              return ListTile(
                leading: Icon(_iconFor(def.iconName), color: AppTheme.primary),
                title: Text(def.name),
                subtitle: null,
                trailing: already ? const Text('已添加', style: TextStyle(color: AppTheme.secondary)) : null,
                onTap: already
                    ? null
                    : () async {
                        Navigator.pop(ctx);
                        await _addPreset(def);
                      },
              );
            }),
          ],
        ),
      ),
    );
  }

  String _cycleLabel(CycleType t) {
    switch (t) {
      case CycleType.day: return '按日';
      case CycleType.week: return '按周';
      case CycleType.month: return '按月';
      case CycleType.year: return '按年';
      case CycleType.all: return '历史所有';
    }
  }
}
