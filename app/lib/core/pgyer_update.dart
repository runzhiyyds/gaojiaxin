import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:love_story/core/config.dart';
import 'package:love_story/core/pgyer_apk_installer.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// 蒲公英「检测 App 是否有更新」返回的新版本信息
class PgyerUpdateInfo {
  PgyerUpdateInfo({
    required this.buildVersion,
    required this.downloadUrl,
    required this.appPageUrl,
    this.updateDescription,
    this.needForceUpdate = false,
  });

  final String buildVersion;
  final String downloadUrl;
  final String appPageUrl;
  final String? updateDescription;
  final bool needForceUpdate;
}

/// 使用蒲公英 API 检查是否有新版本；未配置 appKey/apiKey 时返回 null（不弹更新）。
Future<PgyerUpdateInfo?> checkPgyerUpdate() async {
  if (Config.pgyerAppKey.isEmpty || Config.pgyerApiKey.isEmpty) {
    return null;
  }
  final packageInfo = await PackageInfo.fromPlatform();
  final currentVersion = packageInfo.version;
  final buildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

  final uri = Uri.parse('https://api.pgyer.com/apiv2/app/check');
  final body = <String, String>{
    '_api_key': Config.pgyerApiKey,
    'appKey': Config.pgyerAppKey,
    'buildVersion': currentVersion,
    'buildBuildVersion': buildNumber.toString(),
  };

  try {
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: body,
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body) as Map<String, dynamic>?;
    if (json == null) return null;

    final data = json['data'] as Map<String, dynamic>? ?? json;
    final haveNew = data['buildHaveNewVersion'] as bool? ?? false;
    if (!haveNew) return null;

    final downloadUrl = data['downloadURL'] as String? ?? '';
    final appPageUrl = data['appURl'] as String? ?? '';
    if (downloadUrl.isEmpty && appPageUrl.isEmpty) return null;

    final serverVersion = data['buildVersion'] as String? ?? '';
    final serverBuildNo = data['buildVersionNo']?.toString() ?? '';
    final serverVersionCode = int.tryParse(serverBuildNo) ?? 0;
    if (!_isServerVersionNewer(
      currentVersion: currentVersion,
      currentBuildNumber: buildNumber,
      serverVersion: serverVersion,
      serverVersionCode: serverVersionCode,
    )) {
      return null;
    }

    return PgyerUpdateInfo(
      buildVersion: data['buildVersion'] as String? ?? '',
      downloadUrl: downloadUrl,
      appPageUrl: appPageUrl.isNotEmpty ? appPageUrl : downloadUrl,
      updateDescription: data['buildUpdateDescription'] as String?,
      needForceUpdate: data['needForceUpdate'] as bool? ?? false,
    );
  } catch (_) {
    return null;
  }
}

/// 比较服务端版本是否严格大于当前版本，避免「已是最新仍提示更新」。
bool _isServerVersionNewer({
  required String currentVersion,
  required int currentBuildNumber,
  required String serverVersion,
  required int serverVersionCode,
}) {
  final cv = _parseVersionParts(currentVersion);
  final sv = _parseVersionParts(serverVersion);
  for (var i = 0; i < cv.length && i < sv.length; i++) {
    if (sv[i] > cv[i]) return true;
    if (sv[i] < cv[i]) return false;
  }
  if (sv.length > cv.length) return true;
  if (sv.length < cv.length) return false;
  return serverVersionCode > currentBuildNumber;
}

List<int> _parseVersionParts(String version) {
  return version
      .split(RegExp(r'[.\-+]'))
      .map((s) => int.tryParse(s.trim()) ?? 0)
      .toList();
}

/// 显示蒲公英更新弹窗；[context] 用于弹窗与 SnackBar。[openInApp] 为 true 时使用应用内浏览器打开下载页。
Future<void> showPgyerUpdateDialog(
  BuildContext context,
  PgyerUpdateInfo info, {
  bool openInApp = true,
}) async {
  final openUrl = info.appPageUrl.isNotEmpty ? info.appPageUrl : info.downloadUrl;
  final mode = openInApp ? LaunchMode.inAppWebView : LaunchMode.externalApplication;
  await showDialog<void>(
    context: context,
    barrierDismissible: !info.needForceUpdate,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('发现新版本'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (info.buildVersion.isNotEmpty)
                Text(
                  '新版本：${info.buildVersion}',
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
              if (info.updateDescription != null && info.updateDescription!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  info.updateDescription!,
                  style: Theme.of(ctx).textTheme.bodyMedium,
                ),
              ],
              if (info.needForceUpdate)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    '此版本为强制更新，请更新后继续使用。',
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                          color: Theme.of(ctx).colorScheme.error,
                        ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (!info.needForceUpdate)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('稍后'),
            ),
          FilledButton(
            onPressed: () async {
              if (openUrl.isNotEmpty) {
                final uri = Uri.tryParse(openUrl);
                if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
                  try {
                    await launchUrl(uri, mode: mode);
                  } catch (_) {}
                }
                if (ctx.mounted) Navigator.of(ctx).pop();
                if (ctx.mounted && openUrl.isNotEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('请在打开的页面中下载并安装新版本')),
                  );
                }
              } else {
                Navigator.of(ctx).pop();
              }
            },
            child: const Text('立即更新'),
          ),
        ],
      );
    },
  );
}

