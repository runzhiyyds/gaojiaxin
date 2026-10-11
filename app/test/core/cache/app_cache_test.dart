import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:love_story/core/cache/app_cache.dart';

void main() {
  late AppCache cache;

  setUp(() {
    cache = AppCache.instance;
    cache.clear();
  });

  test('concurrent reads share one request', () async {
    var calls = 0;
    final response = Completer<int>();
    Future<int> load() { calls++; return response.future; }
    final first = cache.getOrLoad('shared', load);
    final second = cache.getOrLoad('shared', load);
    response.complete(42);
    expect(await first, 42);
    expect(await second, 42);
    expect(calls, 1);
  });

  test('old response cannot overwrite cache after invalidation', () async {
    final old = Completer<int>();
    final pending = cache.getOrLoad('points:s1', () => old.future);
    cache.removeByPrefix('points:');
    expect(await cache.getOrLoad('points:s1', () async => 2), 2);
    old.complete(1);
    expect(await pending, 1);
    expect(cache.get<int>('points:s1'), 2);
  });

  test('account switch clears both cache and pending response ownership', () async {
    final old = Completer<int>();
    final pending = cache.getOrLoad('points:s1', () => old.future);
    cache.clear();
    old.complete(1);
    await pending;
    expect(cache.get<int>('points:s1'), isNull);
  });

  test('failed shared request can be retried', () async {
    await expectLater(cache.getOrLoad<int>('failed', () async => throw StateError('failure')),
        throwsStateError);
    expect(await cache.getOrLoad('failed', () async => 7), 7);
  });

  group('AppCache', () {
    test('get returns null for missing key', () {
      expect(cache.get<String>('missing'), isNull);
    });

    test('set and get', () {
      cache.set('k1', 42);
      expect(cache.get<int>('k1'), 42);
    });

    test('set overwrites', () {
      cache.set('k1', 1);
      cache.set('k1', 2);
      expect(cache.get<int>('k1'), 2);
    });

    test('remove', () {
      cache.set('k1', 1);
      cache.remove('k1');
      expect(cache.get<int>('k1'), isNull);
    });

    test('removeByPrefix removes only matching keys', () {
      cache.set('points:space1', 1);
      cache.set('points:space2', 2);
      cache.set('mall:space1', 3);
      cache.removeByPrefix('points:');
      expect(cache.get<int>('points:space1'), isNull);
      expect(cache.get<int>('points:space2'), isNull);
      expect(cache.get<int>('mall:space1'), 3);
    });

    test('eviction when at maxKeys: oldest key removed', () {
      const maxKeys = 256;
      for (var i = 0; i < maxKeys; i++) {
        cache.set('key_$i', i);
      }
      expect(cache.get<int>('key_0'), 0);
      cache.set('key_new', -1);
      expect(cache.get<int>('key_new'), -1);
      expect(cache.get<int>('key_0'), isNull);
      expect(cache.get<int>('key_1'), 1);
    });
  });
}
