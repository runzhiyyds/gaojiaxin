import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:love_story/core/notifications/device_repository.dart';
import 'package:love_story/core/notifications/notification_service.dart';

class DeviceRegistration {
  DeviceRegistration(this._supabase) : _repo = DeviceRepository(_supabase);

  final SupabaseClient _supabase;
  final DeviceRepository _repo;

  Future<void> registerCurrentDevice({required String? coupleSpaceId}) async {
    final user = _supabase.auth.currentUser;
    if (user == null || coupleSpaceId == null || coupleSpaceId.isEmpty) return;

    String? token;
    try {
      await NotificationService.instance.init();
      await NotificationService.instance.requestPermissionsIfNeeded();
      token = await FirebaseMessaging.instance.getToken();
    } catch (_) {
      return;
    }
    if (token == null || token.isEmpty) return;

    final info = await PackageInfo.fromPlatform();
    final platform =
        Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'other');

    if (_supabase.auth.currentUser?.id != user.id) return;
    await _repo.upsertDeviceToken(
      userId: user.id,
      coupleSpaceId: coupleSpaceId,
      token: token,
      platform: platform,
      appVersion: info.version,
    );
  }
}
