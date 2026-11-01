import 'dart:async';

/// Schedules page-level retries for safe read-only refreshes.
///
/// Writes and authentication must never use this controller: a timed-out
/// request may already have reached the server and replaying it can duplicate
/// or unexpectedly change data.
class BackgroundReadRetry {
  BackgroundReadRetry({List<Duration>? delays})
      : _delays = delays ??
            const [
              Duration(seconds: 3),
              Duration(seconds: 10),
              Duration(seconds: 30),
              Duration(seconds: 60),
            ];

  final List<Duration> _delays;
  Timer? _timer;
  int _failureCount = 0;

  bool get isScheduled => _timer?.isActive ?? false;

  void schedule(
    Future<void> Function() retry, {
    void Function()? onStateChanged,
  }) {
    if (isScheduled || _delays.isEmpty) return;
    final delayIndex = _failureCount.clamp(0, _delays.length - 1);
    final delay = _delays[delayIndex];
    _failureCount++;
    _timer = Timer(delay, () async {
      _timer = null;
      onStateChanged?.call();
      await retry();
    });
    onStateChanged?.call();
  }

  void reset({void Function()? onStateChanged}) {
    final changed = isScheduled || _failureCount != 0;
    _timer?.cancel();
    _timer = null;
    _failureCount = 0;
    if (changed) onStateChanged?.call();
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
