import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../database/database.dart' show BatchCacheItem;
import '../models/media_item.dart';
import 'database_service.dart';
import 'debug_logger.dart';
import 'music_assistant_api.dart';
import 'settings_service.dart';

/// Sync status for UI indicators
enum SyncStatus {
  idle,
  syncing,
  completed,
  error,
}

/// Service for background library synchronization
/// Loads from database cache first, then syncs from MA API in background
/// Supports per-provider sync for accurate client-side filtering
class SyncService with ChangeNotifier {
  static SyncService? _instance;
  static final _logger = DebugLogger();

  SyncService._();

  static SyncService get instance {
    _instance ??= SyncService._();
    return _instance!;
  }

  DatabaseService get _db => DatabaseService.instance;

  // Sync state
  SyncStatus _status = SyncStatus.idle;
  String? _lastError;
  DateTime? _lastSyncTime;
  bool _isSyncing = false;

  // Cached data (loaded from DB, updated after sync)
  List<Album> _cachedAlbums = [];
  List<Artist> _cachedArtists = [];
  List<Audiobook> _cachedAudiobooks = [];
  List<Playlist> _cachedPlaylists = [];
  List<Track> _cachedTracks = [];
  List<MediaItem> _cachedPodcasts = [];

  // Source provider tracking for client-side filtering
  // Maps itemId -> list of provider instance IDs that provided the item
  Map<String, List<String>> _albumSourceProviders = {};
  Map<String, List<String>> _artistSourceProviders = {};
  Map<String, List<String>> _audiobookSourceProviders = {};
  Map<String, List<String>> _playlistSourceProviders = {};
  Map<String, List<String>> _trackSourceProviders = {};

  // Getters
  SyncStatus get status => _status;
  String? get lastError => _lastError;
  DateTime? get lastSyncTime => _lastSyncTime;
  bool get isSyncing => _isSyncing;
  List<Album> get cachedAlbums => _cachedAlbums;
  List<Artist> get cachedArtists => _cachedArtists;
  List<Audiobook> get cachedAudiobooks => _cachedAudiobooks;
  List<Playlist> get cachedPlaylists => _cachedPlaylists;
  List<Track> get cachedTracks => _cachedTracks;
  List<MediaItem> get cachedPodcasts => _cachedPodcasts;
  bool get hasCache => _cachedAlbums.isNotEmpty || _cachedArtists.isNotEmpty ||
                       _cachedAudiobooks.isNotEmpty || _cachedPlaylists.isNotEmpty ||
                       _cachedTracks.isNotEmpty || _cachedPodcasts.isNotEmpty;

  // Source provider getters for client-side filtering
  Map<String, List<String>> get albumSourceProviders => _albumSourceProviders;
  Map<String, List<String>> get artistSourceProviders => _artistSourceProviders;
  Map<String, List<String>> get audiobookSourceProviders => _audiobookSourceProviders;
  Map<String, List<String>> get playlistSourceProviders => _playlistSourceProviders;
  Map<String, List<String>> get trackSourceProviders => _trackSourceProviders;

