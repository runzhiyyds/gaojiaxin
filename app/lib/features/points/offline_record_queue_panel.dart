import 'package:flutter/material.dart';
import 'package:love_story/core/theme.dart';
import 'package:love_story/features/points/offline_record_queue.dart';
import 'package:love_story/features/points/random_bonus_util.dart';
import 'package:provider/provider.dart';

class OfflineRecordQueuePanel extends StatelessWidget {
  const OfflineRecordQueuePanel({super.key});

  Future<void> _showEntries(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheetContext) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(sheetContext).height * 0.65,
            child: Consumer<OfflineRecordQueue>(
              builder: (context, queue, _) => Column(
                children: [
                  const ListTile(
                    title: Text('待同步记录'),
                    subtitle: Text('保留到提交成功或你主动删除，不会自动过期'),
                  ),
                  Expanded(
                    child: queue.entries.isEmpty
                        ? const Center(child: Text('已全部同步'))
                        : ListView.builder(
                            itemCount: queue.entries.length,
                            itemBuilder: (context, index) {
                              final entry = queue.entries[index];
                              final payload = entry.payload;
                              final conflict =
                                  entry.status == OfflineRecordStatus.conflict;
                              return ListTile(
                                leading: Icon(
                                  conflict
                                      ? Icons.error_outline
                                      : Icons.cloud_upload_outlined,
                                  color: conflict
                                      ? Theme.of(context).colorScheme.error
                                      : AppTheme.primary,
                                ),
                                title: Text(payload == null
                                    ? '加密记录'
                                    : '${payload.pointItemName} · ${formatHeartValueDisplay(payload.points)} 点'),
                                subtitle: Text(conflict
                                    ? (entry.lastError ?? '线上数据已变化，未自动覆盖')
                                    : '等待联网后自动提交'),
                                trailing: PopupMenuButton<String>(
                                  onSelected: (action) async {
                                    if (action == 'retry') {
                                      await queue.retry(entry.id);
                                    } else if (action == 'delete') {
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (dialogContext) => AlertDialog(
                                          title: const Text('删除这条待同步记录？'),
                                          content:
                                              const Text('删除后无法恢复，且不会再提交到服务器。'),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.pop(
                                                  dialogContext, false),
                                              child: const Text('取消'),
                                            ),
                                            FilledButton(
                                              onPressed: () => Navigator.pop(
                                                  dialogContext, true),
                                              child: const Text('删除'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirmed == true) {
                                        await queue.delete(entry.id);
                                      }
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    if (conflict)
                                      const PopupMenuItem(
                                        value: 'retry',
                                        child: Text('重试（不覆盖线上数据）'),
                                      ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text('删除本地记录'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Consumer<OfflineRecordQueue>(
        builder: (context, queue, _) {
          if (queue.pendingCount == 0) return const SizedBox.shrink();
          final conflict = queue.conflictCount > 0;
          return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Material(
              color: conflict
                  ? Theme.of(context).colorScheme.errorContainer
                  : AppTheme.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              child: ListTile(
                dense: true,
                leading: Icon(conflict
                    ? Icons.error_outline
                    : Icons.cloud_upload_outlined),
                title: Text(conflict
                    ? '${queue.conflictCount} 条记录需要你处理'
                    : '${queue.pendingCount} 条记录待同步'),
                subtitle: Text(conflict
                    ? '不会自动覆盖线上数据'
                    : (queue.syncing ? '正在后台提交…' : '联网后自动提交')),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _showEntries(context),
              ),
            ),
          );
        },
      );
}
