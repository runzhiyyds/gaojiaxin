import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:love_story/core/theme.dart';
import 'package:provider/provider.dart';
import 'package:love_story/features/auth/auth_service.dart';
import 'package:love_story/core/user_error.dart';
import 'package:flutter/services.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _error = null;
      _loading = true;
    });
    try {
      await context.read<AuthService>().signInWithPassword(
            email: _emailController.text.trim(),
            password: _passwordController.text,
          );
      TextInput.finishAutofillContext();
      // AuthService notifies the router after success; it owns navigation.
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = toUserMessage(e, context: '登录');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: AutofillGroup(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 60),
                  Text(
                    '爱情心意值',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: AppTheme.primaryDark,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '登录',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppTheme.secondary,
                        ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '登录后可创建或加入情侣空间，与 TA 一起记录心意值',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.secondary,
                        ),
                  ),
                  const SizedBox(height: 8),
                  const SizedBox(height: 32),
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
                    controller: _emailController,
                    enabled: !_loading,
                    autofillHints: const [
                      AutofillHints.username,
                      AutofillHints.email
                    ],
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
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
                    enabled: !_loading,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: '密码',
                      hintText: '请输入密码',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return '请输入密码';
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
                        : Text(_error == null ? '登录' : '重试登录'),
                  ),
                  if (_loading) ...[
                    const SizedBox(height: 12),
                    const Text('正在连接，请稍候…', textAlign: TextAlign.center),
                  ],
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed:
                        _loading ? null : () => context.push('/register'),
                    child: const Text('还没有账号？去注册'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
