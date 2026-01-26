import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../l10n/app_localizations.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../services/debug_logger.dart';
import '../utils/page_transitions.dart';
import '../screens/audiobook_detail_screen.dart';
import '../constants/hero_tags.dart';
import 'provider_icon.dart';
import 'media_context_menu.dart';

class AudiobookRow extends StatefulWidget {
  final String title;
  final Future<List<Audiobook>> Function() loadAudiobooks;
  final String? heroTagSuffix;
  final double? rowHeight;
  /// Optional: synchronous getter for cached data (for instant display)
  final List<Audiobook>? Function()? getCachedAudiobooks;

  const AudiobookRow({
    super.key,
    required this.title,
    required this.loadAudiobooks,
    this.heroTagSuffix,
    this.rowHeight,
    this.getCachedAudiobooks,
  });

  @override
  State<AudiobookRow> createState() => _AudiobookRowState();
}

class _AudiobookRowState extends State<AudiobookRow> with AutomaticKeepAliveClientMixin {
  List<Audiobook> _audiobooks = [];
  bool _isLoading = true;
  bool _hasLoaded = false;
  bool _hasPrecachedAudiobooks = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // Get cached data synchronously BEFORE first build (no spinner flash)
    final cached = widget.getCachedAudiobooks?.call();
    if (cached != null && cached.isNotEmpty) {
      _audiobooks = cached;
      _isLoading = false;
    }
    _loadAudiobooks();
  }

  Future<void> _loadAudiobooks() async {
    if (_hasLoaded) return;
    _hasLoaded = true;

    // Load fresh data (always update - fresh data may have updated progress)
    try {
      final freshAudiobooks = await widget.loadAudiobooks();
      if (mounted && freshAudiobooks.isNotEmpty) {
        setState(() {
          _audiobooks = freshAudiobooks;
          _isLoading = false;
        });
        // Pre-cache images for smooth hero animations
        _precacheAudiobookImages(freshAudiobooks);
      }
    } catch (e) {
      // Silent failure - keep showing cached data
    }

    if (mounted && _isLoading) {
      setState(() => _isLoading = false);
    }
  }

  /// Pre-cache audiobook images so Hero animations are smooth on first tap
  void _precacheAudiobookImages(List<Audiobook> audiobooks) {
    if (!mounted || _hasPrecachedAudiobooks) return;
    _hasPrecachedAudiobooks = true;

    final maProvider = context.read<MusicAssistantProvider>();

    // Only precache first ~10 visible items
    final audiobooksToCache = audiobooks.take(10);

    for (final audiobook in audiobooksToCache) {
      final imageUrl = maProvider.api?.getImageUrl(audiobook, size: 256);
      if (imageUrl != null) {
        precacheImage(
          CachedNetworkImageProvider(imageUrl),
          context,
        ).catchError((_) {
          // Silently ignore precache errors
        });
      }
    }
  }

  static final _logger = DebugLogger();

  Widget _buildContent(double contentHeight, ColorScheme colorScheme, MusicAssistantProvider maProvider) {
    // Only show loading if we have no data at all
    if (_audiobooks.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_audiobooks.isEmpty) {
      return Center(
        child: Text(
          S.of(context)!.noAudiobooks,
          style: TextStyle(color: colorScheme.onSurface.withOpacity(0.5)),
        ),
      );
    }

    const textAreaHeight = 44.0;
    final artworkSize = contentHeight - textAreaHeight;
    final cardWidth = artworkSize;
    final itemExtent = cardWidth + 12;

    return ScrollConfiguration(
      behavior: const _StretchScrollBehavior(),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12.0),
        itemCount: _audiobooks.length,
        itemExtent: itemExtent,
        cacheExtent: 500,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false,
        itemBuilder: (context, index) {
          final audiobook = _audiobooks[index];
          return Container(
            key: ValueKey(audiobook.uri ?? audiobook.itemId),
            width: cardWidth,
            margin: const EdgeInsets.symmetric(horizontal: 6.0),
            child: _AudiobookCard(
              audiobook: audiobook,
              heroTagSuffix: widget.heroTagSuffix ?? 'home_${widget.title.replaceAll(' ', '_').toLowerCase()}',
              maProvider: maProvider,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _logger.startBuild('AudiobookRow:${widget.title}');
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final maProvider = context.read<MusicAssistantProvider>();

    final totalHeight = widget.rowHeight ?? 237.0;
    const titleHeight = 44.0;
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
              child: _buildContent(contentHeight, colorScheme, maProvider),
            ),
          ],
        ),
      ),
    );
    _logger.endBuild('AudiobookRow:${widget.title}');
    return result;
  }
}

class _AudiobookCard extends StatefulWidget {
  final Audiobook audiobook;
  final String heroTagSuffix;
  final MusicAssistantProvider maProvider;

  const _AudiobookCard({
    required this.audiobook,
    required this.heroTagSuffix,
    required this.maProvider,
  });

  @override
  State<_AudiobookCard> createState() => _AudiobookCardState();
}

