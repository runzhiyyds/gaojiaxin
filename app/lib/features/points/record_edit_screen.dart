import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:love_story/core/theme.dart';
import 'package:love_story/core/user_error.dart';
import 'package:love_story/features/points/point_item_model.dart';
import 'package:love_story/features/points/point_record_model.dart';
import 'package:love_story/features/points/points_repository.dart';
import 'package:love_story/features/points/random_bonus_util.dart';
import 'package:provider/provider.dart';
import 'package:love_story/features/couple/couple_service.dart';

class RecordEditScreen extends StatefulWidget {
  const RecordEditScreen({super.key, required this.record});

  final PointRecordModel record;

  @override
  State<RecordEditScreen> createState() => _RecordEditScreenState();
}

class _RecordEditScreenState extends State<RecordEditScreen> {
  List<PointItemModel> _items = [];
  bool _loading = true;
  PointItemModel? _selectedItem;
  final _pointsController = TextEditingController();
  final _noteController = TextEditingController();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _pointsController.text = formatHeartValueDisplay(widget.record.points);
    _noteController.text = widget.record.note ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadItems());
  }

  @override
  void dispose() {
    _pointsController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId == null) return;
    setState(() => _loading = true);
    try {
      final repo = context.read<PointsRepository>();
      final raw = await repo.getItems(spaceId);
      final list = raw
          .where((e) => e.name != PointsRepository.randomBonusItemName)
          .toList();
      PointItemModel? selected;
      for (final e in list) {
        if (e.id == widget.record.pointItemId) {
          selected = e;
          break;
        }
      }
      if (mounted) {
        setState(() {
          _items = list;
          _selectedItem = selected ?? (list.isNotEmpty ? list.first : null);
          if (_selectedItem != null && _pointsController.text.isEmpty) {
            _pointsController.text = _selectedItem!.pointsPerUnit.toString();
          }
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(toUserMessage(e, context: 'RecordEditScreen._loadItems'))),
        );
      }
    }
  }

  Future<void> _submit() async {
    if (_selectedItem == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择心意项目')),
      );
      return;
    }
    // 历史记录的心意值不可编辑，始终沿用原始数值，仅允许调整项目与备注。
    final points = widget.record.points;
    setState(() => _saving = true);
    try {
      await context.read<PointsRepository>().updateRecord(
            recordId: widget.record.id,
            coupleSpaceId: widget.record.coupleSpaceId,
            points: points,
            note: _noteController.text.trim().isEmpty
                ? null
                : _noteController.text.trim(),
            pointItemId: _selectedItem!.id,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已修改，这条记录以后仍可删除，但不能再次编辑')),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(toUserMessage(e, context: 'RecordEditScreen._submit'))),
        );
        setState(() => _saving = false);
      }
    }
  }

  IconData _iconFor(String name) {
    switch (name) {
      case 'cleaning_services':
        return Icons.cleaning_services;
      case 'card_giftcard':
        return Icons.card_giftcard;
      case 'schedule':
        return Icons.schedule;
      case 'restaurant':
        return Icons.restaurant;
      case 'spa':
        return Icons.spa;
      case 'favorite':
        return Icons.favorite;
      case 'fitness_center':
        return Icons.fitness_center;
      case 'bedtime':
        return Icons.bedtime;
      case 'auto_awesome':
        return Icons.auto_awesome;
      case 'savings':
        return Icons.savings;
      case 'psychology':
        return Icons.psychology;
      case 'trending_up':
        return Icons.trending_up;
      case 'task_alt':
        return Icons.task_alt;
      case 'celebration':
        return Icons.celebration;
      case 'local_fire_department':
        return Icons.local_fire_department;
      case 'home':
        return Icons.home;
      case 'photo_album':
        return Icons.photo_album;
      default:
        return Icons.star;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('编辑记录'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_items.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('编辑记录'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('暂无心意项目，无法编辑'),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('编辑记录'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '每条记录仅支持一次编辑或删除，保存后不可再改。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.secondary,
                  ),
            ),
            const SizedBox(height: 16),
            const Text('心意项目', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ..._items.map((item) {
              final selected = _selectedItem?.id == item.id;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                color: selected ? AppTheme.primary.withOpacity(0.1) : null,
                child: ListTile(
                  leading: Icon(_iconFor(item.iconName), color: AppTheme.primary),
                  title: Text(item.name),
                  subtitle: null,
                  trailing: selected
                      ? const Icon(Icons.check_circle, color: AppTheme.primary)
                      : null,
                  onTap: () {
                    setState(() {
                      _selectedItem = item;
                      _pointsController.text = item.pointsPerUnit.toString();
                    });
                  },
                ),
              );
            }),
            const SizedBox(height: 16),
            TextField(
              controller: _pointsController,
              readOnly: true,
              enabled: false,
              decoration: const InputDecoration(
                labelText: '本次心意值',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: '备注（选填）',
                hintText: '可选',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _submit,
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存（使用本次编辑机会）'),
            ),
          ],
        ),
      ),
    );
  }
}
