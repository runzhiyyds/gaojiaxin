import 'dart:io';

import 'package:apk_sideload/install_apk.dart';
import 'package:dio/dio.dart';
import 'package:love_story/core/pgyer_update.dart';
import 'package:path_provider/path_provider.dart';

/// 应用内下载并安装蒲公英 APK（仅 Android）。
/// 成功返回本地 APK 路径，失败返回 null，由调用方走降级逻辑（如打开网页）。
/// [onProgress]：progress 0.0~1.0，total 未知时为 null；eta 为预计剩余时间，未知时为 null。
Future<String?> downloadAndInstallApk(
  PgyerUpdateInfo info, {
  void Function(double progress, int received, int? total, Duration? eta)? onProgress,
}) async {
  if (!Platform.isAndroid) return null;
  final url = info.downloadUrl.trim();
  if (url.isEmpty) return null;
  final uri = Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) return null;

  final dir = await getTemporaryDirectory();
  final filePath = '${dir.path}/pgyer_update_${DateTime.now().millisecondsSinceEpoch}.apk';
  final file = File(filePath);

  try {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 10),
      followRedirects: true,
      maxRedirects: 5,
    ));

    int received = 0;
    int? total;
    final stopwatch = Stopwatch()..start();
    int lastUpdate = 0;
    const minProgressIntervalMs = 200;

    await dio.download(
      url,
      filePath,
      onReceiveProgress: (int count, int? totalBytes) {
        received = count;
        total = totalBytes;
        final now = DateTime.now().millisecondsSinceEpoch;
        if (now - lastUpdate < minProgressIntervalMs && totalBytes != null) return;
        lastUpdate = now;

        double progress = 0.0;
        if (totalBytes != null && totalBytes > 0) {
          progress = count / totalBytes;
          if (progress > 1.0) progress = 1.0;
        }

        Duration? eta;
        if (totalBytes != null && totalBytes > count && stopwatch.elapsedMilliseconds > 500) {
          final speed = count / (stopwatch.elapsedMilliseconds / 1000);
          if (speed > 0) {
            final remainingSeconds = (totalBytes - count) / speed;
            if (remainingSeconds.isFinite && remainingSeconds > 0) {
              eta = Duration(seconds: remainingSeconds.round());
            }
          }
        }
        onProgress?.call(progress, count, totalBytes, eta);
      },
      options: Options(
        responseType: ResponseType.bytes,
        validateStatus: (status) => status != null && status >= 200 && status < 300,
      ),
    );

    if (!await file.exists() || await file.length() == 0) return null;

    await InstallApk().installApk(filePath);
    return filePath;
  } catch (_) {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
    return null;
  }
}
