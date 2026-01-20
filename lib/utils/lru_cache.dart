import 'dart:collection';

/// A simple Least Recently Used (LRU) cache implementation.
///
/// When the cache reaches its maximum size, the least recently used entries
/// are automatically evicted to make room for new entries.
///
/// Usage:
/// ```dart
/// final cache = LruCache<String, String>(maxSize: 100);
/// cache.put('key', 'value');
/// final value = cache.get('key');
/// ```
class LruCache<K, V> {
  /// Maximum number of entries to store
  final int maxSize;

  /// Internal storage using LinkedHashMap for O(1) LRU operations
  final LinkedHashMap<K, V> _cache = LinkedHashMap<K, V>();

  /// Creates an LRU cache with the specified maximum size.
  ///
  /// [maxSize] must be greater than 0.
  LruCache({required this.maxSize}) : assert(maxSize > 0);

  /// Returns the number of entries currently in the cache.
  int get length => _cache.length;

  /// Returns true if the cache is empty.
  bool get isEmpty => _cache.isEmpty;

  /// Returns true if the cache is not empty.
  bool get isNotEmpty => _cache.isNotEmpty;

  /// Returns true if the cache contains an entry for [key].
  bool containsKey(K key) => _cache.containsKey(key);

  /// Returns the value for [key], or null if not found.
  ///
  /// This operation marks the entry as recently used.
  V? get(K key) {
    if (!_cache.containsKey(key)) {
      return null;
    }
    // Move to end (most recently used) by removing and re-adding
    final value = _cache.remove(key);
    _cache[key] = value as V;
    return value;
  }

  /// Returns the value for [key] without marking it as recently used.
  ///
  /// Use this when you need to check a value without affecting LRU order.
  V? peek(K key) => _cache[key];

  /// Stores [value] for [key] in the cache.
  ///
  /// If [key] already exists, the value is updated and marked as recently used.
  /// If the cache is full, the least recently used entry is evicted.
  void put(K key, V value) {
    // If key exists, remove it first (will be re-added at end)
    if (_cache.containsKey(key)) {
      _cache.remove(key);
    } else if (_cache.length >= maxSize) {
      // Cache is full, remove least recently used (first entry)
      _cache.remove(_cache.keys.first);
    }
    _cache[key] = value;
  }

  /// Operator access for getting values (same as [get]).
  V? operator [](K key) => get(key);

  /// Operator access for setting values (same as [put]).
  void operator []=(K key, V value) => put(key, value);

  /// Removes the entry for [key] if it exists.
  ///
  /// Returns the removed value, or null if [key] was not in the cache.
  V? remove(K key) => _cache.remove(key);

  /// Removes all entries from the cache.
  void clear() => _cache.clear();

  /// Returns all keys currently in the cache.
  Iterable<K> get keys => _cache.keys;

  /// Returns all values currently in the cache.
  Iterable<V> get values => _cache.values;

  /// Returns all entries currently in the cache.
  Iterable<MapEntry<K, V>> get entries => _cache.entries;
}

/// An LRU cache that can store null values and distinguish them from missing entries.
///
/// Regular LruCache returns null for both missing keys and keys with null values.
/// This class uses a wrapper to distinguish between the two cases.
class NullableLruCache<K, V> {
  final LruCache<K, _CacheEntry<V>> _cache;

  /// Creates a nullable LRU cache with the specified maximum size.
  NullableLruCache({required int maxSize}) : _cache = LruCache(maxSize: maxSize);

  /// Returns the number of entries currently in the cache.
  int get length => _cache.length;

  /// Returns true if the cache contains an entry for [key].
  bool containsKey(K key) => _cache.containsKey(key);

  /// Returns the value for [key], or null if not found.
  ///
  /// Note: This will also return null if the cached value is null.
  /// Use [containsKey] to distinguish between missing and null values.
  V? get(K key) => _cache.get(key)?.value;

  /// Stores [value] for [key] in the cache.
  ///
  /// The value can be null.
  void put(K key, V? value) => _cache.put(key, _CacheEntry(value));

  /// Operator access for getting values.
  V? operator [](K key) => get(key);

  /// Operator access for setting values.
  void operator []=(K key, V? value) => put(key, value);

  /// Removes the entry for [key] if it exists.
  V? remove(K key) => _cache.remove(key)?.value;

  /// Removes all entries from the cache.
  void clear() => _cache.clear();
}

/// Wrapper to store nullable values in the cache
class _CacheEntry<V> {
  final V? value;
  _CacheEntry(this.value);
}
