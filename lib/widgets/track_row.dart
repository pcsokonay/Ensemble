import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../l10n/app_localizations.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../services/debug_logger.dart';
import 'media_context_menu.dart';

class TrackRow extends StatefulWidget {
  final String title;
  final Future<List<Track>> Function() loadTracks;
  final double? rowHeight;
  /// Optional: synchronous getter for cached data (for instant display)
  final List<Track>? Function()? getCachedTracks;

  const TrackRow({
    super.key,
    required this.title,
    required this.loadTracks,
    this.rowHeight,
    this.getCachedTracks,
  });

  @override
  State<TrackRow> createState() => _TrackRowState();
}

class _TrackRowState extends State<TrackRow> with AutomaticKeepAliveClientMixin {
  List<Track> _tracks = [];
  bool _isLoading = true;
  bool _hasLoaded = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Get cached data synchronously BEFORE first build (no spinner flash)
    final cached = widget.getCachedTracks?.call();
    if (cached != null && cached.isNotEmpty) {
      _tracks = cached;
      _isLoading = false;
    }
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    if (_hasLoaded) return;
    _hasLoaded = true;

    // Load fresh data (always update)
    try {
      final freshTracks = await widget.loadTracks();
      if (mounted && freshTracks.isNotEmpty) {
        setState(() {
          _tracks = freshTracks;
          _isLoading = false;
        });
        // Pre-cache images for smooth scrolling
        _precacheTrackImages(freshTracks);
      }
    } catch (e) {
      // Silent failure - keep showing cached data
    }

    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  void _precacheTrackImages(List<Track> tracks) {
    if (!mounted) return;
    final maProvider = context.read<MusicAssistantProvider>();

    final tracksToCache = tracks.take(10);

    for (final track in tracksToCache) {
      final imageUrl = maProvider.api?.getImageUrl(track, size: 256);
      if (imageUrl != null) {
        precacheImage(
          CachedNetworkImageProvider(imageUrl),
          context,
        ).catchError((_) => false);
      }
    }
  }

  static final _logger = DebugLogger();

  Widget _buildContent(double contentHeight, ColorScheme colorScheme) {
    // Only show loading if we have no data at all
    if (_tracks.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_tracks.isEmpty) {
      return Center(
        child: Text(
          S.of(context)!.noTracksFound,
          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
        ),
      );
    }

    // Card layout: square artwork + text below
    // Text area: 8px gap + ~18px title + ~18px artist = ~44px
    const textAreaHeight = 44.0;
    final artworkSize = contentHeight - textAreaHeight;
    final cardWidth = artworkSize; // Card width = artwork width (square)
    final itemExtent = cardWidth + 12;

    return ScrollConfiguration(
      behavior: const _StretchScrollBehavior(),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        itemCount: _tracks.length,
        itemExtent: itemExtent,
        cacheExtent: 500, // Preload ~3 items ahead for smoother scrolling
        addAutomaticKeepAlives: false, // Row already uses AutomaticKeepAliveClientMixin
        addRepaintBoundaries: false, // Cards already have RepaintBoundary
        itemBuilder: (context, index) {
          final track = _tracks[index];
          return Container(
            key: ValueKey(track.uri ?? track.itemId),
            width: cardWidth,
            margin: const EdgeInsets.symmetric(horizontal: 6.0),
            child: _TrackCard(
              track: track,
              tracks: _tracks,
              index: index,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _logger.startBuild('TrackRow:${widget.title}');
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    // Total row height includes title + content
    final totalHeight = widget.rowHeight ?? 224.0; // Default: 44 title + 180 content
    const titleHeight = 44.0; // 12 top padding + ~24 text + 8 bottom padding
    final contentHeight = totalHeight - titleHeight;

    final result = RepaintBoundary(
      child: SizedBox(
        height: totalHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 8.0),
              child: Text(
                widget.title,
                style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colorScheme.onBackground,
              ),
            ),
          ),
          Expanded(
            child: _buildContent(contentHeight, colorScheme),
          ),
          ],
        ),
      ),
    );
    _logger.endBuild('TrackRow:${widget.title}');
    return result;
  }
}

class _TrackCard extends StatefulWidget {
  final Track track;
  final List<Track> tracks;
  final int index;

  const _TrackCard({
    required this.track,
    required this.tracks,
    required this.index,
  });

  @override
  State<_TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends State<_TrackCard> {
  late bool _isFavorite;
  late bool _isInLibrary;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.track.favorite ?? false;
    _isInLibrary = widget.track.inLibrary;
  }

  Future<void> _toggleFavorite() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final newState = !_isFavorite;

    try {
      bool success;
      if (newState) {
        String actualProvider = widget.track.provider;
        String actualItemId = widget.track.itemId;

        if (widget.track.providerMappings != null && widget.track.providerMappings!.isNotEmpty) {
          final mapping = widget.track.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => widget.track.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => widget.track.providerMappings!.first,
            ),
          );
          actualProvider = mapping.providerDomain;
          actualItemId = mapping.itemId;
        }

