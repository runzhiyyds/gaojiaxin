import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:love_story/features/couple/couple_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, Object?> _session(String id) => {
      'access_token': 'test-token',
      'refresh_token': 'refresh-token',
      'token_type': 'bearer',
      'expires_in': 3600,
      'user': {
        'id': id,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-01-01T00:00:00Z'
      },
    };
http.Response _profile(http.Request request, String user, String? space) =>
    http.Response(
        jsonEncode({
          'id': user,
          'couple_space_id': space,
          'nickname': user,
        }),
        200,
        request: request,
        headers: {'content-type': 'application/json'});

void main() {
  test('constructor, auth event and concurrent refresh share one profile read',
      () async {
    var reads = 0;
    final profile = Completer<void>();
    final client = SupabaseClient('https://example.test', 'anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
      reads++;
      await profile.future;
      return _profile(request, 'user-a', null);
    }));
    await client.auth.setInitialSession(jsonEncode(_session('user-a')));
    final service = CoupleService(client: client);
    final first = service.refresh();
    final second = service.refresh();
    profile.complete();
    await Future.wait([first, second]);
    expect(reads, 1);
    expect(service.loading, isFalse);
    expect(service.error, isNull);
    service.dispose();
    await client.dispose();
  });

  test('late previous-account response cannot overwrite current binding',
      () async {
    final oldProfile = Completer<void>();
    final client = SupabaseClient('https://example.test', 'anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
      if (request.url.queryParameters['id'] == 'eq.user-a') {
        await oldProfile.future;
        return _profile(request, 'user-a', null);
      }
      return _profile(request, 'user-b', null);
    }));
    await client.auth.setInitialSession(jsonEncode(_session('user-a')));
    final service = CoupleService(client: client);
    final old = service.refresh();
    await client.auth.setInitialSession(jsonEncode(_session('user-b')));
    await service.refresh();
    oldProfile.complete();
    await old;
    expect(service.myProfile?['id'], 'user-b');
    expect(service.loading, isFalse);
    service.dispose();
    await client.dispose();
  });

  test('failed binding load exposes retryable error instead of unbound success',
      () async {
    var fail = true;
    final client = SupabaseClient('https://example.test', 'anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
      if (fail)
        throw http.ClientException('SocketException: Connection timed out');
      return _profile(request, 'user-a', null);
    }));
    await client.auth.setInitialSession(jsonEncode(_session('user-a')));
    final service = CoupleService(client: client);
    await service.refresh();
    expect(service.loading, isFalse);
    expect(service.error, contains('连接服务超时'));
    fail = false;
    await service.refresh();
    expect(service.error, isNull);
    expect(service.myProfile?['id'], 'user-a');
    service.dispose();
    await client.dispose();
  });
}
