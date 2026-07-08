import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:love_story/core/config.dart';
import 'package:love_story/main.dart' as app;

/// 集成测试：验证应用能启动。
/// 未配置 Supabase 时显示「未配置 Supabase」；已配置时进入启动页。
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('app starts', (WidgetTester tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 5));

    if (!Config.isSupabaseConfigured) {
      expect(find.text('未配置 Supabase'), findsOneWidget);
    } else {
      expect(find.byType(MaterialApp), findsOneWidget);
    }
  });
}
