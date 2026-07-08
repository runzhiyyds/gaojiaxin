import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:love_story/core/theme.dart';
import 'package:provider/provider.dart';
import 'package:love_story/features/couple/couple_service.dart';
import 'package:love_story/features/points/points_repository.dart';

class BindScreen extends StatefulWidget {
  const BindScreen({super.key});

  @override
  State<BindScreen> createState() => _BindScreenState();
}

class _BindScreenState extends State<BindScreen> {
  final _codeController = TextEditingController();
  bool _creating = false;
  bool _joining = false;
  bool _hasNavigatedToHome = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CoupleService>().refresh();
      _startPolling();
    });
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) async {
      if (!mounted) return;
      if (_creating || _joining) return;
      final couple = context.read<CoupleService>();
      if (couple.isBound && !couple.hasPartner) {
        await couple.refresh();
      }
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _createSpace() async {
    setState(() => _creating = true);
    final ok = await context.read<CoupleService>().createSpace();
    if (!mounted) return;
    if (ok) {
      final spaceId = context.read<CoupleService>().coupleSpaceId;
      if (spaceId != null) {
        try {
          await context.read<PointsRepository>().createItem(
                coupleSpaceId: spaceId,
                name: '日常',
                iconName: 'star',
                pointsPerUnit: 1,
                isDefault: true,
              );
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() => _creating = false);
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('邀请码已生成，分享给 TA 吧')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<CoupleService>().error ?? '创建失败'),
        ),
      );
    }
  }

  Future<void> _joinSpace() async {
    if (_codeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入邀请码')),
      );
      return;
    }
    setState(() => _joining = true);
    final ok = await context.read<CoupleService>().joinWithCode(_codeController.text);
    if (!mounted) return;
    setState(() => _joining = false);
    if (ok) {
      context.go('/home');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.read<CoupleService>().error ?? '绑定失败'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<CoupleService>(
      builder: (context, couple, _) {
        if (couple.loading) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        if (couple.isBound && couple.hasPartner) {
          if (!_hasNavigatedToHome) {
            _hasNavigatedToHome = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) context.go('/home');
            });
          }
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('关联情侣空间'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/home'),
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 48),
                  Text(
                    couple.isBound && couple.inviteCode != null ? '等待 TA 关联' : '关联情侣空间',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppTheme.primaryDark,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    couple.inviteCode != null
                        ? '将下方邀请码发给 TA，TA 注册/登录后输入即可完成绑定'
                        : '创建空间生成邀请码发给 TA，或输入 TA 的邀请码加入',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.secondary,
                        ),
                  ),
                  const SizedBox(height: 40),

                  if (couple.inviteCode != null) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            const Text('你的邀请码'),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  couple.inviteCode!,
                                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                        letterSpacing: 8,
                                        fontWeight: FontWeight.bold,
                                        color: AppTheme.primary,
                                      ),
                                ),
                                const SizedBox(width: 8),
                                IconButton.filled(
                                  tooltip: '复制邀请码',
                                  icon: const Icon(Icons.copy),
                                  onPressed: () async {
                                    await Clipboard.setData(ClipboardData(text: couple.inviteCode!));
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('已复制到剪贴板')),
                                      );
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '邀请码一次性有效，TA 输入后即失效',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (couple.isBound) ...[
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: () => context.go('/home'),
                                icon: const Icon(Icons.home_outlined, size: 20),
                                label: const Text('返回首页'),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ] else if (couple.isBound) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          children: [
                            Text(
                              '你已在情侣空间中',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '无法在此处输入邀请码。若需更换空间，请先在「我的」-「设置」中退出当前空间。',
                              style: Theme.of(context).textTheme.bodySmall,
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: () => context.go('/home'),
                              icon: const Icon(Icons.home_outlined, size: 20),
                              label: const Text('返回首页'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    FilledButton.icon(
                      onPressed: _creating ? null : _createSpace,
                      icon: _creating
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_circle_outline),
                      label: Text(_creating ? '创建中…' : '创建情侣空间'),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(child: Divider(color: Colors.grey.shade400)),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text(
                            '或输入 TA 的邀请码',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Expanded(child: Divider(color: Colors.grey.shade400)),
                      ],
                    ),
                    const SizedBox(height: 24),
                    TextField(
                      controller: _codeController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: const InputDecoration(
                        labelText: '邀请码',
                        hintText: '6 位大写字母或数字',
                        prefixIcon: Icon(Icons.link),
                      ),
                      maxLength: 6,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _joining ? null : _joinSpace,
                      child: _joining
                          ? const SizedBox(
                              height: 22,
                              width: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('绑定'),
                    ),
                    const SizedBox(height: 16),
                    OutlinedButton.icon(
                      onPressed: () => context.go('/home'),
                      icon: const Icon(Icons.home_outlined, size: 20),
                      label: const Text('先进入主页，稍后再绑定'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
