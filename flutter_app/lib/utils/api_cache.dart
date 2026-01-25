import 'dart:collection';

/// Simple in-memory cache for API responses
class ApiCache {
  static final ApiCache _instance = ApiCache._internal();
  factory ApiCache() => _instance;
  ApiCache._internal();

  final _cache = HashMap<String, CachedResponse>();
  
  /// Get cached data or fetch new data
  Future<T> getCached<T>({
    required String key,
    required Future<T> Function() fetcher,
    Duration ttl = const Duration(minutes: 5),
  }) async {
    final cached = _cache[key];
    
    // Return cached data if valid
    if (cached != null && !cached.isExpired) {
      return cached.data as T;
    }
    
    // Fetch new data
    final data = await fetcher();
    _cache[key] = CachedResponse(
      data: data,
      expiresAt: DateTime.now().add(ttl),
    );
    
    return data;
  }
  
  /// Get cached data without fetching (for optimistic UI)
  T? get<T>(String key) {
    final cached = _cache[key];
    if (cached != null && !cached.isExpired) {
      return cached.data as T;
    }
    return null;
  }
  
  /// Manually set cache
  void set(String key, dynamic data, {Duration ttl = const Duration(minutes: 5)}) {
    _cache[key] = CachedResponse(
      data: data,
      expiresAt: DateTime.now().add(ttl),
    );
  }
  
  /// Clear specific cache entry
  void invalidate(String key) {
    _cache.remove(key);
  }
  
  /// Clear all cache
  void clearAll() {
    _cache.clear();
  }
  
  /// Clear expired entries
  void clearExpired() {
    _cache.removeWhere((key, value) => value.isExpired);
  }
}

class CachedResponse {
  final dynamic data;
  final DateTime expiresAt;
  
  CachedResponse({
    required this.data,
    required this.expiresAt,
  });
  
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
