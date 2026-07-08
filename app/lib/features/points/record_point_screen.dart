import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:love_story/core/theme.dart';
import 'package:love_story/core/user_error.dart';
import 'package:love_story/features/points/point_item_model.dart';
import 'package:love_story/features/points/point_record_model.dart';
import 'package:love_story/features/points/points_repository.dart';
import 'package:love_story/features/points/love_dimension.dart';
import 'package:love_story/features/points/random_bonus_util.dart';
import 'package:love_story/features/deposits/deposits_repository.dart';
import 'package:love_story/features/deposits/point_deposit_model.dart';
import 'package:provider/provider.dart';
import 'package:love_story/features/auth/auth_service.dart';
import 'package:love_story/features/couple/couple_service.dart';

enum _RewardMode {
  normal,      // 普通模式：三档随机心意值 + 自己随机回馈
  domineering, // 霸总模式：只奖励对方，不给自己随机奖励
}

class RecordPointScreen extends StatefulWidget {
  const RecordPointScreen({super.key});

  @override
  State<RecordPointScreen> createState() => _RecordPointScreenState();
}

class _RecordPointScreenState extends State<RecordPointScreen> {
  List<PointItemModel> _items = [];
  PointItemModel? _defaultItem;
  bool _loading = true;
  PointItemModel? _selected;
  final _pointsController = TextEditingController();
  final _noteController = TextEditingController();
  bool _saving = false;
  _RewardMode _rewardMode = _RewardMode.normal;
  // 维度已简化为预设心意类型，不再单独编辑。
  LoveDimension? _overrideLoveDimension;
  HeartAmountTier? _heartTier;
  int _normalModePointsTenths = 0;
  DateTime _recordAt = DateTime.now();

