import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:love_story/core/config.dart';
import 'package:love_story/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app renders and leaves local bootstrap', (tester) async {
    app.main();
    // Background sync/animations must not make pumpAndSettle wait forever.
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    do {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.byType(MaterialApp).evaluate().isNotEmpty &&
          find.text('正在准备…').evaluate().isEmpty) break;
    } while (DateTime.now().isBefore(deadline));
    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.text('正在准备…'), findsNothing);
    expect(find.text('暂时无法启动，请重试。'), findsNothing);
    if (!Config.isSupabaseConfigured) {
      expect(find.text('应用配置不完整'), findsOneWidget);
    } else {
      expect(find.text('应用配置不完整'), findsNothing);
    }
    expect(tester.takeException(), isNull);
  });
}
