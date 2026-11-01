import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/testing.dart';
import 'package:love_story/features/auth/auth_service.dart';
import 'package:love_story/features/splash/splash_screen.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  for (final loggedIn in [false, true]) {
    testWidgets('local session routes immediately (loggedIn=$loggedIn)', (tester) async {
      var requests = 0;
      final auth = GoTrueClient(url: 'https://example.test/auth/v1', autoRefreshToken: false,
          httpClient: MockClient((_) async {
            requests++;
            throw StateError('Startup should not request password login');
          }));
      if (loggedIn) {
        await auth.setInitialSession(jsonEncode({
          'access_token': 'test-token', 'refresh_token': 'refresh-token',
          'token_type': 'bearer', 'expires_in': 3600,
          'user': {'id': 'user-a', 'app_metadata': {}, 'user_metadata': {},
            'aud': 'authenticated', 'created_at': '2026-01-01T00:00:00Z'},
        }));
      }
      final service = AuthService(client: auth);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
        GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Text('Login destination'))),
        GoRoute(path: '/home/points', builder: (_, __) => const Scaffold(body: Text('Home destination'))),
      ]);
      await tester.pumpWidget(ChangeNotifierProvider.value(value: service,
          child: MaterialApp.router(routerConfig: router)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(loggedIn ? 'Home destination' : 'Login destination'), findsOneWidget);
      expect(requests, 0);
      await tester.pumpWidget(const SizedBox());
      router.dispose();
      service.dispose();
      auth.dispose();
    });
  }
}