/// 应用内下载并安装的更新弹窗：先尝试 Android 内下载+安装，失败则降级为「前往蒲公英下载」。
/// [openInAppForFallback] 为 true 时降级使用应用内 WebView 打开下载页，否则用外部浏览器。
/// 返回 true 表示用户选择了更新（立即更新/前往下载/已调起安装），false 表示点了「稍后」。
Future<bool> showPgyerUpdateDialogWithInAppInstall(
  BuildContext context,
  PgyerUpdateInfo info, {
  bool openInAppForFallback = false,
}) async {
  final openUrl = info.appPageUrl.isNotEmpty ? info.appPageUrl : info.downloadUrl;
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: !info.needForceUpdate,
    builder: (ctx) => PopScope(
      canPop: !info.needForceUpdate,
      child: _PgyerUpdateDialogWithInstallContent(
      info: info,
      openUrl: openUrl,
      openInAppForFallback: openInAppForFallback,
      ),
    ),
  );
  return result ?? false;
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _formatEta(Duration eta) {
  if (eta.inSeconds < 60) return '约 ${eta.inSeconds} 秒';
  if (eta.inMinutes < 60) return '约 ${eta.inMinutes} 分钟';
  return '约 ${eta.inHours} 小时';
}

class _PgyerUpdateDialogWithInstallContent extends StatefulWidget {
  const _PgyerUpdateDialogWithInstallContent({
    required this.info,
    required this.openUrl,
    required this.openInAppForFallback,
  });

  final PgyerUpdateInfo info;
  final String openUrl;
  final bool openInAppForFallback;

  @override
  State<_PgyerUpdateDialogWithInstallContent> createState() =>
      _PgyerUpdateDialogWithInstallContentState();
}

enum _PgyerDialogState { idle, downloading, failed }

class _PgyerUpdateDialogWithInstallContentState
    extends State<_PgyerUpdateDialogWithInstallContent> {
  _PgyerDialogState _state = _PgyerDialogState.idle;
  double _progress = 0.0;
  int _received = 0;
  int? _total;
  Duration? _eta;

  void _onTapUpdate() {
    final canInAppInstall = Platform.isAndroid &&
        widget.info.downloadUrl.trim().isNotEmpty &&
        Uri.tryParse(widget.info.downloadUrl) != null;

    if (!canInAppInstall) {
      _openFallbackAndPop();
      return;
    }

    setState(() {
      _state = _PgyerDialogState.downloading;
      _progress = 0.0;
      _received = 0;
      _total = null;
      _eta = null;
    });

    downloadAndInstallApk(
      widget.info,
      onProgress: (progress, received, total, eta) {
        if (!mounted) return;
        setState(() {
          _progress = progress;
          _received = received;
          _total = total;
          _eta = eta;
        });
      },
    ).then((result) {
      if (!mounted) return;
      if (result != null) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请完成安装后重新打开应用')),
        );
      } else {
        setState(() => _state = _PgyerDialogState.failed);
      }
    });
  }

  Future<void> _openFallbackAndPop() async {
    if (widget.openUrl.isEmpty) {
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    final uri = Uri.tryParse(widget.openUrl);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      try {
        final mode = widget.openInAppForFallback
            ? LaunchMode.inAppWebView
            : LaunchMode.externalApplication;
        await launchUrl(uri, mode: mode);
      } catch (_) {}
    }
    if (mounted) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请在打开的页面中下载并安装新版本')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_state == _PgyerDialogState.failed) {
      return AlertDialog(
        title: const Text('发现新版本'),
        content: const Text(
          '自动更新失败，请手动前往蒲公英下载。',
          style: TextStyle(fontSize: 15),
        ),
        actions: [
          FilledButton(
            onPressed: () async {
              await _openFallbackAndPop();
            },
            child: const Text('前往下载'),
          ),
        ],
      );
    }

    if (_state == _PgyerDialogState.downloading) {
      return AlertDialog(
        title: const Text('发现新版本'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('正在下载…', style: TextStyle(fontSize: 15)),
              const SizedBox(height: 16),
              if (_total != null && _total! > 0)
                LinearProgressIndicator(value: _progress)
              else
                const LinearProgressIndicator(),
              const SizedBox(height: 12),
              Text(
                _total != null
                    ? '${_formatBytes(_received)} / ${_formatBytes(_total!)}'
                    : '已下载 ${_formatBytes(_received)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_eta != null) ...[
                const SizedBox(height: 4),
                Text(
                  _formatEta(_eta!),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return AlertDialog(
      title: const Text('发现新版本'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.info.buildVersion.isNotEmpty)
              Text(
                '新版本：${widget.info.buildVersion}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            if (widget.info.updateDescription != null &&
                widget.info.updateDescription!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                widget.info.updateDescription!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
            if (widget.info.needForceUpdate)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  '此版本为强制更新，请更新后继续使用。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.error,
                      ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        if (!widget.info.needForceUpdate)
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('稍后'),
          ),
        FilledButton(
          onPressed: _onTapUpdate,
          child: const Text('立即更新'),
        ),
      ],
    );
  }
}
