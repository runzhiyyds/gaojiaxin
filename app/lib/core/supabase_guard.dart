import 'dart:async';
import 'package:love_story/core/user_error.dart';

/// The HTTP transport cancels requests at 12s. This guard also bounds custom
/// calls. Retry a transient read failure once; never repeat timed-out or write
/// requests, permission errors, or validation errors.
Future<T> withSupabaseCall<T>(
  Future<T> Function() fn, {
  bool isRead = false,
}) async {
  try {
    return await fn().timeout(const Duration(seconds: 14));
  } catch (error) {
    if (!isRead || !isNetworkFailure(error) || isNetworkTimeout(error)) rethrow;
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return await fn().timeout(const Duration(seconds: 14));
  }
}
