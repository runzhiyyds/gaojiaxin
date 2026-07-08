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

  void set(String key, dynamic value) {
    if (_store.length >= _maxKeys && !_store.containsKey(key)) {
      final oldest = _store.keys.first;
      _store.remove(oldest);
    }
    _store[key] = _Entry(value, DateTime.now());
  }

  void remove(String key) {
    _store.remove(key);
  }

  /// 移除所有以 prefix 开头的 key，用于写操作后使相关列表/汇总失效。
  void removeByPrefix(String prefix) {
    final toRemove = _store.keys.where((k) => k.startsWith(prefix)).toList();
    for (final k in toRemove) _store.remove(k);
  }

  void clear() {
    _store.clear();
  }
}

class _Entry {
  _Entry(this.value, this.at);
  final dynamic value;
  final DateTime at;
}
