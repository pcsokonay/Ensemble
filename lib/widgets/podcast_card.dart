import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../screens/podcast_detail_screen.dart';
import '../constants/hero_tags.dart';
import '../constants/timings.dart';
import '../utils/page_transitions.dart';
import '../l10n/app_localizations.dart';
import 'provider_icon.dart';
import 'media_context_menu.dart';

class PodcastCard extends StatefulWidget {
  final MediaItem podcast;
  final VoidCallback? onTap;
  final String? heroTagSuffix;
  /// Image decode size in pixels. Defaults to 256.
  /// Use smaller values (e.g., 128) for list views, larger for grids.
  final int? imageCacheSize;

  const PodcastCard({
    super.key,
    required this.podcast,
    this.onTap,
    this.heroTagSuffix,
    this.imageCacheSize,
  });

  @override
  State<PodcastCard> createState() => _PodcastCardState();
}

class _PodcastCardState extends State<PodcastCard> {
  bool _isNavigating = false;
  late bool _isFavorite;
  late bool _isInLibrary;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.podcast.favorite ?? false;
    _isInLibrary = widget.podcast.inLibrary;
  }

  Future<void> _toggleFavorite() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final newState = !_isFavorite;

    try {
      bool success;
      if (newState) {
        String actualProvider = widget.podcast.provider;
        String actualItemId = widget.podcast.itemId;

        if (widget.podcast.providerMappings != null && widget.podcast.providerMappings!.isNotEmpty) {
          final mapping = widget.podcast.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => widget.podcast.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => widget.podcast.providerMappings!.first,
            ),
          );
          actualProvider = mapping.providerDomain;
          actualItemId = mapping.itemId;
        }

        success = await maProvider.addToFavorites(
          mediaType: 'podcast',
          itemId: actualItemId,
          provider: actualProvider,
        );
      } else {
        int? libraryItemId;
        if (widget.podcast.provider == 'library') {
          libraryItemId = int.tryParse(widget.podcast.itemId);
        } else if (widget.podcast.providerMappings != null) {
          final libraryMapping = widget.podcast.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.podcast.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId == null) return;

        success = await maProvider.removeFromFavorites(
          mediaType: 'podcast',
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

        if (widget.podcast.providerMappings != null && widget.podcast.providerMappings!.isNotEmpty) {
          final nonLibraryMapping = widget.podcast.providerMappings!.where(
            (m) => m.providerInstance != 'library' && m.providerDomain != 'library',
          ).firstOrNull;

          if (nonLibraryMapping != null) {
            actualProvider = nonLibraryMapping.providerDomain;
            actualItemId = nonLibraryMapping.itemId;
          }
        }

        if (actualProvider == null || actualItemId == null) {
          if (widget.podcast.provider != 'library') {
            actualProvider = widget.podcast.provider;
            actualItemId = widget.podcast.itemId;
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
          mediaType: 'podcast',
          provider: actualProvider,
          itemId: actualItemId,
        ).catchError((e) {
          if (mounted) setState(() => _isInLibrary = !newState);
        });
      } else {
        int? libraryItemId;
        if (widget.podcast.provider == 'library') {
          libraryItemId = int.tryParse(widget.podcast.itemId);
        } else if (widget.podcast.providerMappings != null) {
          final libraryMapping = widget.podcast.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.podcast.providerMappings!.first,
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
          mediaType: 'podcast',
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
    // Use provider's getPodcastImageUrl which includes iTunes cache
    final imageUrl = maProvider.getPodcastImageUrl(widget.podcast, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final suffix = widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';

    // PERF: Use appropriate cache size based on display size
    final cacheSize = widget.imageCacheSize ?? 256;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap ?? () {
          // Prevent double-tap navigation
          if (_isNavigating) return;
          _isNavigating = true;

          // PERF: Color extraction deferred to detail screen's initState
          // to avoid competing with Hero animation for GPU resources
          Navigator.push(
            context,
            FadeSlidePageRoute(
              child: PodcastDetailScreen(
                podcast: widget.podcast,
                heroTagSuffix: widget.heroTagSuffix,
                initialImageUrl: imageUrl,
              ),
            ),
          ).then((_) {
            // Reset after navigation debounce delay
            Future.delayed(Timings.navigationDebounce, () {
              if (mounted) _isNavigating = false;
            });
          });
        },
        onLongPressStart: (details) {
          HapticFeedback.mediumImpact();
          MediaContextMenu.show(
            context: context,
            position: details.globalPosition,
            mediaType: ContextMenuMediaType.podcast,
            item: widget.podcast,
            isFavorite: _isFavorite,
            isInLibrary: _isInLibrary,
            onToggleFavorite: _toggleFavorite,
            onToggleLibrary: _toggleLibrary,
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Podcast artwork - square with rounded corners
            AspectRatio(
              aspectRatio: 1.0,
              child: Hero(
                tag: HeroTags.podcastCover + (widget.podcast.uri ?? widget.podcast.itemId) + suffix,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.0),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        color: colorScheme.surfaceVariant,
                        child: imageUrl != null
                            ? CachedNetworkImage(
                                imageUrl: imageUrl,
                                fit: BoxFit.cover,
                                memCacheWidth: cacheSize,
                                memCacheHeight: cacheSize,
                                fadeInDuration: Duration.zero,
                                fadeOutDuration: Duration.zero,
                                placeholder: (context, url) => const SizedBox(),
                                errorWidget: (context, url, error) => Center(
                                  child: Icon(
                                    MdiIcons.podcast,
                                    size: 64,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : Center(
                                child: Icon(
                                  MdiIcons.podcast,
                                  size: 64,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                      ),
                      // Provider icon overlay
                      if (widget.podcast.providerMappings?.isNotEmpty == true)
                        ProviderIconOverlay(
                          domain: widget.podcast.providerMappings!.first.providerDomain,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Podcast title
            // PERF: Removed Hero - text animations provide minimal benefit but add overhead
            Text(
              widget.podcast.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
            // Podcast author (if available)
            Text(
              _getAuthor(widget.podcast),
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

  /// Extract author from podcast metadata
  String _getAuthor(MediaItem podcast) {
    final metadata = podcast.metadata;
    if (metadata == null) return '';

    // Try different metadata fields for author
    final author = metadata['author'] ??
                   metadata['artist'] ??
                   metadata['owner'] ?? '';
    return author.toString();
  }
}
