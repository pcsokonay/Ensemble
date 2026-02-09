import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../widgets/global_player_overlay.dart';
import '../widgets/provider_icon.dart';
import '../theme/palette_helper.dart';
import '../theme/theme_provider.dart';
import '../theme/design_tokens.dart';
import '../services/debug_logger.dart';
import '../constants/hero_tags.dart';
import '../l10n/app_localizations.dart';

class PodcastEpisodeDetailScreen extends StatefulWidget {
  final MediaItem episode;
  final MediaItem podcast;
  final String? heroTagSuffix;
  final String? initialImageUrl;

  const PodcastEpisodeDetailScreen({
    super.key,
    required this.episode,
    required this.podcast,
    this.heroTagSuffix,
    this.initialImageUrl,
  });

  @override
  State<PodcastEpisodeDetailScreen> createState() => _PodcastEpisodeDetailScreenState();
}

class _PodcastEpisodeDetailScreenState extends State<PodcastEpisodeDetailScreen> {
  final _logger = DebugLogger();
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;

  String get _heroTagSuffix => widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        markDetailScreenEntered(context);
        _extractColors();
      }
    });
  }

  Future<void> _extractColors() async {
    final maProvider = context.read<MusicAssistantProvider>();
    // Try episode image first, fallback to podcast image
    final imageUrl = widget.initialImageUrl ??
        maProvider.getImageUrl(widget.episode, size: 512) ??
        maProvider.getPodcastImageUrl(widget.podcast);

    if (imageUrl != null) {
      try {
        final colorSchemes = await PaletteHelper.extractColorSchemesFromUrl(imageUrl);
        if (mounted && colorSchemes != null) {
          setState(() {
            _lightColorScheme = colorSchemes.$1;
            _darkColorScheme = colorSchemes.$2;
          });

          final themeProvider = context.read<ThemeProvider>();
          themeProvider.updateAdaptiveColors(colorSchemes.$1, colorSchemes.$2, isFromDetailScreen: true);
        }
      } catch (e) {
        _logger.log('Error extracting colors for episode: $e');
      }
    }
  }

  void _playEpisode() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final selectedPlayer = maProvider.selectedPlayer;

    if (selectedPlayer != null) {
      try {
        maProvider.setCurrentPodcastName(widget.podcast.name);
        await maProvider.api?.playPodcastEpisode(selectedPlayer.playerId, widget.episode);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Playing: ${widget.episode.name}'),
              duration: const Duration(seconds: 1),
            ),
          );
        }
      } catch (e) {
        _logger.log('Error playing episode: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to play episode: $e')),
          );
        }
      }
    } else {
      _showPlayOnMenu();
    }
  }

  void _showPlayOnMenu() {
    final maProvider = context.read<MusicAssistantProvider>();

    GlobalPlayerOverlay.showPlayerSelectorForAction(
      contextHint: S.of(context)!.selectPlayerForEpisode,
      onPlayerSelected: (player) async {
        maProvider.selectPlayer(player);
        maProvider.setCurrentPodcastName(widget.podcast.name);
        await maProvider.api?.playPodcastEpisode(player.playerId, widget.episode);
      },
    );
  }

  Future<void> _addToQueue() async {
    final maProvider = context.read<MusicAssistantProvider>();
    final selectedPlayer = maProvider.selectedPlayer;

    if (selectedPlayer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context)!.noPlayerSelected)),
      );
      return;
    }

    try {
      final track = Track(
        itemId: widget.episode.itemId,
        provider: widget.episode.provider,
        name: widget.episode.name,
        uri: widget.episode.uri,
        duration: widget.episode.duration,
        metadata: widget.episode.metadata,
      );
      await maProvider.addTrackToQueue(selectedPlayer.playerId, track);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context)!.addedToQueue),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      _logger.log('Error adding episode to queue: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context)!.failedToAddToQueue(e.toString()))),
        );
      }
    }
  }

  String _formatDuration(Duration? duration) {
    if (duration == null || duration == Duration.zero) return '';
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '$minutes min';
  }

  String? _formatPublishDate(Map<String, dynamic>? metadata) {
    if (metadata == null) return null;

    dynamic dateValue = metadata['published'] ??
        metadata['pub_date'] ??
        metadata['release_date'] ??
        metadata['aired'] ??
        metadata['timestamp'];

    if (dateValue == null) return null;

    try {
      DateTime? date;
      if (dateValue is String) {
        date = DateTime.tryParse(dateValue);
      } else if (dateValue is int) {
        date = DateTime.fromMillisecondsSinceEpoch(dateValue * 1000);
      }

      if (date != null) {
        final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        return '${months[date.month - 1]} ${date.day}, ${date.year}';
      }
    } catch (e) {
      _logger.log('Error parsing release date: $e');
    }

    return null;
  }

  String _stripHtml(String htmlText) {
    final withoutTags = htmlText.replaceAll(RegExp(r'<[^>]*>'), '');
    final decoded = withoutTags
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'");
    return decoded.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  @override
  Widget build(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final episodeImageUrl = maProvider.getImageUrl(widget.episode, size: 512);
    final podcastImageUrl = maProvider.getPodcastImageUrl(widget.podcast);
    final imageUrl = widget.initialImageUrl ?? episodeImageUrl ?? podcastImageUrl;

    final adaptiveTheme = context.select<ThemeProvider, bool>(
      (provider) => provider.adaptiveTheme,
    );
    final adaptiveLightScheme = context.select<ThemeProvider, ColorScheme?>(
      (provider) => provider.adaptiveLightScheme,
    );
    final adaptiveDarkScheme = context.select<ThemeProvider, ColorScheme?>(
      (provider) => provider.adaptiveDarkScheme,
    );

    final isDark = Theme.of(context).brightness == Brightness.dark;

    ColorScheme? adaptiveScheme;
    if (adaptiveTheme) {
      adaptiveScheme = isDark
          ? (_darkColorScheme ?? adaptiveDarkScheme)
          : (_lightColorScheme ?? adaptiveLightScheme);
    }
    final colorScheme = adaptiveScheme ?? Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final description = widget.episode.metadata?['description'] as String?;
    final duration = widget.episode.duration;
    final publishDate = _formatPublishDate(widget.episode.metadata);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          clearAdaptiveColorsOnBack(context);
        }
      },
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: LayoutBuilder(
          builder: (context, constraints) {
            final coverSize = (constraints.maxWidth * 0.6).clamp(180.0, 280.0);
            final expandedHeight = coverSize + 70;

            return Stack(
              children: [
                CustomScrollView(
              slivers: [
                SliverAppBar(
                  expandedHeight: expandedHeight,
                  pinned: true,
                  backgroundColor: colorScheme.surface,
                  leading: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: () {
                      clearAdaptiveColorsOnBack(context);
                      Navigator.pop(context);
                    },
                    color: colorScheme.onSurface,
                  ),
                  flexibleSpace: FlexibleSpaceBar(
                    background: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 60),
                        Hero(
                          tag: HeroTags.podcastEpisodeCover +
                              (widget.episode.uri ?? widget.episode.itemId) + _heroTagSuffix,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: SizedBox(
                              width: coverSize,
                              height: coverSize,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Container(
                                    color: colorScheme.surfaceContainerHighest,
                                    child: imageUrl != null
                                        ? CachedNetworkImage(
                                            imageUrl: imageUrl,
                                            fit: BoxFit.cover,
                                            memCacheWidth: 256,
                                            memCacheHeight: 256,
                                            fadeInDuration: Duration.zero,
                                            fadeOutDuration: Duration.zero,
                                            errorWidget: (_, __, ___) => Center(
                                              child: Icon(
                                                MdiIcons.podcast,
                                                size: coverSize * 0.43,
                                                color: colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          )
                                        : Center(
                                            child: Icon(
                                              MdiIcons.podcast,
                                              size: coverSize * 0.43,
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                  ),
                                  if (widget.episode.providerMappings?.isNotEmpty == true)
                                    ProviderIconOverlay(
                                      domain: widget.episode.providerMappings!.first.providerDomain,
                                      size: 24,
                                      margin: 8,
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Header content with title, podcast name, metadata, and actions
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24.0, 8.0, 24.0, 24.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Episode title
                        Text(
                          widget.episode.name,
                          style: textTheme.headlineMedium?.copyWith(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Spacing.vGap8,

                        // Podcast name (tappable to go back)
                        InkWell(
                          onTap: () => Navigator.pop(context),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4.0),
                            child: Text(
                              widget.podcast.name,
                              style: textTheme.titleMedium?.copyWith(
                                color: colorScheme.primary,
                              ),
                            ),
                          ),
                        ),
                        Spacing.vGap16,

                        // Duration and publish date
                        Row(
                          children: [
                            if (duration != null && duration > Duration.zero) ...[
                              Icon(
                                Icons.access_time,
                                size: 16,
                                color: colorScheme.onSurface.withOpacity(0.6),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatDuration(duration),
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                            ],
                            if (duration != null && duration > Duration.zero && publishDate != null)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text(
                                  '•',
                                  style: textTheme.bodyMedium?.copyWith(
                                    color: colorScheme.onSurface.withOpacity(0.5),
                                  ),
                                ),
                              ),
                            if (publishDate != null)
                              Text(
                                publishDate,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: colorScheme.onSurface.withOpacity(0.6),
                                ),
                              ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Action buttons row
                        Row(
                          children: [
                            // Main Play Button
                            Expanded(
                              child: SizedBox(
                                height: 50,
                                child: ElevatedButton.icon(
                                  onPressed: _playEpisode,
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  label: Text(S.of(context)!.play),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: colorScheme.primary,
                                    foregroundColor: colorScheme.onPrimary,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Play On... Button
                            SizedBox(
                              height: 50,
                              width: 50,
                              child: FilledButton.tonal(
                                onPressed: _showPlayOnMenu,
                                style: FilledButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Icon(Icons.speaker_group_outlined, size: 25),
                              ),
                            ),
                            const SizedBox(width: 12),

                            // Add to Queue Button
                            SizedBox(
                              height: 50,
                              width: 50,
                              child: FilledButton.tonal(
                                onPressed: _addToQueue,
                                style: FilledButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: const Icon(Icons.playlist_add, size: 25),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // Full scrollable description (key feature)
                if (description != null && description.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24.0, 0, 24.0, 24.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            S.of(context)!.about,
                            style: textTheme.titleLarge?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Spacing.vGap12,
                          // Full description - no maxLines, fully scrollable with selectable text
                          SelectableText(
                            _stripHtml(description),
                            style: textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.8),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Bottom spacing for mini player
                SliverToBoxAdapter(
                  child: SizedBox(height: BottomSpacing.withMiniPlayer),
                ),
              ],
            ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: BottomSpacing.withMiniPlayer,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            colorScheme.surface.withOpacity(0.0),
                            colorScheme.surface,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
