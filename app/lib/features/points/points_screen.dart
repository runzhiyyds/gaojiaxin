import 'package:flutter/material.dart';
import 'package:love_story/core/connectivity_helper.dart';
import 'package:love_story/core/theme.dart';
import 'package:love_story/core/user_error.dart';
import 'package:love_story/core/bind_prompt.dart';
import 'package:love_story/core/settings_prefs.dart';
import 'package:love_story/features/points/point_item_model.dart';
import 'package:love_story/features/points/point_record_model.dart';
import 'package:love_story/features/points/points_repository.dart';
import 'package:love_story/features/points/random_bonus_util.dart';
import 'package:love_story/features/points/recipient_comment_ui.dart';
import 'package:love_story/features/points/love_dimension.dart';
import 'package:love_story/features/mall/mall_repository.dart';
import 'package:love_story/features/deposits/deposits_repository.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:love_story/features/auth/auth_service.dart';
import 'package:love_story/features/couple/couple_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PointsScreen extends StatefulWidget {
  const PointsScreen({super.key});

  @override
  State<PointsScreen> createState() => _PointsScreenState();
}

class _PointsScreenState extends State<PointsScreen> with WidgetsBindingObserver {
  List<PointItemModel> _items = [];
  List<PointRecordModel> _records = [];
  int _totalEarned = 0;
  int _totalSpent = 0;
  int _myTotalEarned = 0;
  int _myTotalSpent = 0;
  int _myLocked = 0;
  int _taLocked = 0;
  bool _loading = true;
  RealtimeChannel? _channel;

  int _recordTabIndex = 0;
  String _noteSearchQuery = '';
  String? _filterPointItemId;
  DateTimeRange? _filterDateRange;
  final _noteSearchController = TextEditingController();
  String? _lastUserId;
  String? _lastSpaceId;
  String? _lastPartnerId;

