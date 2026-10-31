import 'package:flutter/material.dart';

/// Keep failures distinct from empty data, with a reachable recovery action.
class LoadFeedback extends StatelessWidget {
  const LoadFeedback({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.cloud_off_outlined, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('重新加载')),
          ]),
        ),
      );
}

class RefreshNotice extends StatelessWidget {
  const RefreshNotice(
      {super.key,
      required this.message,
      required this.onRetry,
      this.autoRetrying = false,
      this.cachedReadOnly = false});
  final String message;
  final VoidCallback onRetry;
  final bool autoRetrying;
  final bool cachedReadOnly;

  String get _displayMessage {
    if (autoRetrying) {
      return cachedReadOnly
          ? '后台自动重试中。你可继续查看，也可检查网络；同步成功后可编辑。'
          : '后台自动重试中，你也可以检查网络。';
    }
    if (message.contains('无法连接服务') || message.contains('连接服务超时')) {
      return '网络不稳定，暂未同步';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Expanded(child: Text(_displayMessage)),
            TextButton(
              onPressed: onRetry,
              child: Text(autoRetrying ? '立即重试' : '重试'),
            ),
          ]),
        ),
      );
}
