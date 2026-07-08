import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:love_story/core/theme.dart';
import 'package:provider/provider.dart';
import 'package:love_story/features/couple/couple_service.dart';

/// 未登录时，点击新建/保存类操作后弹出「请先登录」引导
void showLoginPrompt(BuildContext context, {String? message}) {
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('请先登录'),
      content: Text(
        message ?? '未登录无法保存数据到云端，请先登录后再操作。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('稍后'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(ctx);
            context.go('/login');
          },
          icon: const Icon(Icons.login, size: 20),
          label: const Text('去登录'),
        ),
      ],
    ),
  );
}

/// 对方未关联时，点击不可用操作后弹出「关联情侣空间」引导：
/// 支持「分享邀请码给 TA」或「输入 TA 的邀请码」
void showBindPrompt(BuildContext context) {
  final couple = context.read<CoupleService>();
  final hasInviteCode = couple.inviteCode != null && couple.inviteCode!.isNotEmpty;

  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('关联情侣空间'),
      content: const SingleChildScrollView(
        child: Text(
          '对方尚未关联账号，部分功能暂不可用（如记积分、兑换等）。\n\n'
          '你可以：\n'
          '· 把邀请码分享给 TA，等 TA 注册/登录后输入邀请码完成关联；\n'
          '· 或输入 TA 的邀请码，加入已有空间。',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('稍后'),
        ),
        if (hasInviteCode)
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: couple.inviteCode!));
              Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('邀请码已复制到剪贴板，可粘贴发给 TA')),
                );
              }
            },
            icon: const Icon(Icons.copy, size: 20),
            label: const Text('复制邀请码给 TA'),
          )
        else
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              context.go('/bind');
            },
            icon: const Icon(Icons.add_circle_outline, size: 20),
            label: const Text('创建空间获取邀请码'),
          ),
        FilledButton.icon(
          onPressed: () {
            Navigator.pop(ctx);
            context.go('/bind');
          },
          icon: const Icon(Icons.link, size: 20),
          label: const Text('输入 TA 的邀请码'),
        ),
      ],
    ),
  );
}
