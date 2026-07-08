import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:love_story/core/theme.dart';
import 'package:love_story/core/pgyer_update.dart';
import 'package:provider/provider.dart';
import 'package:love_story/features/auth/auth_service.dart';
import 'package:love_story/features/couple/couple_service.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart' show ShorebirdUpdater, UpdateStatus;

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _redirect());
  }

  Future<void> _redirect() async {
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    // Shorebird 检查可能挂起（非 Shorebird 构建或网络问题），加超时跳过
    try {
      await Future.any([
        () async {
          final updater = ShorebirdUpdater();
          final status = await updater.checkForUpdate();
          if (status == UpdateStatus.outdated) {
            await updater.update();
          }
        }(),
        Future.delayed(const Duration(seconds: 5)),
      ]);
    } catch (_) {}
    if (!mounted) return;
    try {
      await _doRedirect().timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TimeoutException('启动流程超时'),
      );
    } on TimeoutException {
      if (kDebugMode) {
        debugPrint('SplashScreen: 启动流程超时，强制跳转');
      }
      if (!mounted) return;
      _navigateByAuthState();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('SplashScreen _redirect error: $e\n$st');
      }
      if (!mounted) return;
      _navigateByAuthState();
    }
  }

  Future<void> _doRedirect() async {
    final updateInfo = await checkPgyerUpdate();
    if (mounted && updateInfo != null) {
      final go = await showPgyerUpdateDialogWithInAppInstall(
        context,
        updateInfo,
        openInAppForFallback: false,
      );
      if (!go && updateInfo.needForceUpdate) {
        if (mounted) context.go('/login');
        return;
      }
    }
    if (!mounted) return;
    final auth = context.read<AuthService>();
    if (!auth.isLoggedIn) {
      for (var i = 0; i < 3 && !auth.isLoggedIn; i++) {
        try {
          await auth.autoSignIn().timeout(const Duration(seconds: 10));
        } catch (_) {}
        if (!mounted) return;
        if (auth.isLoggedIn) break;
        await Future.delayed(const Duration(milliseconds: 500));
      }
    }
    if (!mounted) return;
    try {
      await context.read<CoupleService>().refresh().timeout(const Duration(seconds: 10));
    } catch (_) {}
    if (!mounted) return;
    final couple = context.read<CoupleService>();
    if (auth.isLoggedIn) {
      if (couple.isBound) {
        context.go('/home');
      } else {
        context.go('/bind');
      }
    } else {
      context.go('/login');
    }
  }

  void _navigateByAuthState() {
    if (!mounted) return;
    try {
      final auth = context.read<AuthService>();
      if (auth.isLoggedIn) {
        context.go('/home');
      } else {
        context.go('/login');
      }
    } catch (_) {
      context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFFDF6F8),
              Color(0xFFF5E0E8),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 80),
              Text(
                '爱情积分',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      color: AppTheme.primaryDark,
                      fontWeight: FontWeight.bold,
                      height: 1.3,
                    ),
              ),
              const SizedBox(height: 12),
              Text(
                '与 TA 一起记录、兑换爱情积分',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppTheme.secondary,
                    ),
              ),
              const Spacer(),
              const CircularProgressIndicator(
                color: AppTheme.primary,
                strokeWidth: 2,
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}
