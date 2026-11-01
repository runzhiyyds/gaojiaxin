import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:love_story/core/theme.dart';
import 'package:provider/provider.dart';
import 'package:love_story/features/auth/auth_service.dart';
import 'package:love_story/features/couple/couple_service.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('我的')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Opacity(
              opacity: 0.6,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.grey.shade300,
                        child: Icon(Icons.person_off_outlined, size: 32, color: Colors.grey.shade600),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '请先登录',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    color: AppTheme.secondary,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '登录后可关联情侣空间、记录心意值、管理心意商城',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.secondary,
                                  ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 12,
                              children: [
                                FilledButton.icon(
                                  onPressed: () => context.go('/login'),
                                  icon: const Icon(Icons.login, size: 18),
                                  label: const Text('去登录'),
                                ),
                                TextButton(
                                  onPressed: () => context.go('/register'),
                                  child: const Text('去注册'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('设置'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/home/profile/settings'),
            ),
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('关于'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/home/profile/about'),
            ),
          ],
        ),
      );
    }

    final couple = context.watch<CoupleService>();
    final email = auth.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 32,
                    child: Icon(Icons.person, size: 32),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          couple.myProfile?['nickname']?.toString() ?? '我',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.secondary,
                              ),
                        ),
                        if (couple.partnerProfile != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '与 ${couple.partnerProfile!['nickname'] ?? 'TA'} 已绑定',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.primary,
                                  ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.favorite_border),
            title: const Text('情侣空间'),
            subtitle: Text(
              couple.isBound
                  ? '已与 ${couple.partnerProfile?['nickname'] ?? 'TA'} 绑定'
                  : '尚未绑定，去创建或加入情侣空间',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.secondary,
                  ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/bind'),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text('设置'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/home/profile/settings'),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/home/profile/about'),
          ),
        ],
      ),
    );
  }
}