  /// Load library data from database cache (instant)
  /// Call this on app startup for immediate data
  /// Also loads source provider info for client-side filtering
  Future<void> loadFromCache() async {
    if (!_db.isInitialized) {
      _logger.log('⚠️ Database not initialized, skipping cache load');
      return;
    }

    try {
      _logger.log('📦 Loading library from database cache...');

      // Load albums from cache with source providers
      final albumDataWithProviders = await _db.getCachedItemsWithProviders('album');
      _cachedAlbums = [];
      _albumSourceProviders = {};
      for (final (data, providers) in albumDataWithProviders) {
        try {
          final album = Album.fromJson(data);
          _cachedAlbums.add(album);
          if (providers.isNotEmpty) {
            _albumSourceProviders[album.itemId] = providers;
          }
        } catch (e) {
          _logger.log('⚠️ Failed to parse cached album: $e');
        }
      }

      // Load artists from cache with source providers
      final artistDataWithProviders = await _db.getCachedItemsWithProviders('artist');
      _cachedArtists = [];
      _artistSourceProviders = {};
      for (final (data, providers) in artistDataWithProviders) {
        try {
          final artist = Artist.fromJson(data);
          _cachedArtists.add(artist);
          if (providers.isNotEmpty) {
            _artistSourceProviders[artist.itemId] = providers;
          }
        } catch (e) {
          _logger.log('⚠️ Failed to parse cached artist: $e');
        }
      }

      // Load audiobooks from cache with source providers
      final audiobookDataWithProviders = await _db.getCachedItemsWithProviders('audiobook');
      _cachedAudiobooks = [];
      _audiobookSourceProviders = {};
      for (final (data, providers) in audiobookDataWithProviders) {
        try {
          final audiobook = Audiobook.fromJson(data);
          _cachedAudiobooks.add(audiobook);
          if (providers.isNotEmpty) {
            _audiobookSourceProviders[audiobook.itemId] = providers;
          }
        } catch (e) {
          _logger.log('⚠️ Failed to parse cached audiobook: $e');
        }
      }

      // Load playlists from cache with source providers
      final playlistDataWithProviders = await _db.getCachedItemsWithProviders('playlist');
      _cachedPlaylists = [];
      _playlistSourceProviders = {};
      for (final (data, providers) in playlistDataWithProviders) {
        try {
          final playlist = Playlist.fromJson(data);
          _cachedPlaylists.add(playlist);
          if (providers.isNotEmpty) {
            _playlistSourceProviders[playlist.itemId] = providers;
          }
        } catch (e) {
          _logger.log('⚠️ Failed to parse cached playlist: $e');
        }
      }

      // Load tracks from cache with source providers
      final trackDataWithProviders = await _db.getCachedItemsWithProviders('track');
      _cachedTracks = [];
      _trackSourceProviders = {};
      for (final (data, providers) in trackDataWithProviders) {
        try {
          final track = Track.fromJson(data);
          _cachedTracks.add(track);
          if (providers.isNotEmpty) {
            _trackSourceProviders[track.itemId] = providers;
          }
        } catch (e) {
          _logger.log('⚠️ Failed to parse cached track: $e');
        }
      }

      // Load podcasts from cache (no source provider tracking - API doesn't support filtering)
      final podcastData = await _db.getCachedItems('podcast');
      _cachedPodcasts = [];
      for (final data in podcastData) {
        try {
          _cachedPodcasts.add(MediaItem.fromJson(data));
        } catch (e) {
          _logger.log('⚠️ Failed to parse cached podcast: $e');
        }
      }

      _logger.log('📦 Loaded ${_cachedAlbums.length} albums, ${_cachedArtists.length} artists, '
                  '${_cachedAudiobooks.length} audiobooks, ${_cachedPlaylists.length} playlists, '
                  '${_cachedTracks.length} tracks, ${_cachedPodcasts.length} podcasts from cache');
      _logger.log('📦 Source providers: ${_albumSourceProviders.length} albums, ${_artistSourceProviders.length} artists, ${_trackSourceProviders.length} tracks tracked');
      notifyListeners();
    } catch (e) {
      _logger.log('❌ Failed to load from cache: $e');
    }
  }

