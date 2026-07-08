import 'package:flutter/material.dart';
import 'package:love_story/core/theme.dart';
import 'package:love_story/features/points/point_record_model.dart';

/// 收件人回应正文最大长度
const int kRecipientCommentMaxLen = 500;

String formatRecipientCommentAt(DateTime t) {
  return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')} '
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// 列表/时间轴卡片：有回应时展示「已回应」（当前用户是收件人）或「对方回应」（当前用户是赠送方）。
Widget? buildRecipientResponseBadgeChip({
  required bool hasRecipientComment,
  required bool viewerIsRecordRecipient,
  double labelFontSize = 11,
}) {
  if (!hasRecipientComment) return null;
  final label = viewerIsRecordRecipient ? '已回应' : '对方回应';
  final bg = viewerIsRecordRecipient
      ? AppTheme.primary.withOpacity(0.12)
      : AppTheme.success.withOpacity(0.18);
  return Chip(
    label: Text(label),
    labelStyle: TextStyle(fontSize: labelFontSize),
    visualDensity: VisualDensity.compact,
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    padding: EdgeInsets.zero,
    backgroundColor: bg,
  );
}

/// 详情弹窗只读：赠送方查看收件人已写下的回应。
List<Widget> buildPartnerRecipientCommentReadOnlySection({
  required BuildContext context,
  required PointRecordModel record,
}) {
  if (!record.hasRecipientComment) return [];
  return [
    const Divider(height: 24),
    Text(
      '对方回应',
      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 8),
    SelectableText(
      record.recipientComment!.trim(),
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
    ),
    if (record.recipientCommentAt != null)
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          '回应时间：${formatRecipientCommentAt(record.recipientCommentAt!)}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.secondary),
        ),
      ),
  ];
}

/// 详情弹窗内「我的回应」区块（仅当当前用户是该条记录的收件人时由调用方决定是否插入）。
List<Widget> buildRecipientCommentDetailSection({
  required BuildContext context,
  required PointRecordModel record,
  required Future<void> Function(String? trimmedOrNull) onCommit,
}) {
  return [
    const Divider(height: 24),
    Text(
      '我的回应',
      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: 8),
    if (record.hasRecipientComment) ...[
      SelectableText(
        record.recipientComment!.trim(),
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4),
      ),
      if (record.recipientCommentAt != null)
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(
            '回应时间：${formatRecipientCommentAt(record.recipientCommentAt!)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.secondary),
          ),
        ),
    ] else
      Text(
        '还没有写下对这条心意的回应',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTheme.secondary),
      ),
    const SizedBox(height: 12),
    OutlinedButton.icon(
      icon: Icon(record.hasRecipientComment ? Icons.edit_outlined : Icons.chat_bubble_outline),
      label: Text(record.hasRecipientComment ? '编辑回应' : '写回应'),
      onPressed: () => showRecipientCommentEditorDialog(
        context: context,
        initialText: record.recipientComment,
        onCommit: onCommit,
      ),
    ),
  ];
}

/// 编辑回应：保存时若正文为空则清除回应（RPC 置 null）。
Future<void> showRecipientCommentEditorDialog({
  required BuildContext context,
  String? initialText,
  required Future<void> Function(String? trimmedOrNull) onCommit,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _RecipientCommentEditorDialog(
      initialText: initialText,
      onCommit: onCommit,
    ),
  );
}

class _RecipientCommentEditorDialog extends StatefulWidget {
  const _RecipientCommentEditorDialog({
    required this.initialText,
    required this.onCommit,
  });

  final String? initialText;
  final Future<void> Function(String? trimmedOrNull) onCommit;

  @override
  State<_RecipientCommentEditorDialog> createState() => _RecipientCommentEditorDialogState();
}

class _RecipientCommentEditorDialogState extends State<_RecipientCommentEditorDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText?.trim() ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('我的回应'),
      content: TextField(
        controller: _controller,
        maxLines: 5,
        maxLength: kRecipientCommentMaxLen,
        decoration: const InputDecoration(
          hintText: '记录你想对 TA 说的话…',
          alignLabelWithHint: true,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            final t = _controller.text.trim();
            Navigator.of(context).pop();
            await widget.onCommit(t.isEmpty ? null : t);
          },
          child: const Text('保存'),
        ),
      ],
    );
  }
}
