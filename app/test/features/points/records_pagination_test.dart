import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:love_story/core/cache/app_cache.dart';
import 'package:love_story/features/points/points_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  setUp(() => AppCache.instance.clear());
  test(
      'requests only the next 20 records with stable ordering and isolated cache',
      () async {
    final offsets = <String>[];
    final client = SupabaseClient('https://example.test', 'anon',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
      expect(request.url.queryParameters['couple_space_id'], 'eq.space-a');
      expect(request.url.queryParameters['order']?.replaceAll('.nullslast', ''), 'record_at.desc,id.desc');
      expect(request.url.queryParameters['limit'], '20');
      offsets.add(request.url.queryParameters['offset']!);
      return http.Response(jsonEncode([]), 200,
          request: request, headers: {'content-type': 'application/json'});
    }));
    final repo = PointsRepository(client);
    await repo.getRecords(coupleSpaceId: 'space-a', limit: 20);
    await repo.getRecords(coupleSpaceId: 'space-a', limit: 20, offset: 20);
    await repo.getRecords(coupleSpaceId: 'space-a', limit: 20, offset: 20);
    expect(offsets, ['0', '20']);
    await client.dispose();
  });
}
