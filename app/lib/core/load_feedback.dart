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
      {super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            Expanded(child: Text('刷新失败，以下为上次加载的内容。$message')),
            TextButton(onPressed: onRetry, child: const Text('重试')),
          ]),
        ),
      );
}
