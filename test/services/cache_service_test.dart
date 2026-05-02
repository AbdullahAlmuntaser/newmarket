import 'package:flutter_test/flutter_test.dart';
import 'package:supermarket_erp/core/services/cache_service.dart';

void main() {
  group('CacheService Tests', () {
    late CacheService cacheService;

    setUp(() {
      cacheService = CacheService();
    });

    tearDown(() {
      cacheService.clear();
    });

    test('should cache data and retrieve it successfully', () async {
      const key = 'test_key';
      const value = {'id': 1, 'name': 'Test Item'};

      // Cache the data
      await cacheService.set(key, value, duration: const Duration(minutes: 5));

      // Retrieve the data
      final cachedData = await cacheService.get(key);

      expect(cachedData, equals(value));
    });

    test('should return null for expired cache', () async {
      const key = 'expired_key';
      const value = {'id': 2, 'name': 'Expired Item'};

      // Cache data with very short duration
      await cacheService.set(key, value, duration: const Duration(milliseconds: 50));
      
      // Wait for expiration
      await Future.delayed(const Duration(milliseconds: 100));

      final cachedData = await cacheService.get(key);

      expect(cachedData, isNull);
    });

    test('should clear all cache', () async {
      await cacheService.set('key1', {'data': 'value1'}, duration: const Duration(minutes: 5));
      await cacheService.set('key2', {'data': 'value2'}, duration: const Duration(minutes: 5));

      await cacheService.clear();

      expect(await cacheService.get('key1'), isNull);
      expect(await cacheService.get('key2'), isNull);
    });

    test('should remove specific key', () async {
      await cacheService.set('key1', {'data': 'value1'}, duration: const Duration(minutes: 5));
      await cacheService.set('key2', {'data': 'value2'}, duration: const Duration(minutes: 5));

      await cacheService.remove('key1');

      expect(await cacheService.get('key1'), isNull);
      expect(await cacheService.get('key2'), isNotNull);
    });
  });
}
