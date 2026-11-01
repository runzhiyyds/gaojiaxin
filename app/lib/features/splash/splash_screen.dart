import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:love_story/core/theme.dart';
import 'package:provider/provider.dart';
import 'package:love_story/features/auth/auth_service.dart';

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

  void _redirect() {
    if (!mounted) return;
    // Supabase.initialize has already restored the persisted session. Network
    // sync and updates continue on the destination page, never on the splash.
    final auth = context.read<AuthService>();
    context.go(auth.isLoggedIn ? '/home/points' : '/login');
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
