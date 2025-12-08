import '../models/media_item.dart';
import '../services/debug_logger.dart';
import '../constants/timings.dart';

/// Centralized cache service for all app data caching
/// This is a non-notifying service - it just stores and retrieves cached data
class CacheService {
  final DebugLogger _logger = DebugLogger();

  // Home screen row caching
  List<Album>? _cachedRecentAlbums;
  List<Artist>? _cachedDiscoverArtists;
  List<Album>? _cachedDiscoverAlbums;
  DateTime? _recentAlbumsLastFetched;
  DateTime? _discoverArtistsLastFetched;
  DateTime? _discoverAlbumsLastFetched;

  // Detail screen caching
  final Map<String, List<Track>> _albumTracksCache = {};
  final Map<String, DateTime> _albumTracksCacheTime = {};
  final Map<String, List<Track>> _playlistTracksCache = {};
  final Map<String, DateTime> _playlistTracksCacheTime = {};
  final Map<String, List<Album>> _artistAlbumsCache = {};
  final Map<String, DateTime> _artistAlbumsCacheTime = {};

  // Search results caching
  final Map<String, Map<String, List<MediaItem>>> _searchCache = {};
  final Map<String, DateTime> _searchCacheTime = {};

  // Player list caching
  DateTime? _playersLastFetched;

  // Player track cache (for smooth swipe transitions)
  final Map<String, Track?> _playerTrackCache = {};

  // ============================================================================
  // HOME SCREEN ROW CACHING
  // ============================================================================

  /// Check if recent albums cache is valid
  bool isRecentAlbumsCacheValid({bool forceRefresh = false}) {
    if (forceRefresh) return false;
    final now = DateTime.now();
    return _cachedRecentAlbums != null &&
        _recentAlbumsLastFetched != null &&
        now.difference(_recentAlbumsLastFetched!) < Timings.homeRowCacheDuration;
  }

  /// Get cached recent albums
  List<Album>? getCachedRecentAlbums() => _cachedRecentAlbums;

  /// Set cached recent albums
  void setCachedRecentAlbums(List<Album> albums) {
    _cachedRecentAlbums = albums;
    _recentAlbumsLastFetched = DateTime.now();
    _logger.log('✅ Cached ${albums.length} recent albums');
  }

  /// Check if discover artists cache is valid
  bool isDiscoverArtistsCacheValid({bool forceRefresh = false}) {
    if (forceRefresh) return false;
    final now = DateTime.now();
    return _cachedDiscoverArtists != null &&
        _discoverArtistsLastFetched != null &&
        now.difference(_discoverArtistsLastFetched!) < Timings.homeRowCacheDuration;
  }

  /// Get cached discover artists
  List<Artist>? getCachedDiscoverArtists() => _cachedDiscoverArtists;

  /// Set cached discover artists
  void setCachedDiscoverArtists(List<Artist> artists) {
    _cachedDiscoverArtists = artists;
    _discoverArtistsLastFetched = DateTime.now();
    _logger.log('✅ Cached ${artists.length} discover artists');
  }

  /// Check if discover albums cache is valid
  bool isDiscoverAlbumsCacheValid({bool forceRefresh = false}) {
    if (forceRefresh) return false;
    final now = DateTime.now();
    return _cachedDiscoverAlbums != null &&
        _discoverAlbumsLastFetched != null &&
        now.difference(_discoverAlbumsLastFetched!) < Timings.homeRowCacheDuration;
  }

  /// Get cached discover albums
  List<Album>? getCachedDiscoverAlbums() => _cachedDiscoverAlbums;

  /// Set cached discover albums
  void setCachedDiscoverAlbums(List<Album> albums) {
    _cachedDiscoverAlbums = albums;
    _discoverAlbumsLastFetched = DateTime.now();
    _logger.log('✅ Cached ${albums.length} discover albums');
  }

  /// Invalidate home screen cache (call on pull-to-refresh)
  void invalidateHomeCache() {
    _recentAlbumsLastFetched = null;
    _discoverArtistsLastFetched = null;
    _discoverAlbumsLastFetched = null;
    _logger.log('🗑️ Home screen cache invalidated');
  }

  // ============================================================================
  // DETAIL SCREEN CACHING
  // ============================================================================

  /// Check if album tracks cache is valid
  bool isAlbumTracksCacheValid(String cacheKey, {bool forceRefresh = false}) {
    if (forceRefresh) return false;
    final now = DateTime.now();
    final cacheTime = _albumTracksCacheTime[cacheKey];
    return _albumTracksCache.containsKey(cacheKey) &&
        cacheTime != null &&
        now.difference(cacheTime) < const Duration(minutes: 5);
  }

  /// Get cached album tracks
  List<Track>? getCachedAlbumTracks(String cacheKey) => _albumTracksCache[cacheKey];

