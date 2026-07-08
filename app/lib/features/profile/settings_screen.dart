import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:love_story/core/settings_prefs.dart';
import 'package:love_story/features/auth/auth_service.dart';
import 'package:love_story/features/couple/couple_service.dart';
import 'package:love_story/core/notifications/notification_service.dart';
import 'package:provider/provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _cycleStartWeekday = 1;
  bool _notificationEnabled = true;
  bool _loading = true;

  static const _weekdayLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final weekday = await SettingsPrefs.getCycleStartWeekday();
    final notification = await SettingsPrefs.getNotificationEnabled();
    if (mounted) {
      setState(() {
        _cycleStartWeekday = weekday;
        _notificationEnabled = notification;
        _loading = false;
      });
    }
  }

  Future<void> _pickCycleStart() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('周期起始日'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(7, (i) {
            final w = i + 1;
            return RadioListTile<int>(
              title: Text(_weekdayLabels[i]),
              value: w,
              groupValue: _cycleStartWeekday,
              onChanged: (v) => Navigator.pop(ctx, v),
            );
          }),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await SettingsPrefs.setCycleStartWeekday(picked);
    if (mounted) setState(() => _cycleStartWeekday = picked);
  }

  Future<void> _setNotification(bool value) async {
    await SettingsPrefs.setNotificationEnabled(value);
    if (mounted) setState(() => _notificationEnabled = value);
    if (value) {
      await NotificationService.instance.requestPermissionsIfNeeded();
    }
  }

  Future<void> _logout() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出登录'),
        content: const Text('退出后需要重新输入账号密码才能登录，确定要退出当前账号吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('退出登录'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await context.read<AuthService>().signOut();
    if (!mounted) return;
    context.go('/login');
  }

  Future<void> _showAdvancedActions() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        final isBound = context.read<CoupleService>().isBound;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '更多账号与空间操作',
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '以下操作影响较大，请确认后再继续。',
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                if (isBound)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.link_off, color: Theme.of(sheetContext).colorScheme.error),
                    title: const Text('退出情侣空间'),
                    subtitle: const Text('退出后需重新创建或输入邀请码才能再次关联'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _leaveSpace();
                    },
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.logout, color: Theme.of(sheetContext).colorScheme.error),
                  title: const Text('退出登录'),
                  subtitle: const Text('清除当前账号登录状态，返回登录页'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _logout();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _leaveSpace() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('退出情侣空间'),
        content: const Text(
          '退出后需重新创建或输入邀请码才能再次关联。确定退出？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final success = await context.read<CoupleService>().leaveSpace();
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已退出情侣空间')),
      );
      // 退出后回到「我的」页，由用户自行选择是否重新进入「情侣空间」页面
      context.go('/home/profile');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.read<CoupleService>().error ?? '操作失败')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isBound = context.watch<CoupleService>().isBound;
    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('设置'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: ListView(
        children: [
          ListTile(
            title: const Text('周期起始日'),
            subtitle: Text(_weekdayLabels[_cycleStartWeekday - 1]),
            trailing: const Icon(Icons.chevron_right),
            onTap: _pickCycleStart,
          ),
          SwitchListTile(
            title: const Text('推送通知'),
            subtitle: const Text('开启后可接收 TA 给你加分、兑换成功等提醒'),
            value: _notificationEnabled,
            onChanged: _setNotification,
          ),
          const Divider(),
          ListTile(
            title: const Text('更多账号与空间操作'),
            subtitle: Text(
              isBound ? '包含退出情侣空间、退出登录等高风险操作' : '包含退出登录等操作',
            ),
            leading: const Icon(Icons.admin_panel_settings_outlined),
            trailing: const Icon(Icons.chevron_right),
            onTap: _showAdvancedActions,
          ),
        ],
      ),
    );
  }
}
