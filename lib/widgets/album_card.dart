import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../screens/album_details_screen.dart';
import '../constants/hero_tags.dart';
import '../theme/theme_provider.dart';
import '../utils/page_transitions.dart';
import '../services/metadata_service.dart';

class AlbumCard extends StatefulWidget {
  final Album album;
  final VoidCallback? onTap;
  final String? heroTagSuffix;

  const AlbumCard({
    super.key,
    required this.album,
    this.onTap,
    this.heroTagSuffix,
  });

  @override
  State<AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<AlbumCard> {
  String? _fallbackImageUrl;
  bool _triedFallback = false;
  bool _maImageFailed = false;
  String? _cachedMaImageUrl;

  @override
  void initState() {
    super.initState();
    _initFallbackImage();
  }

  void _initFallbackImage() {
    // Check if MA has an image after first build, then fetch fallback if needed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final maProvider = context.read<MusicAssistantProvider>();
      final maImageUrl = maProvider.api?.getImageUrl(widget.album, size: 256);
      _cachedMaImageUrl = maImageUrl;

      if (maImageUrl == null && !_triedFallback) {
        _triedFallback = true;
        _fetchFallbackImage();
      }
    });
  }

  Future<void> _fetchFallbackImage() async {
    final fallbackUrl = await MetadataService.getAlbumImageUrl(
      widget.album.name,
      widget.album.artistsString,
    );
    if (fallbackUrl != null && mounted) {
      setState(() {
        _fallbackImageUrl = fallbackUrl;
      });
    }
  }

  void _onImageError() {
    // When MA image fails to load, try Deezer fallback
    if (!_triedFallback && !_maImageFailed) {
      _maImageFailed = true;
      _triedFallback = true;
      _fetchFallbackImage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    // Use cached URL if available, otherwise get fresh
    final maImageUrl = _cachedMaImageUrl ?? maProvider.api?.getImageUrl(widget.album, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final suffix = widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';

    // Use fallback if MA image failed or wasn't available
    final imageUrl = (_maImageFailed || maImageUrl == null) ? _fallbackImageUrl : maImageUrl;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap ?? () {
          // Update adaptive colors immediately on tap
          updateAdaptiveColorsFromImage(context, imageUrl);
          Navigator.push(
            context,
            FadeSlidePageRoute(
              child: AlbumDetailsScreen(
                album: widget.album,
                heroTagSuffix: widget.heroTagSuffix,
                initialImageUrl: imageUrl,
              ),
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Album artwork
            AspectRatio(
              aspectRatio: 1.0,
              child: Hero(
                tag: HeroTags.albumCover + (widget.album.uri ?? widget.album.itemId) + suffix,
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
                            fadeInDuration: Duration.zero,
                            fadeOutDuration: Duration.zero,
                            placeholder: (context, url) => const SizedBox(),
                            errorWidget: (context, url, error) {
                              // Try fallback on error (only for MA URLs, not fallback URLs)
                              if (!_maImageFailed && url == maImageUrl) {
                                WidgetsBinding.instance.addPostFrameCallback((_) {
                                  _onImageError();
                                });
                              }
                              return Icon(
                                Icons.album_rounded,
                                size: 64,
                                color: colorScheme.onSurfaceVariant,
                              );
                            },
                          )
                        : Center(
                            child: Icon(
                              Icons.album_rounded,
                              size: 64,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          // Album title with year
          Hero(
            tag: HeroTags.albumTitle + (widget.album.uri ?? widget.album.itemId) + suffix,
            child: Material(
              color: Colors.transparent,
              child: Text(
                widget.album.nameWithYear,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          // Artist name
          Hero(
            tag: HeroTags.artistName + (widget.album.uri ?? widget.album.itemId) + suffix,
            child: Material(
              color: Colors.transparent,
              child: Text(
                widget.album.artistsString,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withOpacity(0.7),
                ),
              ),
            ),
          ),
          ],
        ),
      ),
    );
  }
}