        success = await maProvider.addToFavorites(
          mediaType: 'track',
          itemId: actualItemId,
          provider: actualProvider,
        );
      } else {
        int? libraryItemId;
        if (widget.track.provider == 'library') {
          libraryItemId = int.tryParse(widget.track.itemId);
        } else if (widget.track.providerMappings != null) {
          final libraryMapping = widget.track.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.track.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId == null) return;

        success = await maProvider.removeFromFavorites(
          mediaType: 'track',
          libraryItemId: libraryItemId,
        );
      }

      if (success && mounted) {
        setState(() => _isFavorite = newState);
        maProvider.invalidateHomeCache();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isFavorite ? S.of(context)!.addedToFavorites : S.of(context)!.removedFromFavorites),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      // Silent failure
    }
  }

  Future<void> _toggleLibrary() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final newState = !_isInLibrary;

    try {
      if (newState) {
        String? actualProvider;
        String? actualItemId;

        if (widget.track.providerMappings != null && widget.track.providerMappings!.isNotEmpty) {
          final nonLibraryMapping = widget.track.providerMappings!.where(
            (m) => m.providerInstance != 'library' && m.providerDomain != 'library',
          ).firstOrNull;

          if (nonLibraryMapping != null) {
            actualProvider = nonLibraryMapping.providerDomain;
            actualItemId = nonLibraryMapping.itemId;
          }
        }

        if (actualProvider == null || actualItemId == null) {
          if (widget.track.provider != 'library') {
            actualProvider = widget.track.provider;
            actualItemId = widget.track.itemId;
          } else {
            return;
          }
        }

        setState(() => _isInLibrary = newState);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.addedToLibrary),
            duration: const Duration(seconds: 1),
          ),
        );

        maProvider.addToLibrary(
          mediaType: 'track',
          provider: actualProvider,
          itemId: actualItemId,
        ).catchError((e) {
          if (mounted) setState(() => _isInLibrary = !newState);
        });
      } else {
        int? libraryItemId;
        if (widget.track.provider == 'library') {
          libraryItemId = int.tryParse(widget.track.itemId);
        } else if (widget.track.providerMappings != null) {
          final libraryMapping = widget.track.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.track.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId == null) return;

        setState(() => _isInLibrary = newState);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.removedFromLibrary),
            duration: const Duration(seconds: 1),
          ),
        );

        maProvider.removeFromLibrary(
          mediaType: 'track',
          libraryItemId: libraryItemId,
        ).catchError((e) {
          if (mounted) setState(() => _isInLibrary = !newState);
        });
      }
    } catch (e) {
      // Silent failure
    }
  }

  @override
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    // Try track image first, then album image
    final trackImageUrl = maProvider.getImageUrl(widget.track, size: 256);
    final albumImageUrl = widget.track.album != null
        ? maProvider.getImageUrl(widget.track.album!, size: 256)
        : null;
    final imageUrl = trackImageUrl ?? albumImageUrl;
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: () => _playTrack(context, maProvider),
        onLongPressStart: (details) {
          MediaContextMenu.show(
            context: context,
            position: details.globalPosition,
            mediaType: ContextMenuMediaType.track,
            item: widget.track,
            isFavorite: _isFavorite,
            isInLibrary: _isInLibrary,
            onToggleFavorite: _toggleFavorite,
            onToggleLibrary: _toggleLibrary,
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album artwork
            AspectRatio(
              aspectRatio: 1.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12.0),
                child: Container(
                  color: colorScheme.surfaceVariant,
                  child: imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          memCacheWidth: 256,
                          memCacheHeight: 256,
                          // PERF: Duration.zero for smooth scrolling
                          fadeInDuration: Duration.zero,
                          fadeOutDuration: Duration.zero,
                          placeholder: (context, url) => const SizedBox(),
                          errorWidget: (context, url, error) => Icon(
                            Icons.music_note_rounded,
                            size: 64,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        )
                      : Center(
                          child: Icon(
                            Icons.music_note_rounded,
                            size: 64,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Track title
            Text(
              widget.track.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
            // Artist name
            Text(
              widget.track.artistsString,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _playTrack(BuildContext context, MusicAssistantProvider maProvider) async {
    if (maProvider.selectedPlayer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No player selected')),
      );
      return;
    }

    await maProvider.playTracks(
      maProvider.selectedPlayer!.playerId,
      widget.tracks,
      startIndex: widget.index,
    );
  }
}

class _StretchScrollBehavior extends ScrollBehavior {
  const _StretchScrollBehavior();

  @override
  Widget buildOverscrollIndicator(
      BuildContext context, Widget child, ScrollableDetails details) {
    return StretchingOverscrollIndicator(
      axisDirection: details.direction,
      child: child,
    );
  }
}
