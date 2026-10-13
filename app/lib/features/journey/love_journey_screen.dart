import 'dart:async';
import 'package:flutter/material.dart';
import 'package:love_story/core/theme.dart';
import 'package:love_story/core/load_feedback.dart';
import 'package:love_story/core/user_error.dart';
import 'package:love_story/features/points/point_record_model.dart';
import 'package:love_story/features/points/points_repository.dart';
import 'package:love_story/features/points/random_bonus_util.dart';
import 'package:love_story/features/points/point_item_model.dart';
import 'package:love_story/features/points/recipient_comment_ui.dart';
import 'package:provider/provider.dart';
import 'package:love_story/features/auth/auth_service.dart';
import 'package:love_story/features/couple/couple_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 爱情旅程：纵向时间轴，左侧我记下的、右侧 TA 记下的，支持时间筛选与分页加载。
class LoveJourneyScreen extends StatefulWidget {
  const LoveJourneyScreen({super.key});

  @override
  State<LoveJourneyScreen> createState() => _LoveJourneyScreenState();
}

class _LoveJourneyScreenState extends State<LoveJourneyScreen> with WidgetsBindingObserver {
  List<PointRecordModel> _records = [];
  List<PointItemModel> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasData = false;
  bool _hasMore = true;
  int _nextOffset = 0;
  int _loadVersion = 0;
  String? _loadError;
  Object? _lastIdentity;
  bool? _lastBindingLoading;
  Timer? _realtimeDebounce;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  // 每次请求 20 条，默认展示从现在往前的最近 20 条；点击「加载更多」再向前翻。
  static const int _pageSize = 20;
  RealtimeChannel? _channel;

