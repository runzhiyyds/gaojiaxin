import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:love_story/core/theme.dart';
import 'package:love_story/core/user_error.dart';
import 'package:love_story/features/points/point_item_model.dart';
import 'package:love_story/features/points/points_repository.dart';
import 'package:love_story/features/points/love_dimension.dart';
import 'package:provider/provider.dart';
import 'package:love_story/features/couple/couple_service.dart';

class PointItemEditScreen extends StatefulWidget {
  const PointItemEditScreen({super.key, this.itemId});

  final String? itemId;

  @override
  State<PointItemEditScreen> createState() => _PointItemEditScreenState();
}

class _PointItemEditScreenState extends State<PointItemEditScreen> {
  final _nameController = TextEditingController();
  final _pointsController = TextEditingController(text: '1');
  CycleType _cycleType = CycleType.month;
  String _iconName = 'star';
  bool _isEnabled = true;
  bool _isDefault = false;
  bool _loading = false;
  LoveDimension? _loveDimension;
  bool get _isCreate => widget.itemId == null;

  static const _iconOptions = [
    'favorite',
    'schedule',
    'psychology',
    'trending_up',
    'task_alt',
    'celebration',
    'local_fire_department',
    'home',
    'photo_album',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.itemId != null) _load();
  }

  Future<void> _load() async {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId == null || widget.itemId == null) return;
    final repo = context.read<PointsRepository>();
    final list = await repo.getItemsIncludingDisabled(spaceId);
    final item = list.cast<PointItemModel?>().firstWhere(
          (e) => e?.id == widget.itemId,
          orElse: () => null,
        );
    if (item != null && mounted) {
      _nameController.text = item.name;
      _pointsController.text = item.pointsPerUnit.toString();
      _cycleType = item.cycleType == CycleType.day || item.cycleType == CycleType.week
          ? CycleType.month
          : item.cycleType;
      _iconName = item.iconName;
      _isEnabled = item.isEnabled;
      _isDefault = item.isDefault;
      _loveDimension = item.loveDimension;
      setState(() {});
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _pointsController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入项目名称')));
      return;
    }
    final points = int.tryParse(_pointsController.text);
    if (points == null || points < 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('分值至少为 1')));
      return;
    }
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId == null) return;
    setState(() => _loading = true);
    try {
      final repo = context.read<PointsRepository>();
      if (_isCreate) {
        final maxOrder = 0; // will get from list if needed
        await repo.createItem(
          coupleSpaceId: spaceId,
          name: name,
          iconName: _iconName,
          pointsPerUnit: points,
          cycleType: _cycleType,
          sortOrder: maxOrder,
          isPreset: false,
          isDefault: _isDefault,
          loveDimension: _loveDimension,
        );
      } else {
        await repo.updateItem(
          id: widget.itemId!,
          name: name,
          iconName: _iconName,
          pointsPerUnit: points,
          cycleType: _cycleType,
          isEnabled: _isEnabled,
          isDefault: _isDefault,
          loveDimension: _loveDimension,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存')));
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toUserMessage(e, context: 'PointItemEditScreen.save'))));
        setState(() => _loading = false);
      }
    }
  }

  IconData _iconFor(String name) {
    switch (name) {
      case 'favorite': return Icons.favorite;
      case 'schedule': return Icons.schedule;
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
        title: Text(_isCreate ? '添加项目' : '编辑项目'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton(
            onPressed: _loading ? null : _save,
            child: _loading ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('保存'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '项目名称', hintText: '如：做家务'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pointsController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '单次心意值'),
            ),
            const SizedBox(height: 16),
            const Text('图标'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _iconOptions.map((name) {
                final selected = _iconName == name;
                return ChoiceChip(
                  label: Icon(_iconFor(name)),
                  selected: selected,
                  onSelected: (v) => setState(() => _iconName = name),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            const Text('统计周期'),
            const SizedBox(height: 8),
            SegmentedButton<CycleType>(
              segments: const [
                ButtonSegment(value: CycleType.month, label: Text('月')),
                ButtonSegment(value: CycleType.year, label: Text('年')),
                ButtonSegment(value: CycleType.all, label: Text('历史所有')),
              ],
              selected: {_cycleType},
              onSelectionChanged: (s) => setState(() => _cycleType = s.first),
            ),
            SwitchListTile(
              title: const Text('设为默认项目'),
              subtitle: const Text('记一笔将一键使用该项目'),
              value: _isDefault,
              onChanged: (v) => setState(() => _isDefault = v),
            ),
            if (!_isCreate) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('启用'),
                value: _isEnabled,
                onChanged: (v) => setState(() => _isEnabled = v),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