  /// 用户主动下拉刷新时调用：先使缓存失效再拉取，保证看到最新数据。
  Future<void> _refresh() async {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId != null) {
      _invalidateSpaceCaches(spaceId);
    }
    return _load();
  }

  void _invalidateSpaceCaches(String spaceId) {
    context.read<PointsRepository>().invalidateForSpace(spaceId);
    context.read<MallRepository>().invalidateForSpace(spaceId);
    context.read<DepositsRepository>().invalidateForSpace(spaceId);
  }

  void _resetViewState() {
    if (!mounted) return;
    setState(() {
      _items = [];
      _records = [];
      _totalEarned = 0;
      _totalSpent = 0;
      _myTotalEarned = 0;
      _myTotalSpent = 0;
      _myLocked = 0;
      _taLocked = 0;
      _loading = false;
    });
  }

  /// [silent] 为 true 时不显示 loading，用于 App 恢复时后台拉取最新数据，兼顾速度与实时性。
  Future<void> _load({bool silent = false}) async {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    final partnerId = context.read<CoupleService>().partnerId;
    if (spaceId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!silent) setState(() => _loading = true);
    try {
      final repo = context.read<PointsRepository>();
      final mallRepo = context.read<MallRepository>();
      final historyStart = DateTime(2000, 1, 1);
      final historyEnd = DateTime(2100, 1, 1);
      final start = _filterDateRange?.start ?? historyStart;
      final end = _filterDateRange?.end ?? historyEnd;
      final itemsRaw = await repo.getItems(spaceId);
      final records = await repo.getRecords(
        coupleSpaceId: spaceId,
        from: start,
        to: end,
        pointItemId: _filterPointItemId,
        limit: 200,
      );
      final userId = context.read<AuthService>().currentUser?.id;
      final depositsRepo = context.read<DepositsRepository>();
      int taEarned = 0, taSpent = 0;
      int myEarned = 0, mySpent = 0;
      int myLocked = 0, taLocked = 0;
      if (partnerId != null) {
        taEarned = await repo.getTotalPointsEarned(spaceId, partnerId);
        taSpent = await mallRepo.getTotalPointsSpent(spaceId, partnerId);
        taLocked = await depositsRepo.getLockedPrincipal(spaceId, partnerId);
      }
      if (userId != null) {
        myEarned = await repo.getTotalPointsEarned(spaceId, userId);
        mySpent = await mallRepo.getTotalPointsSpent(spaceId, userId);
        myLocked = await depositsRepo.getLockedPrincipal(spaceId, userId);
      }
      if (mounted) {
        // 与记一笔一致，仅展示九种预设心意类型。
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
        final items = itemsRaw
            .where((e) => e.name != PointsRepository.randomBonusItemName)
            .where((e) => allowedNames.contains(e.name))
            .toList()
          ..sort((a, b) => allowedNames.indexOf(a.name).compareTo(allowedNames.indexOf(b.name)));

        setState(() {
          _items = items;
          _records = records;
          _totalEarned = taEarned;
          _totalSpent = taSpent;
          _myTotalEarned = myEarned;
          _myTotalSpent = mySpent;
          _myLocked = myLocked;
          _taLocked = taLocked;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        final msg = await isOffline()
            ? '请检查网络'
            : toUserMessage(e, context: '积分页加载');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg)),
          );
        }
      }
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
      _subscribeRealtime();
      _showManualIfFirstTime();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final auth = Provider.of<AuthService>(context);
    final couple = Provider.of<CoupleService>(context);
    final currentUserId = auth.currentUser?.id;
    final currentSpaceId = couple.coupleSpaceId;
    final currentPartnerId = couple.partnerId;
    final changed = currentUserId != _lastUserId ||
        currentSpaceId != _lastSpaceId ||
        currentPartnerId != _lastPartnerId;
    if (!changed) return;

    final previousSpaceId = _lastSpaceId;
    _lastUserId = currentUserId;
    _lastSpaceId = currentSpaceId;
    _lastPartnerId = currentPartnerId;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (previousSpaceId != null && previousSpaceId != currentSpaceId) {
        _invalidateSpaceCaches(previousSpaceId);
      }
      if (currentSpaceId == null || currentUserId == null) {
        _channel?.unsubscribe();
        _channel = null;
        _resetViewState();
        return;
      }
      _invalidateSpaceCaches(currentSpaceId);
      _subscribeRealtime();
      _load(silent: true);
    });
  }

  /// 仅在新用户「首次注册并登录」后弹出使用说明（注册时已设 show_manual_on_next_login）
  Future<void> _showManualIfFirstTime() async {
    final showOnNextLogin = await SettingsPrefs.getShowManualOnNextLogin();
    if (!showOnNextLogin || !mounted) return;
    await SettingsPrefs.setShowManualOnNextLogin(false);
    if (mounted) {
      context.push('/home/points/manual', extra: true);
    }
  }

  @override
  void dispose() {
    _noteSearchController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _channel?.unsubscribe();
    super.dispose();
  }

  List<PointRecordModel> _filterRecordsForTab(List<PointRecordModel> records) {
    final userId = context.read<AuthService>().currentUser?.id;
    final partnerId = context.read<CoupleService>().partnerId;
    var list = records;
    if (_recordTabIndex == 0 && userId != null) {
      list = list.where((r) => r.userId == userId).toList();
    } else if (_recordTabIndex == 1 && partnerId != null) {
      list = list.where((r) => r.userId == partnerId).toList();
    }
    if (_noteSearchQuery.trim().isEmpty) return list;
    final q = _noteSearchQuery.trim().toLowerCase();
    return list.where((r) => r.note != null && r.note!.toLowerCase().contains(q)).toList();
  }

  LoveDimension? _recordLoveDimension(PointRecordModel r) {
    if (r.loveDimension != null) return r.loveDimension;
    final item = _items.firstWhere(
      (e) => e.id == r.pointItemId,
      orElse: () => PointItemModel(
        id: '',
        coupleSpaceId: '',
        name: '',
        iconName: 'star',
        pointsPerUnit: 1,
        cycleType: CycleType.month,
        sortOrder: 0,
        isPreset: false,
        isEnabled: true,
      ),
    );
    if (item.id.isEmpty) return null;
    return item.loveDimension;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId == null) return;
    _invalidateSpaceCaches(spaceId);
    _load(silent: true);
  }

  void _subscribeRealtime() {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId == null) return;
    _channel?.unsubscribe();
    _channel = Supabase.instance.client
        .channel('points-$spaceId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'point_records',
          callback: (payload) {
            if (!mounted) return;
            context.read<PointsRepository>().invalidateForSpace(spaceId);
            context.read<MallRepository>().invalidateForSpace(spaceId);
            _load();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'point_items',
          callback: (payload) {
            if (!mounted) return;
            context.read<PointsRepository>().invalidateForSpace(spaceId);
            context.read<MallRepository>().invalidateForSpace(spaceId);
            _load();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'exchange_records',
          callback: (payload) {
            if (!mounted) return;
            context.read<PointsRepository>().invalidateForSpace(spaceId);
            context.read<MallRepository>().invalidateForSpace(spaceId);
            _load();
          },
        )
        .subscribe();
  }

  Future<void> _onRecordTap() async {
    if (!context.read<AuthService>().isLoggedIn) {
      showLoginPrompt(context);
      return;
    }
    if (!context.read<CoupleService>().hasPartner) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('对方尚未关联账号，关联后可记录积分')),
        );
      }
      return;
    }
    context.push('/home/points/record').then((_) => _load());
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
      case 'savings': return Icons.savings;
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

  String _itemName(String itemId) {
    for (final e in _items) if (e.id == itemId) return e.name;
    return '项目';
  }

  String _formatRecordDateTimeFull(DateTime t) {
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  void _openRecordDetailDialog(BuildContext context, PointRecordModel r) {
    final userId = context.read<AuthService>().currentUser?.id;
    final iAmRecipient = userId != null && r.userId == userId;

    PointItemModel? item;
    for (final e in _items) {
      if (e.id == r.pointItemId) {
        item = e;
        break;
      }
    }
    final isRandomFeedback = item == null;
    final displayTitle =
        isRandomFeedback ? PointsRepository.randomBonusItemName : _itemName(r.pointItemId);
    final pointsLabel = '${formatHeartValueDisplay(r.points)} 心意';
    final timeLabel = _formatRecordDateTimeFull(r.recordAt);
    final noteBody = isRandomFeedback
        ? (r.note != null && r.note!.trim().isNotEmpty ? r.note!.trim() : '来自普通模式的随机回馈')
        : (r.note != null && r.note!.trim().isNotEmpty ? r.note!.trim() : '无备注');

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(displayTitle),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('心意值：$pointsLabel', style: Theme.of(ctx).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text('记录时间：$timeLabel', style: Theme.of(ctx).textTheme.bodyMedium),
              const SizedBox(height: 16),
              Text(
                isRandomFeedback ? '说明' : '备注',
                style: Theme.of(ctx).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              SelectableText(
                noteBody,
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                      color: AppTheme.secondary,
                      height: 1.4,
                    ),
              ),
              if (iAmRecipient)
                ...buildRecipientCommentDetailSection(
                  context: ctx,
                  record: r,
                  onCommit: (text) async {
                    try {
                      await context.read<PointsRepository>().setRecipientComment(
                            recordId: r.id,
                            coupleSpaceId: r.coupleSpaceId,
                            comment: text,
                          );
                      if (!context.mounted) return;
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('回应已保存')),
                      );
                      _load();
                    } catch (e) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(toUserMessage(e, context: 'PointsScreen.recipientComment'))),
                      );
                    }
                  },
                )
              else
                ...buildPartnerRecipientCommentReadOnlySection(context: ctx, record: r),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 首页顶部：我的 / Ta 的 心意值与可用兑换余额，分块清晰展示。
  Widget _buildPointsBalanceCard(BuildContext context) {
    final theme = Theme.of(context);
    final myBalance = _myTotalEarned - _myTotalSpent - _myLocked;
    final taBalance = _totalEarned - _totalSpent - _taLocked;

    Widget buildBlock({
      required String title,
      required int pointsEarned,
      required int balance,
      required IconData icon,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: AppTheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppTheme.secondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  '累计心意值',
                  style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.secondary),
                ),
                const SizedBox(width: 8),
                Text(
                  formatHeartValueDisplay(pointsEarned),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppTheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.2),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance_wallet_outlined, size: 18, color: AppTheme.primary),
                  const SizedBox(width: 8),
                  Text(
                    '可用心意余额',
                    style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.secondary),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    formatHeartValueDisplay(balance),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            buildBlock(
              title: '我的',
              pointsEarned: _myTotalEarned,
              balance: myBalance,
              icon: Icons.person_outline,
            ),
            Divider(height: 1, color: theme.dividerColor),
            buildBlock(
              title: 'Ta 的',
              pointsEarned: _totalEarned,
              balance: taBalance,
              icon: Icons.favorite_border,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordFilters(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.search, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _noteSearchController,
                    decoration: const InputDecoration(
                      hintText: '按备注搜索',
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(vertical: 8),
                    ),
                    onChanged: (v) => setState(() => _noteSearchQuery = v),
                  ),
                ),
              ],
            ),
            const Divider(height: 16),
            Row(
              children: [
                Icon(Icons.category_outlined, size: 20, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _filterPointItemId,
                      isExpanded: true,
                      hint: const Text('积分项目'),
                      items: [
                        const DropdownMenuItem(value: null, child: Text('全部项目')),
                        ..._items.map((e) => DropdownMenuItem(value: e.id, child: Text(e.name))),
                      ],
                      onChanged: (v) {
                        setState(() => _filterPointItemId = v);
                        _load();
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.date_range),
                  tooltip: '筛选日期范围',
                  onPressed: () async {
                    final range = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDateRange: _filterDateRange ?? DateTimeRange(
                        start: DateTime(DateTime.now().year, DateTime.now().month, 1),
                        end: DateTime.now(),
                      ),
                    );
                    if (range != null && mounted) {
                      setState(() {
                        _filterDateRange = range;
                        _load();
                      });
                    }
                  },
                ),
              ],
            ),
            if (_filterDateRange != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Text(
                      '${_filterDateRange!.start.month}/${_filterDateRange!.start.day} - ${_filterDateRange!.end.month}/${_filterDateRange!.end.day}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _filterDateRange = null;
                          _load();
                        });
                      },
                      child: const Text('清除'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordList(BuildContext context) {
    final filtered = _filterRecordsForTab(_records);
    if (filtered.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            _recordTabIndex == 0 ? '暂无「我被TA奖励」的记录' : '暂无「我奖励TA」的记录',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.secondary),
          ),
        ),
      );
    }
    final auth = context.read<AuthService>();
    final couple = context.read<CoupleService>();
    final currentUserId = auth.currentUser?.id;
    final partnerId = couple.partnerId;

    bool _canEdit(PointRecordModel r) {
      // 仅允许「我奖励 TA」tab 且该记录尚未使用编辑机会时操作。
      if (_recordTabIndex != 1) return false;
      if (!r.canEditOnce) return false;
      return partnerId != null && r.userId == partnerId;
    }

    bool _canDelete(PointRecordModel r) {
      // 「我奖励 TA」tab 下，该条主记录均可删除（与是否已编辑无关）。
      if (_recordTabIndex != 1) return false;
      return partnerId != null && r.userId == partnerId;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: filtered.map((r) {
        final canEdit = _canEdit(r);
        final canDelete = _canDelete(r);
        final canOperate = canEdit || canDelete;
        // 找到对应的心意项目，以便展示 icon；若找不到则退回占位。
        PointItemModel? item;
        for (final e in _items) {
          if (e.id == r.pointItemId) {
            item = e;
            break;
          }
        }
        final itemName = _itemName(r.pointItemId);
        // 随机奖励记录：其项目为系统隐藏项，不会出现在 _items 中；无论出现在哪个 Tab，统一按「随机奖励」展示。
        final bool isRandomFeedback = item == null;
        final displayTitle =
            isRandomFeedback ? PointsRepository.randomBonusItemName : itemName;
        final pointsText = '${formatHeartValueDisplay(r.points)} 心意';
        final dateText =
            '${r.recordAt.month}/${r.recordAt.day} ${r.recordAt.hour.toString().padLeft(2, '0')}:${r.recordAt.minute.toString().padLeft(2, '0')}';
        final viewerIsRecipient =
            currentUserId != null && r.userId == currentUserId;
        final responseChip = buildRecipientResponseBadgeChip(
          hasRecipientComment: r.hasRecipientComment,
          viewerIsRecordRecipient: viewerIsRecipient,
        );

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            onTap: () => _openRecordDetailDialog(context, r),
            leading: Icon(
              _iconFor(item?.iconName ?? 'star'),
              color: AppTheme.primary,
            ),
            title: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    displayTitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                if (responseChip != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: responseChip,
                  ),
              ],
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 第一行：心意值 + 记录时间
                Text(
                  '$pointsText · $dateText',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                // 第二行：备注或随机奖励说明
                if (isRandomFeedback || (r.note != null && r.note!.isNotEmpty))
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      isRandomFeedback
                          ? '随机奖励'
                          : '备注：${r.note}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppTheme.secondary,
                          ),
                    ),
                  ),
              ],
            ),
            isThreeLine: isRandomFeedback || (r.note != null && r.note!.isNotEmpty),
            trailing: canOperate
                ? PopupMenuButton<String>(
                    onSelected: (value) async {
                      if (value == 'edit') {
                        final changed = await context.push<bool>(
                          '/home/points/record/edit',
                          extra: r,
                        );
                        if (changed == true && mounted) {
                          _load();
                        }
                      } else if (value == 'delete') {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('删除这条记录？'),
                            content: const Text('删除后不可恢复。'),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                child: const Text('取消'),
                              ),
                              FilledButton(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                child: const Text('确认删除'),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true && mounted) {
                          try {
                            await context.read<PointsRepository>().deleteRecord(
                                  recordId: r.id,
                                  coupleSpaceId: r.coupleSpaceId,
                                );
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已删除')),
                            );
                            _load();
                          } catch (e) {
                            if (!mounted) return;
                            final msg = toUserMessage(e, context: 'PointsScreen.deleteRecord');
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(msg)),
                            );
                          }
                        }
                      }
                    },
                    itemBuilder: (ctx) {
                      final items = <PopupMenuEntry<String>>[];
                      if (canEdit) {
                        items.add(const PopupMenuItem(
                          value: 'edit',
                          child: Text('编辑一次'),
                        ));
                      }
                      if (canDelete) {
                        items.add(const PopupMenuItem(
                          value: 'delete',
                          child: Text('删除'),
                        ));
                      }
                      return items;
                    },
                    icon: const Icon(Icons.more_vert),
                  )
                : null,
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final couple = context.watch<CoupleService>();
    final isLoggedIn = auth.isLoggedIn;
    final hasPartner = couple.hasPartner;
    final isBound = couple.isBound;

    return Scaffold(
      appBar: AppBar(
        title: const Text('心意值'),
        leading: IconButton(
          icon: const Icon(Icons.menu_book_outlined),
          tooltip: '使用手册',
          onPressed: () => context.push('/home/points/manual'),
        ),
        actions: const [],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildPointsBalanceCard(context),
                    const SizedBox(height: 16),
                    if (isLoggedIn && !isBound)
                      Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.favorite_border, color: AppTheme.primary),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '尚未绑定情侣空间',
                                      style: Theme.of(context).textTheme.titleSmall,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '与 TA 绑定后可共享积分记录与兑换记录，现在也可以先在主页单人使用。',
                                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                            color: AppTheme.secondary,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        onPressed: () => context.go('/bind'),
                                        icon: const Icon(Icons.link, size: 18),
                                        label: const Text('去绑定情侣空间'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    if (!isLoggedIn)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          '登录后可查看与记录心意值',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.secondary,
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    FilledButton.icon(
                      onPressed: !isLoggedIn
                          ? () => showLoginPrompt(context)
                          : hasPartner
                              ? _onRecordTap
                              : () => showBindPrompt(context),
                      icon: const Icon(Icons.add),
                      label: Text(
                        !isLoggedIn
                            ? '记一笔（请先登录）'
                            : hasPartner
                                ? '记一笔'
                                : '记一笔（需对方关联）',
                      ),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: !isLoggedIn
                          ? () => showLoginPrompt(context)
                          : () => context.push('/home/points/deposits').then((_) => _load()),
                      icon: const Icon(Icons.savings_outlined, size: 20),
                      label: const Text('心意存储'),
                    ),
                    const SizedBox(height: 16),
                    // 简化首页：不再平铺心意项目，仅保留「记一笔」入口及最近记录。
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Text('最近记录', style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('我被TA奖励'), icon: Icon(Icons.favorite_border, size: 18)),
                        ButtonSegment(value: 1, label: Text('我奖励TA'), icon: Icon(Icons.card_giftcard, size: 18)),
                      ],
                      selected: {_recordTabIndex},
                      onSelectionChanged: (s) => setState(() => _recordTabIndex = s.first),
                    ),
                    const SizedBox(height: 8),
                    _buildRecordFilters(context),
                    const SizedBox(height: 8),
                    _buildRecordList(context),
                  ],
                ),
              ),
            ),
    );
  }
}
