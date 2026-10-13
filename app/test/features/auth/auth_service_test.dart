import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:love_story/features/auth/auth_service.dart';
import 'package:love_story/core/network/supabase_http_client.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Map<String, Object?> sessionJson(String id) => {
      'access_token': 'test-access-token',
      'refresh_token': 'test-refresh-token',
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

void main() {
  test('restores local session with no password request on construction',
      () async {
    final auth = GoTrueClient(
        url: 'https://example.test/auth/v1',
        autoRefreshToken: false,
        httpClient:
            MockClient((_) async => throw StateError('Unexpected request')));
    await auth.setInitialSession(jsonEncode(sessionJson('user-a')));
    final service = AuthService(client: auth);
    expect(service.currentUser?.id, 'user-a');
    service.dispose();
    auth.dispose();
  });

  test('login uses one token request without getUser or duplicate submission',
      () async {
    var requests = 0;
    final response = Completer<http.Response>();
    final auth = GoTrueClient(
        url: 'https://example.test/auth/v1',
        autoRefreshToken: false,
        httpClient: MockClient((request) async {
          requests++;
          expect(request.url.path, '/auth/v1/token');
          return response.future;
        }));
    final service = AuthService(client: auth);
    final pending = service.signInWithPassword(
        email: 'a@example.test', password: 'password');
    await service.signInWithPassword(
        email: 'a@example.test', password: 'password');
    expect(service.isLoggedIn, isFalse);
    response.complete(http.Response(jsonEncode(sessionJson('user-a')), 200));
    await pending;
    expect(requests, 1);
    expect(service.currentUser?.id, 'user-a');
    service.dispose();
    auth.dispose();
  });

  test('timed-out token response cannot produce a late login', () async {
    final transport = _LateTransport();
    final client = SupabaseHttpClient(
        inner: transport, timeout: const Duration(milliseconds: 20));
    final auth = GoTrueClient(
        url: 'https://example.test/auth/v1',
        autoRefreshToken: false,
        httpClient: client);
    final service = AuthService(client: auth);
    await expectLater(
        service.signInWithPassword(
            email: 'a@example.test', password: 'password'),
        throwsA(isA<AuthRetryableFetchException>()));
    transport.response.complete(http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(sessionJson('user-a')))), 200));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(service.isLoggedIn, isFalse);
    expect(auth.currentSession, isNull);
    service.dispose();
    auth.dispose();
    client.close();
  });
}

class _LateTransport extends http.BaseClient {
  final response = Completer<http.StreamedResponse>();
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      response.future;
}