  Future<void> _loadItems() async {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId == null) return;
    setState(() => _loading = true);
    try {
      final repo = context.read<PointsRepository>();
      final raw = await repo.getItems(spaceId);
      // 仅保留系统预设的九种心意类型；随机奖励项目不可选（已在仓库中单独标记）。
      const allowedNames = [
        '关心',
        '陪伴',
        '理解',
        '成长',
        '责任',
        '仪式感',
        '激情',
        '日常',
        '纪念过去',
      ];
      final list = raw
          .where((e) => e.name != PointsRepository.randomBonusItemName)
          .where((e) => allowedNames.contains(e.name))
          .toList()
        ..sort((a, b) => allowedNames.indexOf(a.name).compareTo(allowedNames.indexOf(b.name)));
      if (mounted) {
        setState(() {
          _items = list;
          _defaultItem = null;
          _loading = false;
          if (_selected == null && list.isNotEmpty) {
            // 默认选中「日常」，若不存在则退回第一个
            _selected = list.firstWhere(
              (e) => e.name == '日常',
              orElse: () => list.first,
            );
            if (_rewardMode == _RewardMode.domineering) {
              // 霸总模式下输入框显示的是「心意值」而不是十分之一单位，这里填 1.0
              _pointsController.text = formatHeartValueDisplay(_selected!.pointsPerUnit);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(toUserMessage(e, context: 'RecordPointScreen._loadItems'))));
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _recordAt = DateTime.now();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadItems());
  }

  @override
  void dispose() {
    _pointsController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_selected == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择心意项目')));
      return;
    }
    int pointsTenths;
    if (_rewardMode == _RewardMode.normal) {
      if (_normalModePointsTenths < 1) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请选择本次心意档位（小额/中额/大额）')));
        return;
      }
      pointsTenths = _normalModePointsTenths;
    } else {
      final input = _pointsController.text.trim();
      final parsed = double.tryParse(input);
      if (parsed == null || parsed < 0.1) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入有效心意值（支持一位小数）')));
        return;
      }
      pointsTenths = (parsed * kHeartValueScale).round().clamp(1, 9999);
    }
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    final partnerId = context.read<CoupleService>().partnerId;
    final currentUserId = context.read<AuthService>().currentUser?.id;
    if (spaceId == null || partnerId == null || currentUserId == null) return;
    setState(() => _saving = true);
    try {
      final noteText = _noteController.text.trim();
      final repo = context.read<PointsRepository>();
      final depositsRepo = context.read<DepositsRepository>();
      ({PointRecordModel? record, int bonus, bool bonusOk})? randomResult;

      if (_rewardMode == _RewardMode.normal) {
        final label = '${_selected!.name}${noteText.isNotEmpty ? '：$noteText' : ''}';
        randomResult = await repo.addRecordWithRandomBonus(
          coupleSpaceId: spaceId,
          partnerId: partnerId,
          currentUserId: currentUserId,
          pointItemId: _selected!.id,
          points: pointsTenths,
          note: noteText.isEmpty ? null : noteText,
          sourceLabel: label,
          loveDimension: _selected?.loveDimension,
          recordAt: _recordAt,
        );
        if (randomResult!.record == null) throw Exception('记录失败，请稍后重试');
      } else {
        final mainRecord = await repo.addRecord(
          coupleSpaceId: spaceId,
          userId: partnerId,
          pointItemId: _selected!.id,
          points: pointsTenths,
          recordAt: _recordAt,
          note: noteText.isEmpty ? null : noteText,
          loveDimension: _selected?.loveDimension,
        );
        if (mainRecord == null) throw Exception('记录失败，请稍后重试');
      }

      if (!mounted) return;
      var autoDepositDone = false;
      try {
        final defaultProduct = await depositsRepo.getDefaultDepositProduct(spaceId, partnerId);
        if (defaultProduct != null) {
          await depositsRepo.addToDepositOrCreate(
            coupleSpaceId: spaceId,
            userId: partnerId,
            productType: defaultProduct,
            principal: pointsTenths,
          );
          autoDepositDone = true;
        }
      } catch (_) {}
      final suffix = autoDepositDone ? '；TA 的心意值已自动存入其默认定期。' : '';

      if (!mounted) return;
      if (_rewardMode == _RewardMode.normal && randomResult != null) {
        if (!randomResult.bonusOk) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('记录成功，回馈发放延迟，请稍后刷新$suffix')),
          );
        } else {
          final bonusDisplay = formatHeartValueDisplay(randomResult.bonus);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('为今天的体贴种下 ${formatHeartValueDisplay(pointsTenths)} 点心意；TA 也悄悄回馈了你 $bonusDisplay 点心意～$suffix')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('记录成功，这次是霸总模式，只给 TA 种下了心意$suffix')),
        );
      }
      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        final msg = toUserMessage(e, context: 'RecordPointScreen._submit');
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
        context.read<PointsRepository>().invalidateForSpace(spaceId);
        setState(() => _saving = false);
      }
    }
  }

  IconData _iconFor(String name) {
    switch (name) {
      case 'cleaning_services': return Icons.cleaning_services;
      case 'card_giftcard': return Icons.card_giftcard;
      case 'schedule': return Icons.schedule;
      case 'restaurant': return Icons.restaurant;
      case 'spa': return Icons.spa;
      case 'favorite': return Icons.favorite;
      case 'fitness_center': return Icons.fitness_center;
      case 'bedtime': return Icons.bedtime;
      case 'auto_awesome': return Icons.auto_awesome;
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
        title: const Text('记一笔'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.star_border, size: 56, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        const Text(
                          '暂无心意类型',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '请稍后重试，或联系作者在后台配置预设心意类型。',
                          style: TextStyle(color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        TextButton(
                          onPressed: () => context.pop(),
                          child: const Text('返回'),
                        ),
                      ],
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: const [
                          Text('选择项目', style: TextStyle(fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '点击选择本次要为 TA 记录的心意类型',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.secondary,
                            ),
                      ),
                      const SizedBox(height: 8),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final maxWidth = constraints.maxWidth;
                          final itemWidth = (maxWidth - 2 * 12) / 3; // 三列金刚位
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: _items.map((item) {
                              final selected = _selected?.id == item.id;
                              return SizedBox(
                                width: itemWidth,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    setState(() {
                                      _selected = item;
                                      if (_rewardMode == _RewardMode.domineering) {
                                        _pointsController.text = formatHeartValueDisplay(item.pointsPerUnit);
                                      }
                                      // 普通模式下切换项目不再重置心意档位
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                                    decoration: BoxDecoration(
                                      color: selected ? AppTheme.primary.withOpacity(0.12) : Colors.white,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: selected
                                            ? AppTheme.primary.withOpacity(0.6)
                                            : Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundColor: AppTheme.primary.withOpacity(0.1),
                                          child: Icon(
                                            _iconFor(item.iconName),
                                            color: AppTheme.primary,
                                            size: 20,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          item.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                      if (_rewardMode == _RewardMode.normal) ...[
                        Text(
                          '本次心意档位',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: HeartAmountTier.values.map((tier) {
                            final selected = _heartTier == tier;
                            return Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilledButton.tonal(
                                  style: FilledButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                    backgroundColor: selected
                                        ? AppTheme.primary.withOpacity(0.15)
                                        : Theme.of(context).colorScheme.surface,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _heartTier = tier;
                                      _normalModePointsTenths = sampleHeartValue(tier);
                                    });
                                  },
                                  child: Text(tier.label),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '系统会在该档位范围内随机分配心意值，不要太纠结大小，记录本身和你的心意更重要哦～',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.secondary,
                              ),
                        ),
                        const SizedBox(height: 16),
                      ] else ...[
                        TextField(
                          controller: _pointsController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: '本次心意值',
                            hintText: '支持一位小数，如 5 或 5.5',
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                      // 记录时间
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          '记录时间',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${_recordAt.year}-${_recordAt.month.toString().padLeft(2, '0')}-${_recordAt.day.toString().padLeft(2, '0')} '
                          '${_recordAt.hour.toString().padLeft(2, '0')}:${_recordAt.minute.toString().padLeft(2, '0')}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.secondary,
                              ),
                        ),
                        trailing: TextButton.icon(
                          onPressed: () async {
                            final now = DateTime.now();
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _recordAt,
                              firstDate: DateTime(now.year - 3),
                              lastDate: DateTime(now.year + 1),
                            );
                            if (date == null) return;
                            final time = await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(_recordAt),
                            );
                            if (time == null) {
                              setState(() {
                                _recordAt = DateTime(
                                  date.year,
                                  date.month,
                                  date.day,
                                  _recordAt.hour,
                                  _recordAt.minute,
                                );
                              });
                            } else {
                              setState(() {
                                _recordAt = DateTime(
                                  date.year,
                                  date.month,
                                  date.day,
                                  time.hour,
                                  time.minute,
                                );
                              });
                            }
                          },
                          icon: const Icon(Icons.schedule),
                          label: const Text('修改'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 爱的维度已简化为预设心意类型，不再单独编辑。
                      TextField(
                        controller: _noteController,
                        decoration: const InputDecoration(
                          labelText: '备注（选填）',
                          hintText: '可选',
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        '奖励模式',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 8),
                      SegmentedButton<_RewardMode>(
                        segments: const [
                          ButtonSegment(
                            value: _RewardMode.normal,
                            label: Text('普通模式'),
                          ),
                          ButtonSegment(
                            value: _RewardMode.domineering,
                            label: Text('霸总模式'),
                          ),
                        ],
                        selected: {_rewardMode},
                        onSelectionChanged: (s) {
                          setState(() {
                            _rewardMode = s.first;
                            if (_rewardMode == _RewardMode.normal) {
                              _heartTier = null;
                              _normalModePointsTenths = 0;
                            } else if (_selected != null) {
                              _pointsController.text = formatHeartValueDisplay(_selected!.pointsPerUnit);
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _rewardMode == _RewardMode.normal
                            ? '普通模式：选档位后系统随机为 TA 种下心意，也会悄悄回馈你一点。'
                            : '霸总模式：只给 TA 加心意，不给自己随机回馈，适合纯粹表达心意。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.secondary,
                            ),
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
                            : const Text('确认记录'),
                      ),
                    ],
                  ),
                ),
    );
  }
}
