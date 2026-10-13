import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:love_story/core/config.dart';
import 'package:love_story/core/network/supabase_http_client.dart';
import 'package:love_story/features/auth/auth_service.dart';
import 'package:love_story/features/auth/login_screen.dart';
import 'package:love_story/features/couple/couple_service.dart';
import 'package:love_story/features/home/main_shell.dart';
import 'package:love_story/main.dart' as app;

const email = String.fromEnvironment('NETWORK_TEST_EMAIL');
const password = String.fromEnvironment('NETWORK_TEST_PASSWORD');
const expectOldSession = bool.fromEnvironment('NETWORK_EXPECT_OLD_SESSION');

Future<void> waitFor(WidgetTester tester, bool Function() ready,
    {Duration timeout = const Duration(seconds: 30)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), true, reason: 'Expected state was not reached before deadline');
}

Future<void> checkRealtime(SupabaseClient client) async {
  final subscribed = Completer<void>();
  final channel = client.channel('gateway-validation-${DateTime.now().microsecondsSinceEpoch}')
      .onPostgresChanges(event: PostgresChangeEvent.all,
          schema: 'public', table: 'point_records', callback: (_) {});
  channel.subscribe((status, error) {
    if (subscribed.isCompleted) return;
    if (status == RealtimeSubscribeStatus.subscribed) subscribed.complete();
    if (status == RealtimeSubscribeStatus.channelError ||
        status == RealtimeSubscribeStatus.timedOut) {
      subscribed.completeError(StateError('Realtime subscription failed'));
    }
  });
  try {
    await subscribed.future.timeout(const Duration(seconds: 20));
  } finally {
    await client.removeChannel(channel);
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('gateway restores the existing app session and opens core pages', (tester) async {
    expect(Uri.parse(Config.supabaseUrl).host, 'gaojiaxin-check.pet-food-advisor.asia');
    app.main();
    await waitFor(tester, () => find.byType(MainShell).evaluate().isNotEmpty);
    final client = Supabase.instance.client;
    if (expectOldSession) expect(client.auth.currentSession != null, true);
    final context = tester.element(find.byType(MainShell));
    final couple = context.read<CoupleService>();
    await waitFor(tester, () => !couple.loading);
    expect(couple.error, isNull);
    final user = client.auth.currentUser;
    if (user != null) {
      final profile = await client.from('profiles').select('id,couple_space_id')
          .eq('id', user.id).single();
      expect(profile['id'] == user.id, true);
    }
    for (final label in ['爱情旅程', '心意商城', '我的', '心意']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
      await tester.pump(const Duration(seconds: 2));
      expect(find.byType(MainShell), findsOneWidget);
    }
    if (client.auth.currentSession != null) await checkRealtime(client);
    expect(tester.takeException(), isNull);
  });

  testWidgets('password login UI, scoped reads, RPC guard, refresh and realtime use gateway', (tester) async {
    // Isolated memory-only client keeps the phone owner's persisted session intact.
    final client = SupabaseClient(Config.supabaseUrl, Config.supabaseAnonKey,
        httpClient: SupabaseHttpClient(),
        authOptions: const AuthClientOptions(autoRefreshToken: false));
    final auth = AuthService(client: client.auth);
    final router = GoRouter(initialLocation: '/login', refreshListenable: auth,
        redirect: (_, state) => auth.isLoggedIn && state.matchedLocation == '/login' ? '/success' : null,
        routes: [
          GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
          GoRoute(path: '/success', builder: (_, __) => const Scaffold(body: Text('Validation login complete'))),
        ]);
    try {
      await tester.pumpWidget(ChangeNotifierProvider.value(value: auth,
          child: MaterialApp.router(routerConfig: router)));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).at(0), email);
      await tester.enterText(find.byType(TextFormField).at(1), password);
      final login = find.widgetWithText(FilledButton, '登录');
      await tester.ensureVisible(login);
      final watch = Stopwatch()..start();
      await tester.tap(login);
      await waitFor(tester, () => auth.isLoggedIn,
          timeout: const Duration(seconds: 15));
      watch.stop();
      debugPrint('GATEWAY_LOGIN_MS=${watch.elapsedMilliseconds}');
      await tester.pump();
      expect(find.text('Validation login complete'), findsOneWidget);
      final userId = auth.currentUser!.id;
      final profile = await client.from('profiles').select('id,couple_space_id')
          .eq('id', userId).single();
      expect(profile['id'] == userId, true);
      final spaceId = profile['couple_space_id'] as String?;
      if (spaceId != null) {
        await client.from('couple_spaces').select('id').eq('id', spaceId).single();
        for (final table in ['point_items', 'point_records', 'mall_goods', 'exchange_records']) {
          await client.from(table).select('id').eq('couple_space_id', spaceId).limit(5);
        }
      }
      // A deliberately empty match verifies PATCH transport without changing data.
      final empty = await client.from('profiles').update({'nickname': 'gateway-validation'})
          .eq('id', '00000000-0000-0000-0000-000000000000').select('id');
      expect(empty, isEmpty);
      try {
        await client.rpc('set_point_record_recipient_comment', params: {
          'p_record_id': '00000000-0000-0000-0000-000000000000', 'p_comment': '',
        });
        fail('Missing record must be rejected by the server');
      } on PostgrestException catch (error) {
        expect(error.message, 'record not found');
      }
      final refreshed = await client.auth.refreshSession();
      expect(refreshed.user?.id == userId, true);
      await checkRealtime(client);
      await client.realtime.disconnect();
      await checkRealtime(client);
      await auth.signOut();
      expect(auth.isLoggedIn, false);
      expect(Supabase.instance.client.auth.currentSession != null || !expectOldSession, true);
      expect(tester.takeException(), isNull);
    } finally {
      if (auth.isLoggedIn) await auth.signOut();
      await tester.pumpWidget(const SizedBox.shrink());
      router.dispose();
      auth.dispose();
      await client.dispose();
    }
  }, skip: email.isEmpty || password.isEmpty);
}
