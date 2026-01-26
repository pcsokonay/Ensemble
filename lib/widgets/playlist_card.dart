import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../screens/playlist_details_screen.dart';
import '../constants/hero_tags.dart';
import '../constants/timings.dart';
import '../utils/page_transitions.dart';
import '../l10n/app_localizations.dart';
import 'provider_icon.dart';
import 'media_context_menu.dart';

class PlaylistCard extends StatefulWidget {
  final Playlist playlist;
  final VoidCallback? onTap;
  final String? heroTagSuffix;
  final int? imageCacheSize;

  const PlaylistCard({
    super.key,
    required this.playlist,
    this.onTap,
    this.heroTagSuffix,
    this.imageCacheSize,
  });

  @override
  State<PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends State<PlaylistCard> {
  bool _isNavigating = false;
  late bool _isFavorite;
  late bool _isInLibrary;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.playlist.favorite ?? false;
    _isInLibrary = widget.playlist.inLibrary;
  }

  Future<void> _toggleFavorite() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final newState = !_isFavorite;

    try {
      bool success;
      if (newState) {
        String actualProvider = widget.playlist.provider;
        String actualItemId = widget.playlist.itemId;

        if (widget.playlist.providerMappings != null && widget.playlist.providerMappings!.isNotEmpty) {
          final mapping = widget.playlist.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => widget.playlist.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => widget.playlist.providerMappings!.first,
            ),
          );
          actualProvider = mapping.providerDomain;
          actualItemId = mapping.itemId;
        }

        success = await maProvider.addToFavorites(
          mediaType: 'playlist',
          itemId: actualItemId,
          provider: actualProvider,
        );
      } else {
        int? libraryItemId;
        if (widget.playlist.provider == 'library') {
          libraryItemId = int.tryParse(widget.playlist.itemId);
        } else if (widget.playlist.providerMappings != null) {
          final libraryMapping = widget.playlist.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.playlist.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId == null) return;

        success = await maProvider.removeFromFavorites(
          mediaType: 'playlist',
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

        if (widget.playlist.providerMappings != null && widget.playlist.providerMappings!.isNotEmpty) {
          final nonLibraryMapping = widget.playlist.providerMappings!.where(
            (m) => m.providerInstance != 'library' && m.providerDomain != 'library',
          ).firstOrNull;

          if (nonLibraryMapping != null) {
            actualProvider = nonLibraryMapping.providerDomain;
            actualItemId = nonLibraryMapping.itemId;
          }
        }

        if (actualProvider == null || actualItemId == null) {
          if (widget.playlist.provider != 'library') {
            actualProvider = widget.playlist.provider;
            actualItemId = widget.playlist.itemId;
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
          mediaType: 'playlist',
          provider: actualProvider,
          itemId: actualItemId,
        ).catchError((e) {
          if (mounted) setState(() => _isInLibrary = !newState);
          return false;
        });
      } else {
        int? libraryItemId;
        if (widget.playlist.provider == 'library') {
          libraryItemId = int.tryParse(widget.playlist.itemId);
        } else if (widget.playlist.providerMappings != null) {
          final libraryMapping = widget.playlist.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.playlist.providerMappings!.first,
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
          mediaType: 'playlist',
          libraryItemId: libraryItemId,
        ).catchError((e) {
          if (mounted) setState(() => _isInLibrary = !newState);
          return false;
        });
      }
    } catch (e) {
      // Silent failure
    }
  }

  @override
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.api?.getImageUrl(widget.playlist, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final suffix = widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';
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
              child: PlaylistDetailsScreen(
                playlist: widget.playlist,
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
          MediaContextMenu.show(
            context: context,
            position: details.globalPosition,
            mediaType: ContextMenuMediaType.playlist,
            item: widget.playlist,
            isFavorite: _isFavorite,
            isInLibrary: _isInLibrary,
            onToggleFavorite: _toggleFavorite,
            onToggleLibrary: _toggleLibrary,
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Playlist artwork
            AspectRatio(
              aspectRatio: 1.0,
              child: Hero(
                tag: HeroTags.playlistCover + (widget.playlist.uri ?? widget.playlist.itemId) + suffix,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.0),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Container(
                        color: colorScheme.surfaceContainerHighest,
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
                                    Icons.playlist_play_rounded,
                                    size: 64,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              )
                            : Center(
                                child: Icon(
                                  Icons.playlist_play_rounded,
                                  size: 64,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                      ),
                      // Provider icon overlay
                      if (widget.playlist.providerMappings?.isNotEmpty == true)
                        ProviderIconOverlay(
                          domain: widget.playlist.providerMappings!.first.providerDomain,
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Playlist title
            // PERF: Removed Hero - text animations provide minimal benefit but add overhead
            Text(
              widget.playlist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
            // Owner/track count
            Text(
              widget.playlist.owner ?? (widget.playlist.trackCount != null ? '${widget.playlist.trackCount} tracks' : ''),
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
}
