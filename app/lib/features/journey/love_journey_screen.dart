import 'package:flutter/material.dart';
import 'package:love_story/core/theme.dart';
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

class _LoveJourneyScreenState extends State<LoveJourneyScreen> {
  List<PointRecordModel> _records = [];
  List<PointItemModel> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  // 每次请求 20 条，默认展示从现在往前的最近 20 条；点击「加载更多」再向前翻。
  static const int _pageSize = 20;
  RealtimeChannel? _channel;

  Future<void> _load({bool append = false}) async {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!append) setState(() => _loading = true);
    if (append) setState(() => _loadingMore = true);
    try {
      final repo = context.read<PointsRepository>();
      // 未选择时间范围时，不加 from/to 条件，默认按时间倒序拉取最近若干条（即「历史全部」但分页展示）。
      DateTime? start;
      DateTime? end;
      if (_rangeStart != null || _rangeEnd != null) {
        end = _rangeEnd ?? DateTime.now();
        start = _rangeStart ?? DateTime(2000, 1, 1);
      }
      final list = await repo.getItemsIncludingDisabled(spaceId);
      final records = await repo.getRecords(
        coupleSpaceId: spaceId,
        from: start,
        to: end,
        limit: append ? _records.length + _pageSize : _pageSize,
      );
      if (mounted) {
        setState(() {
          if (append) {
            _records = records;
          } else {
            _records = records;
            _items = list;
          }
          _loading = false;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _loadingMore = false;
        });
      }
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
          callback: (payload) {
            if (!mounted) return;
            _load();
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
                  _load();
                });
              }
            },
          ),
        ],
      ),
      body: !hasPartner || userId == null || partnerId == null
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
                  onRefresh: () => _load(),
                  child: _records.isEmpty
                      ? SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: SizedBox(
                            height: MediaQuery.of(context).size.height * 0.5,
                            child: Center(
                              child: Text(
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
                            final children = <Widget>[];
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
                                          onPressed: _records.length >= _pageSize
                                              ? () {
                                                  setState(() => _load(append: true));
                                                }
                                              : null,
                                          child: Text(_records.length >= _pageSize ? '加载更多' : '暂无更多'),
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
