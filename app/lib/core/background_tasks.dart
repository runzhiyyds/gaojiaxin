import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:love_story/core/notifications/notification_service.dart';
import 'package:love_story/core/pgyer_update.dart';
import 'package:shorebird_code_push/shorebird_code_push.dart';

/// Optional services must never delay first frame, login, or binding.
void startBackgroundTasks(GoRouter router) {
  // Web is for business/UI verification; Android updates and notifications
  // require native plugins and must not run in the browser.
  if (kIsWeb) return;
  unawaited(() async {
    try {
      await NotificationService.instance.init();
      NotificationService.instance.listenForegroundMessages();
    } catch (error) {
      if (kDebugMode) debugPrint('Notifications unavailable: $error');
    }
  }());
  unawaited(() async {
    try {
      final updater = ShorebirdUpdater();
      if (!updater.isAvailable) return;
      final status =
          await updater.checkForUpdate().timeout(const Duration(seconds: 5));
      if (status == UpdateStatus.outdated) await updater.update();
    } catch (error) {
      if (kDebugMode) debugPrint('Patch check unavailable: $error');
    }
  }());
  unawaited(() async {
    final update = await checkPgyerUpdate();
    final context = router.routerDelegate.navigatorKey.currentContext;
    if (update == null || context == null || !context.mounted) return;
    await showPgyerUpdateDialogWithInAppInstall(context, update,
        openInAppForFallback: false);
  }()
      .catchError((Object error) {
    if (kDebugMode) debugPrint('Update check unavailable: $error');
  }));
}
