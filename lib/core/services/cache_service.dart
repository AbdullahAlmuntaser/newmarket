import 'package:flutter/foundation.dart';
import 'dart:async';

/// Cache entry with expiration support
class CacheEntry<T> {
  final T data;
  final DateTime expiresAt;

  CacheEntry(this.data, Duration ttl) : expiresAt = DateTime.now().add(ttl);

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// In-memory cache service for frequently accessed data
/// 
/// This service provides:
/// - Fast in-memory caching for static/slowly changing data
/// - Automatic expiration of cached items
/// - Thread-safe operations
/// - Memory management with max size limits
class CacheService {
  static final CacheService _instance = CacheService._internal();
  factory CacheService() => _instance;
  CacheService._internal();

  final Map<String, CacheEntry<dynamic>> _cache = {};
  final Map<String, Timer> _timers = {};
  
  // Configuration
  static const Duration _defaultTTL = Duration(minutes: 5);
  static const int _maxCacheSize = 1000;

  /// Get cached data or null if not found/expired
  T? get<T>(String key) {
    final entry = _cache[key];
    if (entry == null) return null;
    
    if (entry.isExpired) {
      remove(key);
      return null;
    }
    
    try {
      return entry.data as T;
    } catch (e) {
      debugPrint('Cache type mismatch for key $key: $e');
      remove(key);
      return null;
    }
  }

  /// Cache data with optional TTL
  void set<T>(String key, T value, {Duration? ttl}) {
    // Check cache size limit
    if (_cache.length >= _maxCacheSize) {
      _evictOldest();
    }

    // Remove existing timer if any
    _timers[key]?.cancel();
    
    final effectiveTtl = ttl ?? _defaultTTL;
    _cache[key] = CacheEntry<T>(value, effectiveTtl);

    // Set up auto-removal timer
    _timers[key] = Timer(effectiveTtl, () {
      remove(key);
    });
  }

  /// Remove cached item
  void remove(String key) {
    _timers[key]?.cancel();
    _timers.remove(key);
    _cache.remove(key);
  }

  /// Clear all cache
  void clear() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    _cache.clear();
  }

  /// Clear cache by pattern (e.g., 'products_*')
  void clearByPattern(String pattern) {
    final keysToRemove = <String>[];
    final regex = RegExp(pattern.replaceAll('*', '.*'));
    
    for (final key in _cache.keys) {
      if (regex.hasMatch(key)) {
        keysToRemove.add(key);
      }
    }
    
    for (final key in keysToRemove) {
      remove(key);
    }
  }

  /// Check if key exists and is valid
  bool containsKey(String key) {
    final entry = _cache[key];
    if (entry == null) return false;
    
    if (entry.isExpired) {
      remove(key);
      return false;
    }
    
    return true;
  }

  /// Get cache statistics
  Map<String, dynamic> getStats() {
    final now = DateTime.now();
    var expiredCount = 0;
    
    for (final entry in _cache.values) {
      if (entry.isExpired) {
        expiredCount++;
      }
    }
    
    return {
      'total_entries': _cache.length,
      'expired_entries': expiredCount,
      'active_timers': _timers.length,
      'memory_usage_kb': (_cache.length * 100 / 1024).toStringAsFixed(2), // Rough estimate
    };
  }

  /// Evict oldest entries when cache is full
  void _evictOldest({int count = 10}) {
    final entries = _cache.entries.toList()
      ..sort((a, b) => a.value.expiresAt.compareTo(b.value.expiresAt));
    
    final toRemove = entries.take(count);
    for (final entry in toRemove) {
      remove(entry.key);
    }
    
    debugPrint('Cache: Evicted ${toRemove.length} oldest entries');
  }

  /// Preload data into cache
  Future<void> preload<T>(
    String key,
    Future<T> Function() loader, {
    Duration? ttl,
  }) async {
    if (!containsKey(key)) {
      try {
        final data = await loader();
        set(key, data, ttl: ttl);
        debugPrint('Cache: Preloaded $key');
      } catch (e) {
        debugPrint('Cache: Failed to preload $key: $e');
      }
    }
  }

  /// Get from cache or load if not present
  Future<T?> getOrLoad<T>(
    String key,
    Future<T> Function() loader, {
    Duration? ttl,
  }) async {
    final cached = get<T>(key);
    if (cached != null) {
      return cached;
    }

    try {
      final data = await loader();
      set(key, data, ttl: ttl);
      return data;
    } catch (e) {
      debugPrint('Cache: Load failed for $key: $e');
      return null;
    }
  }
}

/// Cache keys constants for consistency
class CacheKeys {
  // Master data
  static const String categories = 'categories_all';
  static const String units = 'units_all';
  static const String warehouses = 'warehouses_all';
  static const String branches = 'branches_all';
  static const String costCenters = 'cost_centers_all';
  static const String glAccounts = 'gl_accounts_all';
  static const String currencies = 'currencies_all';
  
  // Products
  static String product(String id) => 'product_$id';
  static String productByBarcode(String barcode) => 'product_barcode_$barcode';
  static String productBySku(String sku) => 'product_sku_$sku';
  static const String productsLowStock = 'products_low_stock';
  static const String productsCategories = 'products_categories';
  
  // Customers & Suppliers
  static String customer(String id) => 'customer_$id';
  static String customerByPhone(String phone) => 'customer_phone_$phone';
  static String supplier(String id) => 'supplier_$id';
  static const String customersAll = 'customers_all';
  static const String quickCustomers = 'quick_customers';
  static const String suppliersAll = 'suppliers_all';
  
  // Settings
  static const String appSettings = 'app_settings';
  static const String userPreferences = 'user_preferences';
  static const String activeBranch = 'active_branch';
  static const String activeWarehouse = 'active_warehouse';
}