  /// Set cached album tracks
  void setCachedAlbumTracks(String cacheKey, List<Track> tracks) {
    _albumTracksCache[cacheKey] = tracks;
    _albumTracksCacheTime[cacheKey] = DateTime.now();
    _logger.log('✅ Cached ${tracks.length} tracks for album $cacheKey');
  }

  /// Invalidate album tracks cache
  void invalidateAlbumTracksCache(String albumId) {
    _albumTracksCache.remove(albumId);
    _albumTracksCacheTime.remove(albumId);
  }

  /// Check if playlist tracks cache is valid
  bool isPlaylistTracksCacheValid(String cacheKey, {bool forceRefresh = false}) {
    if (forceRefresh) return false;
    final now = DateTime.now();
    final cacheTime = _playlistTracksCacheTime[cacheKey];
    return _playlistTracksCache.containsKey(cacheKey) &&
        cacheTime != null &&
        now.difference(cacheTime) < const Duration(minutes: 5);
  }

  /// Get cached playlist tracks
  List<Track>? getCachedPlaylistTracks(String cacheKey) => _playlistTracksCache[cacheKey];

  /// Set cached playlist tracks
  void setCachedPlaylistTracks(String cacheKey, List<Track> tracks) {
    _playlistTracksCache[cacheKey] = tracks;
    _playlistTracksCacheTime[cacheKey] = DateTime.now();
    _logger.log('✅ Cached ${tracks.length} tracks for playlist $cacheKey');
  }

  /// Invalidate playlist tracks cache
  void invalidatePlaylistTracksCache(String playlistId) {
    _playlistTracksCache.remove(playlistId);
    _playlistTracksCacheTime.remove(playlistId);
  }

  /// Check if artist albums cache is valid
  bool isArtistAlbumsCacheValid(String cacheKey, {bool forceRefresh = false}) {
    if (forceRefresh) return false;
    final now = DateTime.now();
    final cacheTime = _artistAlbumsCacheTime[cacheKey];
    return _artistAlbumsCache.containsKey(cacheKey) &&
        cacheTime != null &&
        now.difference(cacheTime) < Timings.homeRowCacheDuration;
  }

  /// Get cached artist albums
  List<Album>? getCachedArtistAlbums(String cacheKey) => _artistAlbumsCache[cacheKey];

  /// Set cached artist albums
  void setCachedArtistAlbums(String cacheKey, List<Album> albums) {
    _artistAlbumsCache[cacheKey] = albums;
    _artistAlbumsCacheTime[cacheKey] = DateTime.now();
    _logger.log('✅ Cached ${albums.length} albums for artist $cacheKey');
  }

  // ============================================================================
  // SEARCH CACHING
  // ============================================================================

  /// Check if search cache is valid
  bool isSearchCacheValid(String cacheKey, {bool forceRefresh = false}) {
    if (forceRefresh) return false;
    final now = DateTime.now();
    final cacheTime = _searchCacheTime[cacheKey];
    return _searchCache.containsKey(cacheKey) &&
        cacheTime != null &&
        now.difference(cacheTime) < Timings.homeRowCacheDuration;
  }

  /// Get cached search results
  Map<String, List<MediaItem>>? getCachedSearchResults(String cacheKey) => _searchCache[cacheKey];

  /// Set cached search results
  void setCachedSearchResults(String cacheKey, Map<String, List<MediaItem>> results) {
    _searchCache[cacheKey] = results;
    _searchCacheTime[cacheKey] = DateTime.now();
    _logger.log('✅ Cached search results for "$cacheKey"');
  }

  // ============================================================================
  // PLAYER CACHING
  // ============================================================================

  /// Check if players cache is valid
  bool isPlayersCacheValid({bool forceRefresh = false}) {
    if (forceRefresh) return false;
    final now = DateTime.now();
    return _playersLastFetched != null &&
        now.difference(_playersLastFetched!) < Timings.playersCacheDuration;
  }

  /// Update players cache timestamp
  void updatePlayersLastFetched() {
    _playersLastFetched = DateTime.now();
  }

  /// Get cached track for a player (used for smooth swipe transitions)
  Track? getCachedTrackForPlayer(String playerId) => _playerTrackCache[playerId];

  /// Set cached track for a player
  void setCachedTrackForPlayer(String playerId, Track? track) {
    _playerTrackCache[playerId] = track;
  }

  // ============================================================================
  // CLEAR ALL
  // ============================================================================

  /// Clear all detail caches (call on disconnect/reconnect)
  void clearAllDetailCaches() {
    _albumTracksCache.clear();
    _albumTracksCacheTime.clear();
    _playlistTracksCache.clear();
    _playlistTracksCacheTime.clear();
    _artistAlbumsCache.clear();
    _artistAlbumsCacheTime.clear();
    _searchCache.clear();
    _searchCacheTime.clear();
    _playerTrackCache.clear();
    _logger.log('🗑️ All detail caches cleared');
  }

  /// Clear all caches
  void clearAll() {
    invalidateHomeCache();
    clearAllDetailCaches();
    _playersLastFetched = null;
  }
}
