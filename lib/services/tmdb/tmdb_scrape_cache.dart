import 'dart:async';
import 'dart:collection';

/// TMDB 刮削请求的缓存类别。
enum TmdbScrapeCacheKind { search, details, aliases }

/// 为 TMDB 响应提供带 TTL 的 LRU 缓存和进行中请求合并。
///
/// 缓存只保存成功的响应对象，不持久化 API Key、远程路径或媒体内容。
class TmdbScrapeCache {
  TmdbScrapeCache({
    this.searchTtl = const Duration(minutes: 10),
    this.detailsTtl = const Duration(hours: 24),
    this.aliasTtl = const Duration(days: 30),
    this.maximumEntries = 100,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now {
    if (maximumEntries <= 0) {
      throw ArgumentError.value(maximumEntries, 'maximumEntries');
    }
    if (searchTtl < Duration.zero) {
      throw ArgumentError.value(searchTtl, 'searchTtl');
    }
    if (detailsTtl < Duration.zero) {
      throw ArgumentError.value(detailsTtl, 'detailsTtl');
    }
    if (aliasTtl < Duration.zero) {
      throw ArgumentError.value(aliasTtl, 'aliasTtl');
    }
  }

  final Duration searchTtl;
  final Duration detailsTtl;
  final Duration aliasTtl;
  final int maximumEntries;
  final DateTime Function() _now;

  final LinkedHashMap<String, _TmdbCacheEntry> _entries =
      LinkedHashMap<String, _TmdbCacheEntry>();
  final Map<String, Future<Object?>> _inFlight = <String, Future<Object?>>{};
  int _generation = 0;

  /// 当前已完成且未过期的缓存条目数量。
  int get length => _entries.length;

  /// 当前正在加载的请求数量，主要用于诊断和测试。
  int get inFlightCount => _inFlight.length;

  /// 获取缓存值；同一键的并发加载只执行一次。
  Future<T> getOrLoad<T>(
    String key,
    Future<T> Function() loader, {
    TmdbScrapeCacheKind? kind,
  }) {
    final normalizedKey = key.trim();
    if (normalizedKey.isEmpty) {
      throw ArgumentError.value(key, 'key', '缓存键不能为空');
    }

    final cached = _entries.remove(normalizedKey);
    if (cached != null) {
      if (_now().isBefore(cached.expiresAt)) {
        // 移除后重新插入，使 LinkedHashMap 的首项始终是最久未访问项。
        _entries[normalizedKey] = cached;
        return Future<T>.value(cached.value as T);
      }
    }

    final pending = _inFlight[normalizedKey];
    if (pending != null) {
      return pending.then<T>((value) => value as T);
    }

    final generation = _generation;
    late final Future<Object?> shared;
    shared = Future<T>.sync(loader).then<Object?>((value) {
      if (generation == _generation) {
        _store(
          normalizedKey,
          value,
          kind: kind,
        );
      }
      return value;
    });
    _inFlight[normalizedKey] = shared;
    shared.then<void>(
      (_) => _removeInFlight(normalizedKey, shared),
      onError: (Object error, StackTrace stackTrace) {
        // 失败不进入缓存，后续调用可以重新请求。
        _removeInFlight(normalizedKey, shared);
      },
    );
    return shared.then<T>((value) => value as T);
  }

  /// 清除已完成条目，并使清除前发起的请求不能回填缓存。
  void clear() {
    _generation += 1;
    _entries.clear();
    _inFlight.clear();
  }

  void _store(
    String key,
    Object? value, {
    TmdbScrapeCacheKind? kind,
  }) {
    final ttl = _ttlFor(key, kind);
    if (ttl <= Duration.zero) return;
    _entries.remove(key);
    _entries[key] = _TmdbCacheEntry(
      value: value,
      expiresAt: _now().add(ttl),
    );
    while (_entries.length > maximumEntries) {
      _entries.remove(_entries.keys.first);
    }
  }

  void _removeInFlight(String key, Future<Object?> future) {
    if (identical(_inFlight[key], future)) {
      _inFlight.remove(key);
    }
  }

  Duration _ttlFor(String key, TmdbScrapeCacheKind? kind) {
    switch (kind ?? _kindFromKey(key)) {
      case TmdbScrapeCacheKind.search:
        return searchTtl;
      case TmdbScrapeCacheKind.aliases:
        return aliasTtl;
      case TmdbScrapeCacheKind.details:
        return detailsTtl;
    }
  }

  TmdbScrapeCacheKind _kindFromKey(String key) {
    final prefix = key.split('|').first.toLowerCase();
    if (prefix == 'search') return TmdbScrapeCacheKind.search;
    if (prefix == 'alias' || prefix == 'aliases') {
      return TmdbScrapeCacheKind.aliases;
    }
    // 详情、季度详情和未知键都按详情 TTL 处理，避免意外长时间缓存搜索结果。
    return TmdbScrapeCacheKind.details;
  }
}

class _TmdbCacheEntry {
  const _TmdbCacheEntry({required this.value, required this.expiresAt});

  final Object? value;
  final DateTime expiresAt;
}
