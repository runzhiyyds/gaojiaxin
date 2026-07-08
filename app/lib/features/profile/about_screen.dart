import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:love_story/core/theme.dart';
import 'package:love_story/core/pgyer_update.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  static const String _contactPhoneWechat = '18613544331';

  String _versionText = '版本 --';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _versionText = '版本 ${info.version}+${info.buildNumber}');
    }
  }

  Future<void> _checkUpdate() async {
    final info = await checkPgyerUpdate();
    if (!mounted) return;
    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('当前已是最新版本')),
      );
    } else {
      await showPgyerUpdateDialogWithInAppInstall(context, info, openInAppForFallback: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('关于'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 24),
          Text(
          '爱情心意值',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: AppTheme.primaryDark,
                  fontWeight: FontWeight.bold,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
          '与 TA 一起记录、兑换爱情心意值',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: AppTheme.secondary,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Text(
            _versionText,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.system_update),
                  title: const Text('检查版本更新'),
                  subtitle: Text(
                    '支持应用内下载安装，失败时引导至蒲公英',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.secondary,
                        ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: _checkUpdate,
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.contact_phone),
                  title: const Text('联系我们'),
                  subtitle: Text(
                    '作者电话/微信：$_contactPhoneWechat',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.secondary,
                        ),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.copy),
                    tooltip: '复制',
                    onPressed: () async {
                      await Clipboard.setData(const ClipboardData(text: _contactPhoneWechat));
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('已复制到剪贴板')),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