class _AudiobookCardState extends State<_AudiobookCard> {
  late bool _isFavorite;
  late bool _isInLibrary;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.audiobook.favorite ?? false;
    _isInLibrary = widget.audiobook.inLibrary;
  }

  Future<void> _toggleFavorite() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final newState = !_isFavorite;

    try {
      bool success;
      if (newState) {
        String actualProvider = widget.audiobook.provider;
        String actualItemId = widget.audiobook.itemId;

        if (widget.audiobook.providerMappings != null && widget.audiobook.providerMappings!.isNotEmpty) {
          final mapping = widget.audiobook.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => widget.audiobook.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => widget.audiobook.providerMappings!.first,
            ),
          );
          actualProvider = mapping.providerDomain;
          actualItemId = mapping.itemId;
        }

        success = await maProvider.addToFavorites(
          mediaType: 'audiobook',
          itemId: actualItemId,
          provider: actualProvider,
        );
      } else {
        int? libraryItemId;
        if (widget.audiobook.provider == 'library') {
          libraryItemId = int.tryParse(widget.audiobook.itemId);
        } else if (widget.audiobook.providerMappings != null) {
          final libraryMapping = widget.audiobook.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.audiobook.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId == null) return;

        success = await maProvider.removeFromFavorites(
          mediaType: 'audiobook',
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

        if (widget.audiobook.providerMappings != null && widget.audiobook.providerMappings!.isNotEmpty) {
          final nonLibraryMapping = widget.audiobook.providerMappings!.where(
            (m) => m.providerInstance != 'library' && m.providerDomain != 'library',
          ).firstOrNull;

          if (nonLibraryMapping != null) {
            actualProvider = nonLibraryMapping.providerDomain;
            actualItemId = nonLibraryMapping.itemId;
          }
        }

        if (actualProvider == null || actualItemId == null) {
          if (widget.audiobook.provider != 'library') {
            actualProvider = widget.audiobook.provider;
            actualItemId = widget.audiobook.itemId;
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
          mediaType: 'audiobook',
          provider: actualProvider,
          itemId: actualItemId,
        ).catchError((e) {
          if (mounted) setState(() => _isInLibrary = !newState);
        });
      } else {
        int? libraryItemId;
        if (widget.audiobook.provider == 'library') {
          libraryItemId = int.tryParse(widget.audiobook.itemId);
        } else if (widget.audiobook.providerMappings != null) {
          final libraryMapping = widget.audiobook.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.audiobook.providerMappings!.first,
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
          mediaType: 'audiobook',
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
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final imageUrl = widget.maProvider.getImageUrl(widget.audiobook, size: 256);

    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          FadeSlidePageRoute(
            child: AudiobookDetailScreen(
              audiobook: widget.audiobook,
              heroTagSuffix: widget.heroTagSuffix,
              initialImageUrl: imageUrl,
            ),
          ),
        );
      },
      onLongPressStart: (details) {
        MediaContextMenu.show(
          context: context,
          position: details.globalPosition,
          mediaType: ContextMenuMediaType.audiobook,
          item: widget.audiobook,
          isFavorite: _isFavorite,
          isInLibrary: _isInLibrary,
          onToggleFavorite: _toggleFavorite,
          onToggleLibrary: _toggleLibrary,
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                Hero(
                  tag: HeroTags.audiobookCover + (widget.audiobook.uri ?? widget.audiobook.itemId) + '_${widget.heroTagSuffix}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: double.infinity,
                      height: double.infinity,
                      color: colorScheme.surfaceContainerHighest,
                      child: imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              // PERF: Duration.zero for hero-wrapped images
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
                              memCacheWidth: 256,
                              memCacheHeight: 256,
                              placeholder: (_, __) => Center(
                                child: Icon(
                                  MdiIcons.bookOutline,
                                  size: 48,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              errorWidget: (_, __, ___) => Center(
                                child: Icon(
                                  MdiIcons.bookOutline,
                                  size: 48,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : Center(
                              child: Icon(
                                MdiIcons.bookOutline,
                                size: 48,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                    ),
                  ),
                ),
                // Progress indicator
                if (widget.audiobook.progress > 0)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        bottomLeft: Radius.circular(8),
                        bottomRight: Radius.circular(8),
                      ),
                      child: LinearProgressIndicator(
                        value: widget.audiobook.progress,
                        backgroundColor: Colors.black54,
                        valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                        minHeight: 4,
                      ),
                    ),
                  ),
                // Provider icon overlay
                if (widget.audiobook.providerMappings?.isNotEmpty == true)
                  ProviderIconOverlay(
                    domain: widget.audiobook.providerMappings!.first.providerDomain,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Hero(
            tag: HeroTags.audiobookTitle + (widget.audiobook.uri ?? widget.audiobook.itemId) + '_${widget.heroTagSuffix}',
            child: Material(
              color: Colors.transparent,
              child: Text(
                widget.audiobook.name,
                style: textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          Text(
            widget.audiobook.authorsString,
            style: textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurface.withOpacity(0.6),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
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
