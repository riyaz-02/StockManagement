import 'dart:async';

/// Simple in-memory cache for API responses
class CachedResponse {
  final dynamic data;
  final DateTime timestamp;

  CachedResponse(this.data, this.timestamp);
}

/// API caching service to reduce network requests
class CachedApiService {
  static final CachedApiService _instance = CachedApiService._internal();
  factory CachedApiService() => _instance;
  CachedApiService._internal();

  final Map<String, CachedResponse> _cache = {};
  final Duration defaultCacheDuration = const Duration(minutes: 5);

  /// Get cached data or fetch new data
  Future<T> getCached<T>({
    required String key,
    required Future<T> Function() fetcher,
    Duration? cacheDuration,
  }) async {
    final duration = cacheDuration ?? defaultCacheDuration;

    // Check if cached data exists and is still valid
    if (_cache.containsKey(key)) {
      final cached = _cache[key]!;
      if (DateTime.now().difference(cached.timestamp) < duration) {
        print('[CACHE] ✅ Hit: $key');
        return cached.data as T;
      } else {
        print('[CACHE] ⏰ Expired: $key');
      }
    } else {
      print('[CACHE] ❌ Miss: $key');
    }

    // Fetch new data
    final data = await fetcher();
    _cache[key] = CachedResponse(data, DateTime.now());
    return data;
  }

  /// Invalidate specific cache entry
  void invalidate(String key) {
    _cache.remove(key);
    print('[CACHE] 🗑️ Invalidated: $key');
  }

  /// Invalidate all cache entries matching a pattern
  void invalidatePattern(String pattern) {
    final keys = _cache.keys.where((key) => key.contains(pattern)).toList();
    for (final key in keys) {
      _cache.remove(key);
    }
    print('[CACHE] 🗑️ Invalidated pattern: $pattern (${keys.length} entries)');
  }

  /// Clear all cache
  void clearAll() {
    _cache.clear();
    print('[CACHE] 🗑️ Cleared all cache');
  }

  /// Get cache statistics
  Map<String, dynamic> getStats() {
    return {
      'totalEntries': _cache.length,
      'entries': _cache.keys.toList(),
    };
  }
}
