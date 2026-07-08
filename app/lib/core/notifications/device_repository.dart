import 'package:supabase_flutter/supabase_flutter.dart';

class DeviceRepository {
  DeviceRepository(this._client);

  final SupabaseClient _client;

  Future<void> upsertDeviceToken({
    required String userId,
    required String coupleSpaceId,
    required String token,
    required String platform,
    required String appVersion,
  }) async {
    await _client.from('push_devices').upsert({
      'user_id': userId,
      'couple_space_id': coupleSpaceId,
      'device_token': token,
      'platform': platform,
      'app_version': appVersion,
      'is_active': true,
      'last_seen_at': DateTime.now().toIso8601String(),
    });
  }
}

