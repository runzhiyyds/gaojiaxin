import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_story/core/load_feedback.dart';

void main() {
  testWidgets('cached-data refresh notice is concise and keeps retry',
      (tester) async {
    var retries = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RefreshNotice(
            message: '暂时无法连接服务，请检查网络或切换网络后重试。',
            onRetry: () => retries++,
          ),
        ),
      ),
    );

    expect(find.text('网络不稳定，暂未同步'), findsOneWidget);
    expect(find.textContaining('刷新失败，以下为上次加载的内容'), findsNothing);
    expect(find.text('重试'), findsOneWidget);

    await tester.tap(find.text('重试'));
    expect(retries, 1);
  });

  testWidgets('non-network refresh errors keep their specific message',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RefreshNotice(
            message: '数据关联异常，请稍后重试。',
            onRetry: () {},
          ),
        ),
      ),
    );

    expect(find.text('数据关联异常，请稍后重试。'), findsOneWidget);
  });

  testWidgets('background retry explains cached data stays read only',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RefreshNotice(
            message: '暂时无法连接服务',
            onRetry: () {},
            autoRetrying: true,
            cachedReadOnly: true,
          ),
        ),
      ),
    );

    expect(
      find.text('后台自动重试中。你可继续查看，也可检查网络；同步成功后可编辑。'),
      findsOneWidget,
    );
    expect(find.text('立即重试'), findsOneWidget);
  });
}
