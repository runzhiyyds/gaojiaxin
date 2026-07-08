import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:love_story/features/auth/auth_service.dart';
import 'package:love_story/features/auth/login_screen.dart';
import 'package:love_story/features/auth/register_screen.dart';
import 'package:love_story/features/couple/bind_screen.dart';
import 'package:love_story/features/home/main_shell.dart';
import 'package:love_story/features/points/points_screen.dart';
import 'package:love_story/features/mall/mall_screen.dart';
import 'package:love_story/features/profile/profile_screen.dart';
import 'package:love_story/features/journey/love_journey_screen.dart';
import 'package:love_story/features/splash/splash_screen.dart';
import 'package:love_story/features/points/record_edit_screen.dart';
import 'package:love_story/features/points/point_record_model.dart';
import 'package:love_story/features/points/record_point_screen.dart';
import 'package:love_story/features/mall/mall_good_edit_screen.dart';
import 'package:love_story/features/mall/mall_good_detail_screen.dart';
import 'package:love_story/features/mall/mall_my_goods_screen.dart';
import 'package:love_story/features/mall/exchange_history_screen.dart';
import 'package:love_story/features/profile/settings_screen.dart';
import 'package:love_story/features/profile/about_screen.dart';
import 'package:love_story/features/points/user_manual_screen.dart';
import 'package:love_story/features/deposits/deposits_screen.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

/// 创建路由；[authService] 为登录状态唯一数据源，redirect 与 refreshListenable 均依赖其。
GoRouter createRouter(AuthService authService) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    refreshListenable: authService,
    redirect: (context, state) {
      final isLoggedIn = authService.isLoggedIn;

      final loc = state.matchedLocation;
      final isSplash = loc == '/';
      final isAuth = loc == '/login' || loc == '/register';
      final isBind = loc == '/bind';
      final isHome = loc.startsWith('/home');

      // 启动页永远放行，由 Splash 自己决定后续去哪
      if (isSplash) return null;

      // /home 统一进积分页（底部第一项）
      if (loc == '/home') return '/home/points';

      // 未登录：允许进入登录/注册页和首页
      if (!isLoggedIn) {
        if (isAuth) return null;
        if (loc.startsWith('/home/profile')) return '/login';
        if (isHome) return null;
        return '/home/points';
      }

      // 已登录：登录/注册后先进首页，绑定入口在个人页/积分页
      if (isAuth) return '/home/points';

      // 已登录情况下，绑定页 & 主页面都放行
      if (isBind || isHome) return null;

      // 其他奇怪路径兜底：回积分页
      return '/home/points';
    },
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        builder: (_, __) => const RegisterScreen(),
      ),
      GoRoute(
        path: '/bind',
        builder: (_, __) => const BindScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShell(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/points',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: PointsScreen(),
                ),
                routes: [
                  GoRoute(
                    path: 'record',
                    builder: (_, __) => const RecordPointScreen(),
                  ),
                  GoRoute(
                    path: 'record/edit',
                    builder: (context, state) {
                      final record = state.extra as PointRecordModel;
                      return RecordEditScreen(record: record);
                    },
                  ),
                  GoRoute(
                    path: 'manual',
                    builder: (context, state) {
                      final isFirstTime = state.extra == true;
                      return UserManualScreen(isFirstTime: isFirstTime);
                    },
                  ),
                  GoRoute(
                    path: 'deposits',
                    builder: (_, __) => const DepositsScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/journey',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: LoveJourneyScreen(),
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/mall',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: MallScreen(),
                ),
                routes: [
                  GoRoute(
                    path: 'goods/edit',
                    builder: (_, __) => const MallGoodEditScreen(),
                  ),
                  GoRoute(
                    path: 'goods/edit/:id',
                    builder: (context, state) {
                      final id = state.pathParameters['id']!;
                      return MallGoodEditScreen(goodId: id);
                    },
                  ),
                  GoRoute(
                    path: 'goods/:id',
                    builder: (context, state) {
                      final id = state.pathParameters['id']!;
                      return MallGoodDetailScreen(goodId: id);
                    },
                  ),
                  GoRoute(
                    path: 'my-goods',
                    builder: (_, __) => const MallMyGoodsScreen(),
                  ),
                  GoRoute(
                    path: 'history',
                    builder: (_, __) => const ExchangeHistoryScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home/profile',
                pageBuilder: (context, state) => const NoTransitionPage(
                  child: ProfileScreen(),
                ),
                routes: [
                  GoRoute(
                    path: 'settings',
                    builder: (_, __) => const SettingsScreen(),
                  ),
                  GoRoute(
                    path: 'about',
                    builder: (_, __) => const AboutScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
}
