import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:love_story/app.dart';
import 'package:love_story/core/config.dart';
import 'package:love_story/router.dart';
import 'package:love_story/features/auth/auth_service.dart';
import 'package:love_story/features/couple/couple_service.dart';
import 'package:love_story/features/points/points_repository.dart';
import 'package:love_story/features/mall/mall_repository.dart';
import 'package:love_story/features/deposits/deposits_repository.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:love_story/core/notifications/notification_service.dart';
import 'package:love_story/core/network/supabase_http_client.dart';
import 'package:love_story/core/theme.dart';

void main() async {
  // ensureInitialized 与 runApp 必须在同一 zone，避免 Zone mismatch
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (FlutterErrorDetails details) {
      FlutterError.presentError(details);
      if (kDebugMode) {
        debugPrint('FlutterError: ${details.exception}\n${details.stack}');
      }
    };

    unawaited(SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]).catchError((Object error) {
      if (kDebugMode) debugPrint('Orientation unavailable: $error');
    }));
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    runApp(Config.isSupabaseConfigured
        ? const _BootstrapApp()
        : const _ConfigErrorApp());
  }, (Object error, StackTrace stack) {
    if (kDebugMode) {
      debugPrint('runZonedGuarded: $error\n$stack');
    }
  });
}

/// Show Flutter immediately; only local session restoration gates the app.
class _BootstrapApp extends StatefulWidget {
  const _BootstrapApp();

  @override
  State<_BootstrapApp> createState() => _BootstrapAppState();
}

class _BootstrapAppState extends State<_BootstrapApp> {
  Widget? _app;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    setState(() => _error = null);
    try {
      await Supabase.initialize(
        url: Config.supabaseUrl,
        anonKey: Config.supabaseAnonKey,
        httpClient: SupabaseHttpClient(),
      );
      final authService = AuthService();
      final router = createRouter(authService);
      if (!mounted) {
        authService.dispose();
        router.dispose();
        return;
      }
      setState(() {
        _app = MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => authService),
            ChangeNotifierProvider(create: (_) => CoupleService()),
            Provider(create: (_) => PointsRepository(Supabase.instance.client)),
            Provider(create: (_) => MallRepository(Supabase.instance.client)),
            Provider(
                create: (ctx) => DepositsRepository(
                      Supabase.instance.client,
                      ctx.read<PointsRepository>(),
                    )),
          ],
          child: LoveStoryApp(router: router),
        );
      });
    } catch (error) {
      if (kDebugMode) debugPrint('App initialization failed: $error');
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_app != null) return _app!;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('爱情心意值'),
              const SizedBox(height: 24),
              if (_error == null) ...[
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                const Text('正在准备…'),
              ] else ...[
                const Text('暂时无法启动，请重试。'),
                const SizedBox(height: 16),
                FilledButton(onPressed: _initialize, child: const Text('重试')),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A damaged/unconfigured build provides a readable recovery path.
class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp();

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const Scaffold(
          body: SafeArea(
              child: Center(
                  child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.error_outline, size: 48),
              SizedBox(height: 16),
              Text('应用配置不完整', style: TextStyle(fontSize: 20)),
              SizedBox(height: 12),
              Text('请重新安装最新版本，或联系应用维护者。', textAlign: TextAlign.center),
            ]),
          ))),
        ),
      );
}
