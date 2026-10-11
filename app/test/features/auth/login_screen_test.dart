import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:love_story/features/auth/auth_service.dart';
import 'package:love_story/features/auth/login_screen.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  testWidgets('timeout keeps inputs and gives a readable retry action',
      (tester) async {
    final auth = GoTrueClient(
        url: 'https://example.test/auth/v1',
        autoRefreshToken: false,
        httpClient: MockClient((_) async {
          throw http.ClientException('SocketException: Connection timed out');
        }));
    final service = AuthService(client: auth);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: service, child: const MaterialApp(home: LoginScreen())));
    await tester.enterText(find.byType(TextFormField).at(0), 'a@example.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'password');
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('连接服务超时，请切换 Wi-Fi 或移动网络后重试。'), findsOneWidget);
    expect(find.text('重试登录'), findsOneWidget);
    expect(find.text('a@example.test'), findsOneWidget);
    expect(service.isLoggedIn, isFalse);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
    auth.dispose();
  });

  testWidgets('leaving login while request fails avoids disposed setState',
      (tester) async {
    final response = Completer<http.Response>();
    final auth = GoTrueClient(
        url: 'https://example.test/auth/v1',
        autoRefreshToken: false,
        httpClient: MockClient((_) => response.future));
    final service = AuthService(client: auth);
    await tester.pumpWidget(ChangeNotifierProvider.value(
        value: service, child: const MaterialApp(home: LoginScreen())));
    await tester.enterText(find.byType(TextFormField).at(0), 'a@example.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'password');
    await tester.ensureVisible(find.byType(FilledButton));
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    response.completeError(http.ClientException('Connection timed out'));
    await tester.pump();
    expect(tester.takeException(), isNull);
    service.dispose();
    auth.dispose();
  });
}
