import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:love_story/core/theme.dart';
import 'package:love_story/core/settings_prefs.dart';
import 'package:provider/provider.dart';
import 'package:love_story/features/auth/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;
  bool _registered = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    _error = null;
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      final email = _emailController.text.trim();
      await context.read<AuthService>().signUp(
            email: email,
            password: _passwordController.text,
            nickname: _nicknameController.text.trim(),
          );
      await SettingsPrefs.setPendingConfirmEmail(email);
      await SettingsPrefs.setShowManualOnNextLogin(true);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _registered = true;
      });
    } catch (e) {
      String msg = '注册失败，请稍后重试';
      if (e is AuthException) {
        msg = e.message ?? msg;
      }
      setState(() {
        _error = msg;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_registered) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 64, color: AppTheme.primary),
                const SizedBox(height: 24),
                Text(
                  '注册成功',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '请使用刚注册的账号密码在登录页登录，登录后将进入首页。',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                Text(
                  '登录后可创建或加入情侣空间，与 TA 一起记录心意值',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.secondary,
                      ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => context.go('/login'),
                  child: const Text('去登录'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('注册'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 24),
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.error.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppTheme.error),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _nicknameController,
                  decoration: const InputDecoration(
                    labelText: '昵称',
                    hintText: '请输入昵称',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return '请输入昵称';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: '邮箱',
                    hintText: '请输入邮箱',
                    prefixIcon: Icon(Icons.email_outlined),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return '请输入邮箱';
                    if (!v.contains('@')) return '请输入有效邮箱';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: '密码',
                    hintText: '至少 6 位',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return '请输入密码';
                    if (v.length < 6) return '密码至少 6 位';
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('注册'),
                ),
                const SizedBox(height: 12),
                Text(
                  '内测阶段无需邮箱验证，注册成功后可直接使用账号密码登录（成功页会自动跳回登录）。',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.secondary,
                      ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('已有账号？去登录'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
