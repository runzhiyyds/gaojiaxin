import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:love_story/core/supabase_guard.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('a transient read may retry once and succeed', () async {
    var calls = 0;
    final result = await withSupabaseCall(() async {
      if (++calls == 1) throw http.ClientException('Connection reset');
      return 42;
    }, isRead: true);
    expect(result, 42);
    expect(calls, 2);
  });
  for (final error in [TimeoutException('timeout'),
      const PostgrestException(message: 'permission denied', code: '42501')]) {
    test('does not replay ${error.runtimeType} reads', () async {
      var calls = 0;
      await expectLater(withSupabaseCall(() async {
        calls++;
        throw error;
      }, isRead: true), throwsA(same(error)));
      expect(calls, 1);
    });
  }
  test('does not replay a write after network failure', () async {
    var calls = 0;
    await expectLater(withSupabaseCall(() async {
      calls++;
      throw http.ClientException('Connection reset');
    }), throwsA(isA<http.ClientException>()));
    expect(calls, 1);
  });
}
