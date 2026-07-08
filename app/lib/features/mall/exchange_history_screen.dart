import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:love_story/core/theme.dart';
import 'package:love_story/core/user_error.dart';
import 'package:love_story/features/mall/exchange_record_model.dart';
import 'package:love_story/features/mall/mall_repository.dart';
import 'package:love_story/features/points/random_bonus_util.dart';
import 'package:love_story/features/auth/auth_service.dart';
import 'package:provider/provider.dart';
import 'package:love_story/features/couple/couple_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ExchangeHistoryScreen extends StatefulWidget {
  const ExchangeHistoryScreen({super.key});

  @override
  State<ExchangeHistoryScreen> createState() => _ExchangeHistoryScreenState();
}

class _ExchangeHistoryScreenState extends State<ExchangeHistoryScreen> {
  List<ExchangeRecordModel> _records = [];
  Map<String, String> _goodNames = {};
  bool _loading = true;
  RealtimeChannel? _channel;

  Future<void> _load() async {
    final spaceId = context.read<CoupleService>().coupleSpaceId;
    if (spaceId == null) return;
    setState(() => _loading = true);
    try {
      final repo = context.read<MallRepository>();
      final records = await repo.getExchangeHistory(spaceId);
      final goods = await repo.getGoods(spaceId);
      final names = {for (final g in goods) g.id: g.name};
      if (mounted) setState(() {
        _records = records;
        _goodNames = names;
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
        .channel('exchange-$spaceId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'exchange_records',
          callback: (payload) {
            if (!mounted) return;
            context.read<MallRepository>().invalidateForSpace(spaceId);
            _load();
          },
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    final userId = context.watch<AuthService>().currentUser?.id;
    final partnerId = context.watch<CoupleService>().partnerId;
    final hasPartner = context.watch<CoupleService>().hasPartner;

    final myRecords = userId != null
        ? _records.where((r) => r.userId == userId).toList()
        : <ExchangeRecordModel>[];
    final taRecords = partnerId != null
        ? _records.where((r) => r.userId == partnerId).toList()
        : <ExchangeRecordModel>[];
    final unfulfilledTaCount =
        taRecords.where((r) => r.fulfilledAt == null).length;

    return DefaultTabController(
      length: 2,
      initialIndex: 0,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('兑换记录'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
          bottom: TabBar(
            tabs: [
              const Tab(text: '我兑换的'),
              Tab(
                child: unfulfilledTaCount > 0
                    ? Badge(
                        label: Text(
                          unfulfilledTaCount > 99
                              ? '99+'
                              : unfulfilledTaCount.toString(),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                          ),
                        ),
                        child: const Padding(
                          padding: EdgeInsets.only(top: 8, bottom: 8),
                          child: Text('TA兑换的'),
                        ),
                      )
                    : const Text('TA兑换的'),
              ),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                children: [
                  _RecordList(
                    records: myRecords,
                    goodNames: _goodNames,
                    emptyText: '你还没有兑换过',
                    onRefresh: _load,
                    showFulfillButton: false,
                  ),
                  _RecordList(
                    records: taRecords,
                    goodNames: _goodNames,
                    emptyText: hasPartner
                        ? 'TA 还没有兑换过'
                        : '对方尚未关联',
                    onRefresh: _load,
                    showFulfillButton: true,
                    onFulfill: (record) => _markFulfilled(context, record),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _markFulfilled(
      BuildContext context, ExchangeRecordModel record) async {
    final userId = context.read<AuthService>().currentUser?.id;
    if (userId == null) return;
    try {
      await context.read<MallRepository>().markFulfilled(
            recordId: record.id,
            currentUserId: userId,
          );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已标记为已满足')),
        );
        _load();
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  toUserMessage(e, context: 'ExchangeHistoryScreen.markFulfilled'))),
        );
      }
    }
  }
}

class _RecordList extends StatelessWidget {
  const _RecordList({
    required this.records,
    required this.goodNames,
    required this.emptyText,
    required this.onRefresh,
    required this.showFulfillButton,
    this.onFulfill,
  });

  final List<ExchangeRecordModel> records;
  final Map<String, String> goodNames;
  final String emptyText;
  final VoidCallback onRefresh;
  final bool showFulfillButton;
  final void Function(ExchangeRecordModel record)? onFulfill;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async => onRefresh(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.5,
            child: Center(child: Text(emptyText)),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: () async => onRefresh(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: records.length,
        itemBuilder: (context, index) {
          final r = records[index];
          final name = goodNames[r.mallGoodId] ?? '商品';
          final isFulfilled = r.fulfilledAt != null;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      if (showFulfillButton)
                        isFulfilled
                            ? Text(
                                '${r.fulfilledAt!.month}/${r.fulfilledAt!.day} 已满足',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: AppTheme.secondary,
                                    ),
                              )
                            : FilledButton(
                                onPressed: () => onFulfill?.call(r),
                                child: const Text('满足TA'),
                              ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${formatHeartValueDisplay(r.pointsSpent)} 心意值 · ${r.createdAt.month}/${r.createdAt.day} ${r.createdAt.hour}:${r.createdAt.minute.toString().padLeft(2, '0')}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.secondary,
                        ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
