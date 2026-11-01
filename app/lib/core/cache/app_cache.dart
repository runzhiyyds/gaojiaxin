import 'dart:async';

/// 内存缓存：已加载过的数据在本地保存，减少重复请求。
/// 写操作（增删改）时需调用 invalidate 使相关缓存失效。
///
/// 写后失效契约（各 Repository 写方法必须调用对应 invalidate）：
/// - PointsRepository: 前缀 pi:, pia:, pid:, piri:, piint:, pr:, pe:, pc: → invalidateForSpace / _invalidatePoints
/// - MallRepository: 前缀 mg:, mgo:, mg1:, msp:, mex: → _invalidateMallGoods / invalidateForSpace
/// - DepositsRepository: 前缀 pdlocked:, pdlist:, pddefault: → _invalidate / invalidateForSpace
class AppCache {
  AppCache._();

  static final AppCache instance = AppCache._();

  final Map<String, _Entry> _store = {};
  final Map<String, Future<dynamic>> _pending = {};
  static const _maxKeys = 256;

  /// 缓存条目最大存活时间，超时则 get 时视为未命中并移除。
  static const maxAge = Duration(minutes: 10);

  T? get<T>(String key) {
    final e = _store[key];
    if (e == null) return null;
    if (DateTime.now().difference(e.at) > maxAge) {
      _store.remove(key);
      return null;
    }
    return e.value as T?;
  }

  /// Share concurrent reads. Invalidation detaches pending reads so an old
  /// response cannot repopulate the cache after a write or account switch.
  Future<T> getOrLoad<T>(String key, Future<T> Function() load) async {
    final cached = get<T>(key);
    if (cached != null) return cached;
    final existing = _pending[key];
    if (existing != null) return await existing as T;
    final completer = Completer<T>();
    final future = completer.future;
    _pending[key] = future;
    unawaited(() async {
      try {
        final result = await load();
        if (identical(_pending[key], future)) {
          set(key, result);
        }
        completer.complete(result);
      } catch (error, stack) {
        completer.completeError(error, stack);
      } finally {
        if (identical(_pending[key], future)) _pending.remove(key);
      }
    }());
    return future;
  }

  void set(String key, dynamic value) {
    _pending.remove(key);
    if (_store.length >= _maxKeys && !_store.containsKey(key)) {
      final oldest = _store.keys.first;
      _store.remove(oldest);
    }
    _store[key] = _Entry(value, DateTime.now());
  }

  void remove(String key) {
    _pending.remove(key);
    _store.remove(key);
  }

  /// 移除所有以 prefix 开头的 key，用于写操作后使相关列表/汇总失效。
  void removeByPrefix(String prefix) {
    _pending.removeWhere((key, _) => key.startsWith(prefix));
    final toRemove = _store.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in toRemove) _store.remove(k);
  }

  void clear() {
    _pending.clear();
    _store.clear();
  }
}

class _Entry {
  _Entry(this.value, this.at);
  final dynamic value;
  final DateTime at;
}
