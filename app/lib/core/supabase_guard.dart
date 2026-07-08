import 'dart:async';

/// 为 Supabase 调用增加统一超时与可选重试（仅读操作），弱网下减少挂起与一次失败即放弃。
const _timeout = Duration(seconds: 20);
const _maxRetries = 2;

/// 执行 [fn]；[isRead] 为 true 时失败会重试最多 [_maxRetries] 次，指数退避（1s、2s）。
Future<T> withSupabaseCall<T>(
  Future<T> Function() fn, {
  bool isRead = false,
}) async {
  if (isRead) {
    for (var attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        return await fn().timeout(_timeout);
      } catch (e) {
        if (attempt == _maxRetries) rethrow;
        await Future<void>.delayed(
          Duration(seconds: 1 << attempt),
        );
      }
    }
  }
  return await fn().timeout(_timeout);
}
