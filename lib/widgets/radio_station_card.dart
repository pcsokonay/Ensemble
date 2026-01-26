import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../constants/hero_tags.dart';
import '../constants/timings.dart';
import '../l10n/app_localizations.dart';
import 'media_context_menu.dart';

class RadioStationCard extends StatefulWidget {
  final MediaItem radioStation;
  final VoidCallback? onTap;
  final String? heroTagSuffix;
  final int? imageCacheSize;

  const RadioStationCard({
    super.key,
    required this.radioStation,
    this.onTap,
    this.heroTagSuffix,
    this.imageCacheSize,
  });

  @override
  State<RadioStationCard> createState() => _RadioStationCardState();
}

class _RadioStationCardState extends State<RadioStationCard> {
  bool _isTapping = false;
  late bool _isFavorite;
  late bool _isInLibrary;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.radioStation.favorite ?? false;
    _isInLibrary = widget.radioStation.inLibrary;
  }

  Future<void> _toggleFavorite() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final newState = !_isFavorite;

    try {
      bool success;
      if (newState) {
        String actualProvider = widget.radioStation.provider;
        String actualItemId = widget.radioStation.itemId;

        if (widget.radioStation.providerMappings != null && widget.radioStation.providerMappings!.isNotEmpty) {
          final mapping = widget.radioStation.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => widget.radioStation.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => widget.radioStation.providerMappings!.first,
            ),
          );
          actualProvider = mapping.providerDomain;
          actualItemId = mapping.itemId;
        }

        success = await maProvider.addToFavorites(
          mediaType: 'radio',
          itemId: actualItemId,
          provider: actualProvider,
        );
      } else {
        int? libraryItemId;
        if (widget.radioStation.provider == 'library') {
          libraryItemId = int.tryParse(widget.radioStation.itemId);
        } else if (widget.radioStation.providerMappings != null) {
          final libraryMapping = widget.radioStation.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.radioStation.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId == null) return;

        success = await maProvider.removeFromFavorites(
          mediaType: 'radio',
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

        if (widget.radioStation.providerMappings != null && widget.radioStation.providerMappings!.isNotEmpty) {
          final nonLibraryMapping = widget.radioStation.providerMappings!.where(
            (m) => m.providerInstance != 'library' && m.providerDomain != 'library',
          ).firstOrNull;

          if (nonLibraryMapping != null) {
            actualProvider = nonLibraryMapping.providerDomain;
            actualItemId = nonLibraryMapping.itemId;
          }
        }

        if (actualProvider == null || actualItemId == null) {
          if (widget.radioStation.provider != 'library') {
            actualProvider = widget.radioStation.provider;
            actualItemId = widget.radioStation.itemId;
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
          mediaType: 'radio',
          provider: actualProvider,
          itemId: actualItemId,
        ).catchError((e) {
          if (mounted) setState(() => _isInLibrary = !newState);
        });
      } else {
        int? libraryItemId;
        if (widget.radioStation.provider == 'library') {
          libraryItemId = int.tryParse(widget.radioStation.itemId);
        } else if (widget.radioStation.providerMappings != null) {
          final libraryMapping = widget.radioStation.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => widget.radioStation.providerMappings!.first,
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
          mediaType: 'radio',
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
    final imageUrl = maProvider.api?.getImageUrl(widget.radioStation, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final suffix = widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';
    final cacheSize = widget.imageCacheSize ?? 256;

    return RepaintBoundary(
      child: GestureDetector(
        onTap: widget.onTap ?? () {
          // Prevent double-tap actions
          if (_isTapping) return;
          _isTapping = true;

          HapticFeedback.mediumImpact();
          // Play the radio station on selected player
          final selectedPlayer = maProvider.selectedPlayer;
          if (selectedPlayer != null) {
            maProvider.api?.playRadioStation(selectedPlayer.playerId, widget.radioStation);
          }

          // Reset after debounce delay
          Future.delayed(Timings.navigationDebounce, () {
            if (mounted) _isTapping = false;
          });
        },
        onLongPressStart: (details) {
          HapticFeedback.mediumImpact();
          MediaContextMenu.show(
            context: context,
            position: details.globalPosition,
            mediaType: ContextMenuMediaType.radio,
            item: widget.radioStation,
            isFavorite: _isFavorite,
            isInLibrary: _isInLibrary,
            onToggleFavorite: _toggleFavorite,
            onToggleLibrary: _toggleLibrary,
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Radio station artwork - circular for radio
            AspectRatio(
              aspectRatio: 1.0,
              child: Hero(
                tag: HeroTags.radioCover + (widget.radioStation.uri ?? widget.radioStation.itemId) + suffix,
                child: ClipOval(
                  child: Container(
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
                                Icons.radio_rounded,
                                size: 64,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : Center(
                            child: Icon(
                              Icons.radio_rounded,
                              size: 64,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Radio station name - fixed height container so image size is consistent
            SizedBox(
              height: 36, // Fixed height for 2 lines of text
              child: Hero(
                tag: HeroTags.radioTitle + (widget.radioStation.uri ?? widget.radioStation.itemId) + suffix,
                child: Material(
                  color: Colors.transparent,
                  child: Text(
                    widget.radioStation.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: textTheme.titleSmall?.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w500,
                      height: 1.15,
                    ),
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