  /// Sync library data from MA API in background
  /// Updates database cache and notifies listeners when complete
  /// [providerInstanceIds] - list of provider IDs to sync (fetches each provider separately for accurate source tracking)
  Future<void> syncFromApi(
    MusicAssistantAPI api, {
    bool force = false,
    List<String>? providerInstanceIds,
  }) async {
    if (_isSyncing) {
      _logger.log('🔄 Sync already in progress, skipping');
      return;
    }

    if (!_db.isInitialized) {
      _logger.log('⚠️ Database not initialized, skipping sync');
      return;
    }

    // Check if sync is needed (default: every 5 minutes)
    // Always sync if cache is empty (no albums AND no artists loaded)
    final cacheEmpty = _cachedAlbums.isEmpty && _cachedArtists.isEmpty;
    if (!force && !cacheEmpty) {
      final albumsNeedSync = await _db.needsSync('albums', maxAge: const Duration(minutes: 5));
      final artistsNeedSync = await _db.needsSync('artists', maxAge: const Duration(minutes: 5));
      final audiobooksNeedSync = await _db.needsSync('audiobooks', maxAge: const Duration(minutes: 5));
      final playlistsNeedSync = await _db.needsSync('playlists', maxAge: const Duration(minutes: 5));
      final tracksNeedSync = await _db.needsSync('tracks', maxAge: const Duration(minutes: 5));
      final podcastsNeedSync = await _db.needsSync('podcasts', maxAge: const Duration(minutes: 5));

      if (!albumsNeedSync && !artistsNeedSync && !audiobooksNeedSync && !playlistsNeedSync && !tracksNeedSync && !podcastsNeedSync) {
        _logger.log('✅ Cache is fresh, skipping sync');
        return;
      }
    }

    _isSyncing = true;
    _status = SyncStatus.syncing;
    _lastError = null;
    notifyListeners();

    try {
      _logger.log('🔄 Starting background library sync...');

      // Read artist filter setting - when ON, only fetch artists that have albums
      final showOnlyArtistsWithAlbums = await SettingsService.getShowOnlyArtistsWithAlbums();
      _logger.log('🎨 Sync using albumArtistsOnly: $showOnlyArtistsWithAlbums');

      // Only clear cache for full syncs (no specific providers)
      // Partial syncs preserve items from disabled providers for instant toggle-on
      final isPartialSync = providerInstanceIds != null && providerInstanceIds.isNotEmpty;
      if (!isPartialSync) {
        await _db.clearCacheForType('album');
        await _db.clearCacheForType('artist');
        await _db.clearCacheForType('audiobook');
        await _db.clearCacheForType('playlist');
        await _db.clearCacheForType('track');
        await _db.clearCacheForType('podcast');
      }

      // Build NEW source tracking maps - don't modify existing until sync is complete
      // This prevents UI flicker from partial tracking during sync
      final syncingProviders = providerInstanceIds?.toSet() ?? <String>{};
      final newAlbumSourceProviders = <String, List<String>>{};
      final newArtistSourceProviders = <String, List<String>>{};
      final newAudiobookSourceProviders = <String, List<String>>{};
      final newPlaylistSourceProviders = <String, List<String>>{};
      final newTrackSourceProviders = <String, List<String>>{};

      // For partial syncs, copy tracking from non-syncing providers
      if (isPartialSync) {
        for (final entry in _albumSourceProviders.entries) {
          final preserved = entry.value.where((p) => !syncingProviders.contains(p)).toList();
          if (preserved.isNotEmpty) newAlbumSourceProviders[entry.key] = preserved;
        }
        for (final entry in _artistSourceProviders.entries) {
          final preserved = entry.value.where((p) => !syncingProviders.contains(p)).toList();
          if (preserved.isNotEmpty) newArtistSourceProviders[entry.key] = preserved;
        }
        for (final entry in _audiobookSourceProviders.entries) {
          final preserved = entry.value.where((p) => !syncingProviders.contains(p)).toList();
          if (preserved.isNotEmpty) newAudiobookSourceProviders[entry.key] = preserved;
        }
        for (final entry in _playlistSourceProviders.entries) {
          final preserved = entry.value.where((p) => !syncingProviders.contains(p)).toList();
          if (preserved.isNotEmpty) newPlaylistSourceProviders[entry.key] = preserved;
        }
        for (final entry in _trackSourceProviders.entries) {
          final preserved = entry.value.where((p) => !syncingProviders.contains(p)).toList();
          if (preserved.isNotEmpty) newTrackSourceProviders[entry.key] = preserved;
        }
      }

      // Collect all items (deduped by itemId, but tracking all source providers)
      final albumMap = <String, Album>{};
      final artistMap = <String, Artist>{};
      final audiobookMap = <String, Audiobook>{};
      final playlistMap = <String, Playlist>{};
      final trackMap = <String, Track>{};

      // If specific providers are requested, sync each separately for accurate source tracking
      if (providerInstanceIds != null && providerInstanceIds.isNotEmpty) {
        _logger.log('🔒 Per-provider sync for ${providerInstanceIds.length} providers');

        for (final providerId in providerInstanceIds) {
          _logger.log('  📡 Syncing provider: $providerId');

          // Fetch from this specific provider
          final results = await Future.wait([
            api.getAlbums(limit: 1000, providerInstanceIds: [providerId]),
            api.getArtists(limit: 1000, albumArtistsOnly: showOnlyArtistsWithAlbums, providerInstanceIds: [providerId]),
            api.getAudiobooks(limit: 1000, providerInstanceIds: [providerId]),
            api.getPlaylists(limit: 1000, providerInstanceIds: [providerId]),
            api.getTracks(limit: 5000, providerInstanceIds: [providerId]),
          ]);

          final albums = results[0] as List<Album>;
          final artists = results[1] as List<Artist>;
          final audiobooks = results[2] as List<Audiobook>;
          final playlists = results[3] as List<Playlist>;
          final tracks = results[4] as List<Track>;

          _logger.log('  📥 Got ${albums.length} albums, ${artists.length} artists, ${audiobooks.length} audiobooks, ${tracks.length} tracks from $providerId');

          // Add to maps and track source provider in NEW tracking maps
          for (final album in albums) {
            albumMap[album.itemId] = album;
            newAlbumSourceProviders.putIfAbsent(album.itemId, () => []);
            if (!newAlbumSourceProviders[album.itemId]!.contains(providerId)) {
              newAlbumSourceProviders[album.itemId]!.add(providerId);
            }
          }
          for (final artist in artists) {
            artistMap[artist.itemId] = artist;
            newArtistSourceProviders.putIfAbsent(artist.itemId, () => []);
            if (!newArtistSourceProviders[artist.itemId]!.contains(providerId)) {
              newArtistSourceProviders[artist.itemId]!.add(providerId);
            }
          }
          for (final audiobook in audiobooks) {
            audiobookMap[audiobook.itemId] = audiobook;
            newAudiobookSourceProviders.putIfAbsent(audiobook.itemId, () => []);
            if (!newAudiobookSourceProviders[audiobook.itemId]!.contains(providerId)) {
              newAudiobookSourceProviders[audiobook.itemId]!.add(providerId);
            }
          }
          for (final playlist in playlists) {
            playlistMap[playlist.itemId] = playlist;
            newPlaylistSourceProviders.putIfAbsent(playlist.itemId, () => []);
            if (!newPlaylistSourceProviders[playlist.itemId]!.contains(providerId)) {
              newPlaylistSourceProviders[playlist.itemId]!.add(providerId);
            }
          }
          for (final track in tracks) {
            trackMap[track.itemId] = track;
            newTrackSourceProviders.putIfAbsent(track.itemId, () => []);
            if (!newTrackSourceProviders[track.itemId]!.contains(providerId)) {
              newTrackSourceProviders[track.itemId]!.add(providerId);
            }
          }
        }
      } else {
        // No provider filter - fetch all at once (faster, but no source tracking)
        _logger.log('📡 Fetching from all providers (no source tracking)');

        final results = await Future.wait([
          api.getAlbums(limit: 1000),
          api.getArtists(limit: 1000, albumArtistsOnly: showOnlyArtistsWithAlbums),
          api.getAudiobooks(limit: 1000),
          api.getPlaylists(limit: 1000),
          api.getTracks(limit: 5000),
        ]);

        for (final album in results[0] as List<Album>) {
          albumMap[album.itemId] = album;
        }
        for (final artist in results[1] as List<Artist>) {
          artistMap[artist.itemId] = artist;
        }
        for (final audiobook in results[2] as List<Audiobook>) {
          audiobookMap[audiobook.itemId] = audiobook;
        }
        for (final playlist in results[3] as List<Playlist>) {
          playlistMap[playlist.itemId] = playlist;
        }
        for (final track in results[4] as List<Track>) {
          trackMap[track.itemId] = track;
        }
      }

      final albums = albumMap.values.toList();
      final artists = artistMap.values.toList();
      final audiobooks = audiobookMap.values.toList();
      final playlists = playlistMap.values.toList();
      final tracks = trackMap.values.toList();

      // Fetch podcasts separately (API doesn't support providerInstanceIds)
      List<MediaItem> podcasts = [];
      try {
        podcasts = await api.getPodcasts(limit: 100);
      } catch (e) {
        _logger.log('⚠️ Failed to fetch podcasts: $e');
      }

      _logger.log('📥 Total: ${albums.length} albums, ${artists.length} artists, '
                  '${audiobooks.length} audiobooks, ${playlists.length} playlists, '
                  '${tracks.length} tracks, ${podcasts.length} podcasts');

      // Save to database cache with source provider info (using NEW tracking maps)
      await _saveAlbumsToCache(albums, newAlbumSourceProviders);
      await _saveArtistsToCache(artists, newArtistSourceProviders);
      await _saveAudiobooksToCache(audiobooks, newAudiobookSourceProviders);
      await _savePlaylistsToCache(playlists, newPlaylistSourceProviders);
      await _saveTracksToCache(tracks, newTrackSourceProviders);
      await _savePodcastsToCache(podcasts);

      // Update sync metadata
      await _db.updateSyncMetadata('albums', albums.length);
      await _db.updateSyncMetadata('artists', artists.length);
      await _db.updateSyncMetadata('audiobooks', audiobooks.length);
      await _db.updateSyncMetadata('playlists', playlists.length);
      await _db.updateSyncMetadata('tracks', tracks.length);
      await _db.updateSyncMetadata('podcasts', podcasts.length);

      // Update in-memory cache
      if (isPartialSync) {
        // Partial sync: merge with existing cache to preserve items from disabled providers
        final albumIds = albums.map((a) => a.itemId).toSet();
        final artistIds = artists.map((a) => a.itemId).toSet();
        final audiobookIds = audiobooks.map((a) => a.itemId).toSet();
        final playlistIds = playlists.map((p) => p.itemId).toSet();
        final trackIds = tracks.map((t) => t.itemId).toSet();

        // Keep items not in current sync, add/update items from sync
        _cachedAlbums = [
          ..._cachedAlbums.where((a) => !albumIds.contains(a.itemId)),
          ...albums,
        ];
        _cachedArtists = [
          ..._cachedArtists.where((a) => !artistIds.contains(a.itemId)),
          ...artists,
        ];
        _cachedAudiobooks = [
          ..._cachedAudiobooks.where((a) => !audiobookIds.contains(a.itemId)),
          ...audiobooks,
        ];
        _cachedPlaylists = [
          ..._cachedPlaylists.where((p) => !playlistIds.contains(p.itemId)),
          ...playlists,
        ];
        _cachedTracks = [
          ..._cachedTracks.where((t) => !trackIds.contains(t.itemId)),
          ...tracks,
        ];
      } else {
        // Full sync: replace entire cache
        _cachedAlbums = albums;
        _cachedArtists = artists;
        _cachedAudiobooks = audiobooks;
        _cachedPlaylists = playlists;
        _cachedTracks = tracks;
      }
      // Podcasts always full replace (no per-provider tracking)
      _cachedPodcasts = podcasts;

      // Atomically swap in the new source tracking maps
      // This ensures filtering always sees complete data, never partial
      _albumSourceProviders = newAlbumSourceProviders;
      _artistSourceProviders = newArtistSourceProviders;
      _audiobookSourceProviders = newAudiobookSourceProviders;
      _playlistSourceProviders = newPlaylistSourceProviders;
      _trackSourceProviders = newTrackSourceProviders;

      _lastSyncTime = DateTime.now();
      _status = SyncStatus.completed;

      _logger.log('✅ Library sync complete');
      _logger.log('📊 Source tracking: ${_albumSourceProviders.length} albums, ${_artistSourceProviders.length} artists, ${_audiobookSourceProviders.length} audiobooks, ${_trackSourceProviders.length} tracks have provider info');
    } catch (e) {
      _logger.log('❌ Library sync failed: $e');
      _status = SyncStatus.error;
      _lastError = e.toString();
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  /// Save albums to database cache with source provider tracking (batched)
  Future<void> _saveAlbumsToCache(List<Album> albums, Map<String, List<String>> sourceProviders) async {
    final batchItems = <BatchCacheItem>[];
    for (final album in albums) {
      final providers = sourceProviders[album.itemId] ?? <String>[];
      batchItems.add(BatchCacheItem(
        itemType: 'album',
        itemId: album.itemId,
        data: jsonEncode(album.toJson()),
        sourceProviders: providers,
      ));
    }
    try {
      await _db.batchCacheItems(batchItems);
      _logger.log('💾 Batch saved ${albums.length} albums to cache');
    } catch (e) {
      _logger.log('⚠️ Failed to batch cache albums: $e');
    }
  }

  /// Save artists to database cache with source provider tracking (batched)
  Future<void> _saveArtistsToCache(List<Artist> artists, Map<String, List<String>> sourceProviders) async {
    final batchItems = <BatchCacheItem>[];
    for (final artist in artists) {
      final providers = sourceProviders[artist.itemId] ?? <String>[];
      batchItems.add(BatchCacheItem(
        itemType: 'artist',
        itemId: artist.itemId,
        data: jsonEncode(artist.toJson()),
        sourceProviders: providers,
      ));
    }
    try {
      await _db.batchCacheItems(batchItems);
      _logger.log('💾 Batch saved ${artists.length} artists to cache');
    } catch (e) {
      _logger.log('⚠️ Failed to batch cache artists: $e');
    }
  }

  /// Save audiobooks to database cache with source provider tracking (batched)
  Future<void> _saveAudiobooksToCache(List<Audiobook> audiobooks, Map<String, List<String>> sourceProviders) async {
    final batchItems = <BatchCacheItem>[];
    for (final audiobook in audiobooks) {
      final providers = sourceProviders[audiobook.itemId] ?? <String>[];
      batchItems.add(BatchCacheItem(
        itemType: 'audiobook',
        itemId: audiobook.itemId,
        data: jsonEncode(audiobook.toJson()),
        sourceProviders: providers,
      ));
    }
    try {
      await _db.batchCacheItems(batchItems);
      _logger.log('💾 Batch saved ${audiobooks.length} audiobooks to cache');
    } catch (e) {
      _logger.log('⚠️ Failed to batch cache audiobooks: $e');
    }
  }

  /// Save playlists to database cache with source provider tracking (batched)
  Future<void> _savePlaylistsToCache(List<Playlist> playlists, Map<String, List<String>> sourceProviders) async {
    final batchItems = <BatchCacheItem>[];
    for (final playlist in playlists) {
      final providers = sourceProviders[playlist.itemId] ?? <String>[];
      batchItems.add(BatchCacheItem(
        itemType: 'playlist',
        itemId: playlist.itemId,
        data: jsonEncode(playlist.toJson()),
        sourceProviders: providers,
      ));
    }
    try {
      await _db.batchCacheItems(batchItems);
      _logger.log('💾 Batch saved ${playlists.length} playlists to cache');
    } catch (e) {
      _logger.log('⚠️ Failed to batch cache playlists: $e');
    }
  }

  /// Save tracks to database cache with source provider tracking (batched)
  Future<void> _saveTracksToCache(List<Track> tracks, Map<String, List<String>> sourceProviders) async {
    final batchItems = <BatchCacheItem>[];
    for (final track in tracks) {
      final providers = sourceProviders[track.itemId] ?? <String>[];
      batchItems.add(BatchCacheItem(
        itemType: 'track',
        itemId: track.itemId,
        data: jsonEncode(track.toJson()),
        sourceProviders: providers,
      ));
    }
    try {
      await _db.batchCacheItems(batchItems);
      _logger.log('💾 Batch saved ${tracks.length} tracks to cache');
    } catch (e) {
      _logger.log('⚠️ Failed to batch cache tracks: $e');
    }
  }

  /// Save podcasts to database cache (batched, no source provider tracking)
  Future<void> _savePodcastsToCache(List<MediaItem> podcasts) async {
    final batchItems = <BatchCacheItem>[];
    for (final podcast in podcasts) {
      batchItems.add(BatchCacheItem(
        itemType: 'podcast',
        itemId: podcast.itemId,
        data: jsonEncode(podcast.toJson()),
      ));
    }
    try {
      await _db.batchCacheItems(batchItems);
      _logger.log('💾 Batch saved ${podcasts.length} podcasts to cache');
    } catch (e) {
      _logger.log('⚠️ Failed to batch cache podcasts: $e');
    }
  }

  /// Force a fresh sync (for pull-to-refresh)
  /// [providerInstanceIds] - optional list of provider IDs to filter by (null = all providers)
  Future<void> forceSync(MusicAssistantAPI api, {List<String>? providerInstanceIds}) async {
    await syncFromApi(api, force: true, providerInstanceIds: providerInstanceIds);
  }

  /// Clear all cached data
  Future<void> clearCache() async {
    if (!_db.isInitialized) return;

    await _db.clearAllCache();
    _cachedAlbums = [];
    _cachedArtists = [];
    _cachedAudiobooks = [];
    _cachedPlaylists = [];
    _cachedTracks = [];
    _cachedPodcasts = [];
    _albumSourceProviders = {};
    _artistSourceProviders = {};
    _audiobookSourceProviders = {};
    _playlistSourceProviders = {};
    _trackSourceProviders = {};
    _lastSyncTime = null;
    _status = SyncStatus.idle;
    notifyListeners();
    _logger.log('🗑️ Library cache cleared');
  }

  // ============================================
  // Client-side filtering methods
  // ============================================

  /// Filter albums by source provider (instant, no network)
  /// Empty enabledProviderIds = all providers enabled, show everything
  /// Items without source tracking are HIDDEN (strict mode) to ensure accurate filtering
  List<Album> getAlbumsFilteredByProviders(Set<String> enabledProviderIds) {
    if (enabledProviderIds.isEmpty) {
      return _cachedAlbums;
    }
    return _cachedAlbums.where((album) {
      final sources = _albumSourceProviders[album.itemId];
      if (sources == null || sources.isEmpty) return false;
      return sources.any((s) => enabledProviderIds.contains(s));
    }).toList();
  }

  /// Filter artists by source provider (instant, no network)
  List<Artist> getArtistsFilteredByProviders(Set<String> enabledProviderIds) {
    if (enabledProviderIds.isEmpty) {
      return _cachedArtists;
    }
    return _cachedArtists.where((artist) {
      final sources = _artistSourceProviders[artist.itemId];
      if (sources == null || sources.isEmpty) return false;
      return sources.any((s) => enabledProviderIds.contains(s));
    }).toList();
  }

  /// Filter audiobooks by source provider (instant, no network)
  List<Audiobook> getAudiobooksFilteredByProviders(Set<String> enabledProviderIds) {
    if (enabledProviderIds.isEmpty) {
      return _cachedAudiobooks;
    }
    return _cachedAudiobooks.where((audiobook) {
      final sources = _audiobookSourceProviders[audiobook.itemId];
      // STRICT MODE: Hide items without tracking
      if (sources == null || sources.isEmpty) return false;
      return sources.any((s) => enabledProviderIds.contains(s));
    }).toList();
  }

  /// Filter playlists by source provider (instant, no network)
  List<Playlist> getPlaylistsFilteredByProviders(Set<String> enabledProviderIds) {
    if (enabledProviderIds.isEmpty) {
      return _cachedPlaylists;
    }
    return _cachedPlaylists.where((playlist) {
      final sources = _playlistSourceProviders[playlist.itemId];
      // STRICT MODE: Hide items without tracking
      if (sources == null || sources.isEmpty) return false;
      return sources.any((s) => enabledProviderIds.contains(s));
    }).toList();
  }

  /// Filter tracks by source provider (instant, no network)
  List<Track> getTracksFilteredByProviders(Set<String> enabledProviderIds) {
    if (enabledProviderIds.isEmpty) {
      return _cachedTracks;
    }
    return _cachedTracks.where((track) {
      final sources = _trackSourceProviders[track.itemId];
      if (sources == null || sources.isEmpty) return false;
      return sources.any((s) => enabledProviderIds.contains(s));
    }).toList();
  }

  /// Check if we have source provider tracking data
  bool get hasSourceTracking =>
      _albumSourceProviders.isNotEmpty ||
      _artistSourceProviders.isNotEmpty ||
      _audiobookSourceProviders.isNotEmpty ||
      _playlistSourceProviders.isNotEmpty ||
      _trackSourceProviders.isNotEmpty;

  /// Get albums (from cache or empty if not loaded)
  List<Album> getAlbums() => _cachedAlbums;

  /// Get artists (from cache or empty if not loaded)
  List<Artist> getArtists() => _cachedArtists;

  /// Get audiobooks (from cache or empty if not loaded)
  List<Audiobook> getAudiobooks() => _cachedAudiobooks;

  /// Get playlists (from cache or empty if not loaded)
  List<Playlist> getPlaylists() => _cachedPlaylists;

  /// Get tracks (from cache or empty if not loaded)
  List<Track> getTracks() => _cachedTracks;

  /// Get podcasts (from cache or empty if not loaded)
  List<MediaItem> getPodcasts() => _cachedPodcasts;

  /// Check if we have data available (from cache or sync)
  bool get hasData => _cachedAlbums.isNotEmpty || _cachedArtists.isNotEmpty ||
                      _cachedAudiobooks.isNotEmpty || _cachedPlaylists.isNotEmpty ||
                      _cachedTracks.isNotEmpty || _cachedPodcasts.isNotEmpty;

  /// Update cached albums with sorted data from provider
  /// Used when sort order changes - preserves source provider tracking
  void updateCachedAlbums(List<Album> albums) {
    _cachedAlbums = albums;
    notifyListeners();
  }

  /// Update cached artists with sorted data from provider
  /// Used when sort order changes - preserves source provider tracking
  void updateCachedArtists(List<Artist> artists) {
    _cachedArtists = artists;
    notifyListeners();
  }

  /// Update cached playlists with sorted data from provider
  /// Used when sort order changes - preserves source provider tracking
  void updateCachedPlaylists(List<Playlist> playlists) {
    _cachedPlaylists = playlists;
    notifyListeners();
  }

  /// Remove an item from in-memory cache by library ID
  /// Called when an item is removed from library to keep SyncService in sync
  void removeFromCacheByLibraryId(String mediaType, int libraryItemId) {
    final libraryIdStr = libraryItemId.toString();
    bool updated = false;

    // Helper to check if item matches the library ID being removed
    bool matchesLibraryId(String? provider, String? itemId, List<ProviderMapping>? mappings) {
      if (provider == 'library' && itemId == libraryIdStr) return true;
      if (mappings != null) {
        for (final m in mappings) {
          if ((m.providerInstance == 'library' || m.providerDomain == 'library') &&
              m.itemId == libraryIdStr) {
            return true;
          }
        }
      }
      return false;
    }

    switch (mediaType) {
      case 'album':
        final before = _cachedAlbums.length;
        _cachedAlbums = _cachedAlbums.where((a) =>
          !matchesLibraryId(a.provider, a.itemId, a.providerMappings)
        ).toList();
        updated = _cachedAlbums.length != before;
        // Also remove from source provider tracking
        if (updated) {
          _albumSourceProviders.removeWhere((key, _) =>
            _cachedAlbums.every((a) => a.itemId != key));
        }
        break;
      case 'artist':
        final before = _cachedArtists.length;
        _cachedArtists = _cachedArtists.where((a) =>
          !matchesLibraryId(a.provider, a.itemId, a.providerMappings)
        ).toList();
        updated = _cachedArtists.length != before;
        if (updated) {
          _artistSourceProviders.removeWhere((key, _) =>
            _cachedArtists.every((a) => a.itemId != key));
        }
        break;
      case 'audiobook':
        final before = _cachedAudiobooks.length;
        _cachedAudiobooks = _cachedAudiobooks.where((a) =>
          !matchesLibraryId(a.provider, a.itemId, a.providerMappings)
        ).toList();
        updated = _cachedAudiobooks.length != before;
        if (updated) {
          _audiobookSourceProviders.removeWhere((key, _) =>
            _cachedAudiobooks.every((a) => a.itemId != key));
        }
        break;
      case 'playlist':
        final before = _cachedPlaylists.length;
        _cachedPlaylists = _cachedPlaylists.where((p) =>
          !matchesLibraryId(p.provider, p.itemId, p.providerMappings)
        ).toList();
        updated = _cachedPlaylists.length != before;
        if (updated) {
          _playlistSourceProviders.removeWhere((key, _) =>
            _cachedPlaylists.every((p) => p.itemId != key));
        }
        break;
      case 'track':
        final before = _cachedTracks.length;
        _cachedTracks = _cachedTracks.where((t) =>
          !matchesLibraryId(t.provider, t.itemId, t.providerMappings)
        ).toList();
        updated = _cachedTracks.length != before;
        if (updated) {
          _trackSourceProviders.removeWhere((key, _) =>
            _cachedTracks.every((t) => t.itemId != key));
        }
        break;
    }

    if (updated) {
      _logger.log('🗑️ Removed $mediaType with libraryId=$libraryItemId from SyncService cache');
      notifyListeners();
    }
  }
}
