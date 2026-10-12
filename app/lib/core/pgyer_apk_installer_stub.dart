import 'package:love_story/core/pgyer_update.dart';

/// Browsers cannot install Android packages; the update page is the fallback.
Future<String?> downloadAndInstallApk(
  PgyerUpdateInfo info, {
  void Function(double progress, int received, int? total, Duration? eta)?
      onProgress,
}) async =>
    null;
