import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:love_story/app.dart';
import 'package:love_story/core/config.dart';
import 'package:love_story/router.dart';
import 'package:love_story/core/settings_prefs.dart';
import 'package:love_story/features/auth/auth_service.dart';
import 'package:love_story/features/couple/couple_service.dart';
import 'package:love_story/features/points/points_repository.dart';
import 'package:love_story/features/mall/mall_repository.dart';
import 'package:love_story/features/deposits/deposits_repository.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:love_story/firebase_options.dart';
import 'package:love_story/core/notifications/notification_service.dart';

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

    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
    ]);

    if (!Config.isSupabaseConfigured) {
      runApp(const _ConfigErrorApp());
      return;
    }

    await Supabase.initialize(
      url: Config.supabaseUrl,
      anonKey: Config.supabaseAnonKey,
    );

    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    await NotificationService.instance.init();
    await NotificationService.instance.requestPermissionsIfNeeded();
    NotificationService.instance.listenForegroundMessages();

    _listenAuthConfirmLink();

    final authService = AuthService();
    final router = createRouter(authService);

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: authService),
          ChangeNotifierProvider(create: (_) => CoupleService()),
          Provider(create: (_) => PointsRepository(Supabase.instance.client)),
          Provider(create: (_) => MallRepository(Supabase.instance.client)),
          Provider(create: (ctx) => DepositsRepository(
            Supabase.instance.client,
            ctx.read<PointsRepository>(),
          )),
        ],
        child: LoveStoryApp(router: router),
      ),
    );
  }, (Object error, StackTrace stack) {
    if (kDebugMode) {
      debugPrint('runZonedGuarded: $error\n$stack');
    }
  });
}

StreamSubscription? _appLinksSubscription;

/// 当用户通过邮件确认链接打开应用时清除「待确认邮箱」，以便之后可正常登录
void _listenAuthConfirmLink() {
  final appLinks = AppLinks();
  appLinks.getInitialLink().then((uri) {
    if (uri != null && _isAuthConfirmUri(uri.toString())) {
      SettingsPrefs.clearPendingConfirmEmail();
    }
  });
  _appLinksSubscription = appLinks.uriLinkStream.listen((uri) {
    if (uri != null && _isAuthConfirmUri(uri.toString())) {
      SettingsPrefs.clearPendingConfirmEmail();
    }
  });
}

bool _isAuthConfirmUri(String s) {
  final lower = s.toLowerCase();
  return lower.contains('confirm') ||
      lower.contains('verify') ||
      lower.contains('token') ||
      lower.contains('type=signup') ||
      lower.contains('access_token');
}

/// 未传入 Supabase 配置时显示，避免出现 link-local / FormatException 等难以理解的错误。
class _ConfigErrorApp extends StatelessWidget {
  const _ConfigErrorApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.orange),
                const SizedBox(height: 24),
                Text(
                  '未配置 Supabase',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  '此安装包未在构建时传入 Supabase 的 URL 与密钥，无法登录和同步数据。'
                  '请使用以下命令重新打包（将 URL 和密钥替换为你的项目配置）：',
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                SelectableText(
                  'flutter build apk --release \\\n'
                  '  --dart-define=SUPABASE_URL=https://你的项目ID.supabase.co \\\n'
                  '  --dart-define=SUPABASE_ANON_KEY=你的anon密钥',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontFamily: 'monospace',
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
