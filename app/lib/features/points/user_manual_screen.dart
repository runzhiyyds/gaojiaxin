import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:love_story/core/theme.dart';
import 'package:love_story/core/settings_prefs.dart';

/// 使用手册：邀请码、爱情心意值、兑换余额、心意商城（情侣空间共管、预设与品类、1 心意值≈1 元，后续可自定义）。
/// [isFirstTime] 为 true 时底部按钮为「知道了」并会写入“已读”标记；否则为「关闭」仅关闭页面。
class UserManualScreen extends StatelessWidget {
  const UserManualScreen({super.key, this.isFirstTime = false});

  final bool isFirstTime;

  Future<void> _close(BuildContext context) async {
    if (isFirstTime) await SettingsPrefs.setHasSeenUserManual(true);
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('使用手册'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _close(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Section(
              icon: Icons.link,
              title: '邀请码怎么用？',
              children: [
                '· 创建情侣空间后会生成你的 **6 位邀请码**，分享给 TA。',
                '· TA 注册/登录后，在「关联情侣空间」页输入你的邀请码，即可完成绑定。',
                '· 你也可以输入 TA 的邀请码，加入 TA 创建的空间。',
                '· 绑定成功后，两人共用同一空间，才能记录心意值、使用商城。',
              ],
            ),
            const SizedBox(height: 24),
            _Section(
              icon: Icons.star,
              title: '爱情心意值（两套体系）',
              children: [
                '**我的爱情心意值**：我获得的心意累计（TA 给我记的心意值）。',
                '**TA 的爱情心意值**：对方获得的心意累计（我通过「记一笔」给 TA 加的心意值）。',
                '· 「记一笔」是 **给 TA 加心意值**，记在 TA 的爱情心意值里。',
                '· **普通模式**：选小额/中额/大额档位，系统为 TA 随机种下心意（支持一位小数），并悄悄回馈你一点。',
                '· **霸总模式**：自由输入心意值，只给 TA 加，不给自己回馈，适合纯粹表达心意。',
                '· 心意 Tab 上会同时显示「我的」和「TA」的心意值与兑换余额。',
              ],
            ),
            const SizedBox(height: 24),
            _Section(
              icon: Icons.favorite_border,
              title: '爱情旅程',
              children: [
                '· 在 **爱情旅程** Tab 可查看双方记下的心意事件，以时间轴展示。',
                '· 左侧为你记下的，右侧为 TA 记下的，支持时间范围筛选与加载更多。',
              ],
            ),
            const SizedBox(height: 24),
            _Section(
              icon: Icons.account_balance_wallet_outlined,
              title: '兑换余额（我的 / TA）',
              children: [
                '**我的兑换余额** = 我的爱情心意值 − 我已在商城里兑换消耗的心意值。',
                '**TA 的兑换余额** = TA 的爱情心意值 − TA 已兑换消耗的心意值。',
                '· 在「心意商城」里，你用 **自己的兑换余额** 兑换空间内的任意兑换项，扣的是你的心意值。',
              ],
            ),
            const SizedBox(height: 24),
            _Section(
              icon: Icons.shopping_bag_outlined,
              title: '心意商城怎么用？',
              children: [
                '· **情侣空间内双方共管**：商城展示的是空间内全部可兑换项，你和 TA 都可以在「管理商城」里对任意项进行新增、修改、删除。',
                '· **添加方式**：可手动添加（名称、所需心意值、品类等），也可从「从预设添加」里按品类选择（知识付费、科技、虚拟卡、书籍、礼物等），一键加入空间。',
                '· **心意值与价值**：1 心意值 ≈ 1 元，兑换项所需心意值按约定价值配置，可自行修改。',
                '· 你用 **我的兑换余额** 兑换任意一项，扣的是你的心意值；兑换记录在商城页右上角「兑换记录」中查看。',
              ],
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: () => _close(context),
              child: Text(isFirstTime ? '知道了' : '关闭'),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.children,
  });

  final IconData icon;
  final String title;
  final List<String> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppTheme.primary, size: 24),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryDark,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...children.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  line.replaceAll('**', ''),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        height: 1.4,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