  Future<void> _refresh() async {
    if (!mounted) return;
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId != null) context.read<PointsRepository>().invalidateForSpace(spaceId);
    await context.read<CoupleService>().refresh();
    if (mounted) await _load();
  }

  Future<void> _load({bool append = false}) async {
    if (!mounted || (append && (_loadingMore || _loading || !_hasMore))) return;
    final version = ++_loadVersion;
    final couple = context.read<CoupleService>();
    final userId = context.read<AuthService>().currentUser?.id;
    final spaceId = couple.coupleSpaceId;
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
        _records = [];
        _items = [];
        _hasData = false;
        _loading = false;
        _loadingMore = false;
      });
      return;
    }
    setState(() {
      _loading = !append && !_hasData;
      _loadingMore = append;
      _loadError = null;
    });
    bool isCurrent() => mounted && version == _loadVersion &&
        context.read<AuthService>().currentUser?.id == userId &&
        context.read<CoupleService>().coupleSpaceId == spaceId;
    try {
      final repo = context.read<PointsRepository>();
      final selectedEnd = _rangeEnd;
      final end = selectedEnd == null ? null :
          DateTime(selectedEnd.year, selectedEnd.month, selectedEnd.day + 1)
              .subtract(const Duration(microseconds: 1));
      final offset = append ? _nextOffset : 0;
      final results = await Future.wait<Object>([
        append ? Future.value(_items) : repo.getItemsIncludingDisabled(spaceId),
        repo.getRecords(coupleSpaceId: spaceId, from: _rangeStart, to: end,
            limit: _pageSize, offset: offset),
      ], eagerError: true);
      if (!isCurrent()) return;
      final records = results[1] as List<PointRecordModel>;
      setState(() {
        final knownIds = append ? _records.map((r) => r.id).toSet() : <String>{};
        _records = [if (append) ..._records, ...records.where((r) => knownIds.add(r.id))];
        _items = results[0] as List<PointItemModel>;
        _nextOffset = offset + records.length;
        _hasMore = records.length == _pageSize;
        _hasData = true;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!isCurrent()) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _loadError = toUserMessage(error, context: '爱情旅程加载');
      });
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
      _records = [];
      _items = [];
      _hasData = false;
      _nextOffset = 0;
      _hasMore = true;
      _loadError = null;
      _loading = couple.loading;
      _loadingMore = false;
      _channel?.unsubscribe();
      _channel = null;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || identity != _lastIdentity || couple.loading) return;
      if (changed) _subscribeRealtime();
      _load();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !mounted) return;
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId == null) return;
    context.read<PointsRepository>().invalidateForSpace(spaceId);
    _load();
  }

  @override
  void dispose() {
    _loadVersion++;
    _realtimeDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _channel?.unsubscribe();
    super.dispose();
  }

  String _itemName(String itemId) {
    for (final e in _items) if (e.id == itemId) return e.name;
    return '心意';
  }

  void _subscribeRealtime() {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId == null) return;
    _channel?.unsubscribe();
    _channel = Supabase.instance.client
        .channel('journey-$spaceId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'point_records',
          filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq,
              column: 'couple_space_id', value: spaceId),
          callback: (payload) {
            if (!mounted) return;
            context.read<PointsRepository>().invalidateForSpace(spaceId);
            _realtimeDebounce?.cancel();
            _realtimeDebounce = Timer(const Duration(milliseconds: 350), () {
              if (mounted) _load();
            });
          },
        )
        .subscribe();
  }

  bool _isSystemRecord(PointRecordModel r) {
    final name = _itemName(r.pointItemId);
    return name == PointsRepository.randomBonusItemName || name == PointsRepository.interestItemName;
  }

  String _formatRecordDateTimeFull(DateTime t) {
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  void _openRecordDetailDialog(PointRecordModel r, {required bool isMe}) {
    final title = _itemName(r.pointItemId);
    final pointsLabel = '${formatHeartValueDisplay(r.points)} 心意';
    final timeLabel = _formatRecordDateTimeFull(r.recordAt);
    final noteBody = r.note != null && r.note!.trim().isNotEmpty
        ? r.note!.trim()
        : '那天的用心被记录在这里';

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isMe ? '我的心意' : 'TA 的心意',
                style: Theme.of(ctx).textTheme.labelMedium?.copyWith(color: AppTheme.secondary),
              ),
              const SizedBox(height: 8),
              Text('心意值：$pointsLabel', style: Theme.of(ctx).textTheme.bodyMedium),
              const SizedBox(height: 8),
              Text('记录时间：$timeLabel', style: Theme.of(ctx).textTheme.bodyMedium),
              const SizedBox(height: 16),
              Text(
                '备注',
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
              if (isMe)
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
                      if (!mounted || !ctx.mounted) return;
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('回应已保存')),
                      );
                      _load();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(toUserMessage(e, context: 'LoveJourney.recipientComment'))),
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

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthService>().currentUser?.id;
    final partnerId = context.watch<CoupleService>().partnerId;
    final hasPartner = context.watch<CoupleService>().hasPartner;

    return Scaffold(
      appBar: AppBar(
        title: const Text('爱情旅程'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            tooltip: '时间范围',
            onPressed: () async {
              final range = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
                initialDateRange: _rangeStart != null && _rangeEnd != null
                    ? DateTimeRange(start: _rangeStart!, end: _rangeEnd!)
                    : DateTimeRange(
                        start: DateTime.now().subtract(const Duration(days: 90)),
                        end: DateTime.now(),
                      ),
              );
              if (range != null && mounted) {
                setState(() {
                  _rangeStart = range.start;
                  _rangeEnd = range.end;
                });
                _load();
              }
            },
          ),
        ],
      ),
      body: _loadError != null && !_hasData
          ? LoadFeedback(message: _loadError!, onRetry: _refresh)
          : _loading && !_hasData
              ? const Center(child: CircularProgressIndicator())
          : !hasPartner || userId == null || partnerId == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  hasPartner ? '加载中…' : '绑定另一半后可一起查看爱情旅程',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: AppTheme.secondary),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : _loading
              ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
                  onRefresh: _refresh,
                  child: _records.isEmpty
                      ? SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: Center(
                              child: _loadError != null
                                  ? LoadFeedback(message: _loadError!, onRetry: _refresh)
                                  : Text(
                                '暂无记录，去「心意」页为 TA 记一笔吧',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppTheme.secondary),
                              ),
                            ),
                          ),
                        )
                      : Builder(
                          builder: (context) {
                            final display = _records.where((r) => !_isSystemRecord(r)).toList();
                            // 构建带有日期刻度的时间轴：日期分组标签 + 左右心意事件。
                            final children = <Widget>[
                              if (_loadError != null)
                                RefreshNotice(message: _loadError!, onRetry: _refresh),
                            ];
                            DateTime? lastDate;
                            for (final r in display) {
                              final dateOnly = DateTime(r.recordAt.year, r.recordAt.month, r.recordAt.day);
                              final isMe = r.userId == userId;
                              if (lastDate == null || dateOnly.difference(lastDate).inDays != 0) {
                                lastDate = dateOnly;
                                children.add(
                                  _DateSeparator(date: dateOnly),
                                );
                              }
                              final responseBadge = buildRecipientResponseBadgeChip(
                                hasRecipientComment: r.hasRecipientComment,
                                viewerIsRecordRecipient: isMe,
                                labelFontSize: 10,
                              );
                              children.add(
                                _TimelineRow(
                                  isLeft: isMe,
                                  title: _itemName(r.pointItemId),
                                  subtitle: r.note ?? '那天的用心被记录在这里',
                                  points: formatHeartValueDisplay(r.points),
                                  time: r.recordAt,
                                  responseBadge: responseBadge,
                                  onCardTap: () => _openRecordDetailDialog(r, isMe: isMe),
                                ),
                              );
                            }
                            // 底部「加载更多」区域
                            children.add(
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: Center(
                                  child: _loadingMore
                                      ? const CircularProgressIndicator()
                                      : TextButton(
                                          onPressed: _hasMore
                                              ? () {
                                                  _load(append: true);
                                                }
                                              : null,
                                          child: Text(_hasMore ? '加载更多' : '已加载全部记录'),
                                        ),
                                ),
                              ),
                            );

                            return Column(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '我的心意',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                color: AppTheme.secondary,
                                              ),
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          'TA 的心意',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                color: AppTheme.secondary,
                                              ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Expanded(
                                  child: ListView(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    children: children,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.isLeft,
    required this.title,
    required this.subtitle,
    required this.points,
    required this.time,
    required this.responseBadge,
    required this.onCardTap,
  });

  final bool isLeft;
  final String title;
  final String subtitle;
  final String points;
  final DateTime time;
  final Widget? responseBadge;
  final VoidCallback onCardTap;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: isLeft
                ? _EventCard(
                    title: title,
                    subtitle: subtitle,
                    points: points,
                    time: time,
                    align: Alignment.centerRight,
                    responseBadge: responseBadge,
                    onTap: onCardTap,
                  )
                : const SizedBox(),
          ),
          const SizedBox(width: 8),
          Container(
            width: 2,
            color: AppTheme.primary.withOpacity(0.4),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: !isLeft
                ? _EventCard(
                    title: title,
                    subtitle: subtitle,
                    points: points,
                    time: time,
                    align: Alignment.centerLeft,
                    responseBadge: responseBadge,
                    onTap: onCardTap,
                  )
                : const SizedBox(),
          ),
        ],
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({
    required this.title,
    required this.subtitle,
    required this.points,
    required this.time,
    required this.align,
    required this.responseBadge,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final String points;
  final DateTime time;
  final Alignment align;
  final Widget? responseBadge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Align(
        alignment: align,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 280),
          child: Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                            ),
                            if (responseBadge != null) responseBadge!,
                          ],
                        ),
                      ),
                      Text(
                        points,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.secondary,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.secondary,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${time.month}/${time.day} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AppTheme.secondary,
                        ),
                  ),
                ],
              ),
            ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 日期分隔标记：显示在时间轴中部，突出当天的日期刻度。
class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final label = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          const Expanded(child: Divider()),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppTheme.secondary,
                  ),
            ),
          ),
          const Expanded(child: Divider()),
        ],
      ),
    );
  }
}
