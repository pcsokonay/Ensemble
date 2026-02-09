import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../widgets/global_player_overlay.dart';
import '../widgets/media_context_menu.dart';
import '../theme/theme_provider.dart';
import '../services/settings_service.dart';
import '../services/metadata_service.dart';
import '../services/debug_logger.dart';
import '../utils/page_transitions.dart';
import '../constants/hero_tags.dart';
import '../l10n/app_localizations.dart';
import '../theme/design_tokens.dart';
import 'audiobook_detail_screen.dart';
import '../widgets/provider_icon.dart';

class AudiobookAuthorScreen extends StatefulWidget {
  final String authorName;
  final List<Audiobook> audiobooks;
  final String? heroTagSuffix;
  final String? initialAuthorImageUrl;

  const AudiobookAuthorScreen({
    super.key,
    required this.authorName,
    required this.audiobooks,
    this.heroTagSuffix,
    this.initialAuthorImageUrl,
  });

  @override
  State<AudiobookAuthorScreen> createState() => _AudiobookAuthorScreenState();
}

class _AudiobookAuthorScreenState extends State<AudiobookAuthorScreen> {
  final _logger = DebugLogger();
  late List<Audiobook> _audiobooks;
  ColorScheme? _lightColorScheme;
  ColorScheme? _darkColorScheme;
  String? _authorImageUrl;

  // View preferences
  String _sortOrder = 'alpha'; // 'alpha' or 'year'
  String _viewMode = 'grid2'; // 'grid2', 'grid3', 'list'

  String get _heroTagSuffix => widget.heroTagSuffix != null ? '_${widget.heroTagSuffix}' : '';

  @override
  void initState() {
    super.initState();
    _audiobooks = List.from(widget.audiobooks);
    // Use initial image URL immediately for smooth hero animation
    _authorImageUrl = widget.initialAuthorImageUrl;
    _loadViewPreferences();
    _sortAudiobooks();
    _loadAuthorImage();
  }

  Future<void> _loadAuthorImage() async {
    final imageUrl = await MetadataService.getAuthorImageUrl(widget.authorName);
    if (mounted && imageUrl != null) {
      setState(() {
        _authorImageUrl = imageUrl;
      });
    }
  }

  Future<void> _loadViewPreferences() async {
    final sortOrder = await SettingsService.getAuthorAudiobooksSortOrder();
    final viewMode = await SettingsService.getAuthorAudiobooksViewMode();
    if (mounted) {
      setState(() {
        _sortOrder = sortOrder;
        _viewMode = viewMode;
        _sortAudiobooks();
      });
    }
  }

  void _toggleSortOrder() {
    final newOrder = _sortOrder == 'alpha' ? 'year' : 'alpha';
    setState(() {
      _sortOrder = newOrder;
      _sortAudiobooks();
    });
    SettingsService.setAuthorAudiobooksSortOrder(newOrder);
  }

  void _cycleViewMode() {
    String newMode;
    switch (_viewMode) {
      case 'grid2':
        newMode = 'grid3';
        break;
      case 'grid3':
        newMode = 'list';
        break;
      default:
        newMode = 'grid2';
    }
    setState(() {
      _viewMode = newMode;
    });
    SettingsService.setAuthorAudiobooksViewMode(newMode);
  }

  void _sortAudiobooks() {
    if (_sortOrder == 'year') {
      _audiobooks.sort((a, b) {
        if (a.year == null && b.year == null) return a.name.compareTo(b.name);
        if (a.year == null) return 1;
        if (b.year == null) return -1;
        return a.year!.compareTo(b.year!);
      });
    } else {
      _audiobooks.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    }
  }

  /// Toggle favorite status for an audiobook
  Future<void> _toggleAudiobookFavorite(Audiobook book) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final newState = !(book.favorite ?? false);

    try {
      bool success;
      if (newState) {
        // Add to favorites
        String actualProvider = book.provider;
        String actualItemId = book.itemId;

        if (book.providerMappings != null && book.providerMappings!.isNotEmpty) {
          final mapping = book.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => book.providerMappings!.firstWhere(
              (m) => m.available,
              orElse: () => book.providerMappings!.first,
            ),
          );
          actualProvider = mapping.providerInstance;
          actualItemId = mapping.itemId;
        }

        success = await maProvider.addToFavorites(
          mediaType: 'audiobook',
          itemId: actualItemId,
          provider: actualProvider,
        );
      } else {
        // Remove from favorites
        int? libraryItemId;
        if (book.provider == 'library') {
          libraryItemId = int.tryParse(book.itemId);
        } else if (book.providerMappings != null) {
          final libraryMapping = book.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => book.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId != null) {
          success = await maProvider.removeFromFavorites(
            mediaType: 'audiobook',
            libraryItemId: libraryItemId,
          );
        } else {
          success = false;
        }
      }

      if (success && mounted) {
        setState(() {
          final index = _audiobooks.indexWhere((b) => b.itemId == book.itemId);
          if (index != -1) {
            _audiobooks[index] = Audiobook(
              itemId: book.itemId,
              provider: book.provider,
              name: book.name,
              sortName: book.sortName,
              uri: book.uri,
              providerMappings: book.providerMappings,
              favorite: newState,
              metadata: book.metadata,
              year: book.year,
            );
          }
        });
      }
    } catch (e) {
      _logger.log('Error toggling audiobook favorite: $e');
    }
  }

  /// Toggle library status for an audiobook
  Future<void> _toggleAudiobookLibrary(Audiobook book) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final newState = !book.inLibrary;

    try {
      bool success;
      if (newState) {
        // Add to library
        String? actualProvider;
        String? actualItemId;

        if (book.providerMappings != null && book.providerMappings!.isNotEmpty) {
          final mapping = book.providerMappings!.firstWhere(
            (m) => m.available && m.providerInstance != 'library',
            orElse: () => book.providerMappings!.first,
          );
          if (mapping.providerInstance != 'library') {
            actualProvider = mapping.providerInstance;
            actualItemId = mapping.itemId;
          }
        }

        if (actualProvider != null && actualItemId != null) {
          success = await maProvider.addToLibrary(
            mediaType: 'audiobook',
            itemId: actualItemId,
            provider: actualProvider,
          );
        } else {
          success = false;
        }
      } else {
        // Remove from library
        int? libraryItemId;
        if (book.provider == 'library') {
          libraryItemId = int.tryParse(book.itemId);
        } else if (book.providerMappings != null) {
          final libraryMapping = book.providerMappings!.firstWhere(
            (m) => m.providerInstance == 'library',
            orElse: () => book.providerMappings!.first,
          );
          if (libraryMapping.providerInstance == 'library') {
            libraryItemId = int.tryParse(libraryMapping.itemId);
          }
        }

        if (libraryItemId != null) {
          success = await maProvider.removeFromLibrary(
            mediaType: 'audiobook',
            libraryItemId: libraryItemId,
          );
        } else {
          success = false;
        }
      }

      if (success) {
        // Refresh would require reloading from parent - for now just show success
        _logger.log('Audiobook library status toggled');
      }
    } catch (e) {
      _logger.log('Error toggling audiobook library: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
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
            // Responsive cover size: 50% of screen width, clamped between 140-200 (matches artist detail)
            final coverSize = (constraints.maxWidth * 0.5).clamp(140.0, 200.0);
            final expandedHeight = coverSize + 25;

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
                      tag: HeroTags.authorImage + widget.authorName + _heroTagSuffix,
                      child: Container(
                        width: coverSize,
                        height: coverSize,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Icon always present underneath
                            Icon(
                              MdiIcons.accountOutline,
                              size: coverSize * 0.5,
                              color: colorScheme.onPrimaryContainer,
                            ),
                            // Image covers icon when loaded
                            if (_authorImageUrl != null)
                              SizedBox(
                                width: coverSize,
                                height: coverSize,
                                child: ClipOval(
                                  child: CachedNetworkImage(
                                    imageUrl: _authorImageUrl!,
                                    fit: BoxFit.cover,
                                    width: coverSize,
                                    height: coverSize,
                                    memCacheWidth: 256,
                                    fadeInDuration: Duration.zero,
                                    fadeOutDuration: Duration.zero,
                                    placeholder: (_, __) => const SizedBox.shrink(),
                                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24.0, 8.0, 24.0, 24.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Author info on the left
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.authorName,
                            style: textTheme.headlineMedium?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            S.of(context)!.audiobookCount(_audiobooks.length),
                            style: textTheme.bodyLarge?.copyWith(
                              color: colorScheme.onSurface.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Three-dot Menu Button on the right
                    SizedBox(
                      height: 50,
                      width: 50,
                      child: Builder(
                        builder: (buttonContext) => FilledButton.tonal(
                          onPressed: () {
                            final RenderBox box = buttonContext.findRenderObject() as RenderBox;
                            final Offset position = box.localToGlobal(Offset(box.size.width / 2, box.size.height));
                            MediaContextMenu.show(
                              context: context,
                              position: position,
                              mediaType: ContextMenuMediaType.audiobook,
                              item: _audiobooks.isNotEmpty ? _audiobooks.first : null,
                              isFavorite: false,
                              isInLibrary: false,
                              adaptiveColorScheme: adaptiveScheme,
                              showTopRow: false,
                              sortOrder: _sortOrder,
                              onToggleSort: _toggleSortOrder,
                              viewMode: _viewMode,
                              onCycleView: _cycleViewMode,
                            );
                          },
                          style: FilledButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Icon(
                            Icons.more_vert,
                            size: 25,
                            color: Colors.white70,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Audiobooks Section Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24.0, 8.0, 24.0, 8.0),
                child: Text(
                  S.of(context)!.audiobooks,
                  style: textTheme.titleLarge?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            _buildAudiobookSliver(),
            SliverToBoxAdapter(child: SizedBox(height: BottomSpacing.withMiniPlayer)),
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

  Widget _buildAudiobookSliver() {
    if (_viewMode == 'list') {
      return SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) => _buildAudiobookListTile(_audiobooks[index]),
            childCount: _audiobooks.length,
          ),
        ),
      );
    }

    final crossAxisCount = _viewMode == 'grid3' ? 3 : 2;
    final childAspectRatio = _viewMode == 'grid3' ? 0.65 : 0.70;

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverGrid(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          childAspectRatio: childAspectRatio,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildAudiobookCard(_audiobooks[index]),
          childCount: _audiobooks.length,
        ),
      ),
    );
  }

  Widget _buildAudiobookCard(Audiobook book) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(book, size: 256);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final heroSuffix = 'author${_heroTagSuffix}';

    // Get adaptive scheme for context menu
    final themeProvider = context.read<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final adaptiveScheme = themeProvider.adaptiveTheme
        ? (isDark ? _darkColorScheme : _lightColorScheme)
        : null;

    return GestureDetector(
      onLongPressStart: (details) {
        MediaContextMenu.show(
          context: context,
          position: details.globalPosition,
          mediaType: ContextMenuMediaType.audiobook,
          item: book,
          isFavorite: book.favorite ?? false,
          isInLibrary: book.inLibrary,
          adaptiveColorScheme: adaptiveScheme,
          onToggleFavorite: () => _toggleAudiobookFavorite(book),
          onToggleLibrary: () => _toggleAudiobookLibrary(book),
        );
      },
      child: InkWell(
        onTap: () => _navigateToAudiobook(book, heroTagSuffix: heroSuffix, initialImageUrl: imageUrl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1.0,
            child: Stack(
              children: [
                Hero(
                  tag: HeroTags.audiobookCover + (book.uri ?? book.itemId) + '_$heroSuffix',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: imageUrl != null
                          ? CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              width: double.infinity,
                              height: double.infinity,
                              fadeInDuration: Duration.zero,
                              fadeOutDuration: Duration.zero,
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
                if (book.progress > 0)
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: LinearProgressIndicator(
                      value: book.progress,
                      backgroundColor: Colors.black54,
                      valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                      minHeight: 3,
                    ),
                  ),
                // Provider icon overlay
                if (book.providerMappings?.isNotEmpty == true)
                  ProviderIconOverlay(
                    domain: book.providerMappings!.first.providerDomain,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Hero(
            tag: HeroTags.audiobookTitle + (book.uri ?? book.itemId) + '_$heroSuffix',
            child: Material(
              color: Colors.transparent,
              child: Text(
                book.name,
                style: textTheme.titleSmall?.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
          if (book.narratorsString != S.of(context)!.unknownNarrator)
            Text(
              S.of(context)!.narratedBy(book.narratorsString),
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withOpacity(0.6),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAudiobookListTile(Audiobook book) {
    final maProvider = context.read<MusicAssistantProvider>();
    final imageUrl = maProvider.getImageUrl(book, size: 128);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final heroSuffix = 'author${_heroTagSuffix}';

    // Get adaptive scheme for context menu
    final themeProvider = context.read<ThemeProvider>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final adaptiveScheme = themeProvider.adaptiveTheme
        ? (isDark ? _darkColorScheme : _lightColorScheme)
        : null;

    return GestureDetector(
      onLongPressStart: (details) {
        MediaContextMenu.show(
          context: context,
          position: details.globalPosition,
          mediaType: ContextMenuMediaType.audiobook,
          item: book,
          isFavorite: book.favorite ?? false,
          isInLibrary: book.inLibrary,
          adaptiveColorScheme: adaptiveScheme,
          onToggleFavorite: () => _toggleAudiobookFavorite(book),
          onToggleLibrary: () => _toggleAudiobookLibrary(book),
        );
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        leading: Hero(
        tag: HeroTags.audiobookCover + (book.uri ?? book.itemId) + '_$heroSuffix',
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Stack(
            children: [
              Container(
                width: 56,
                height: 56,
                color: colorScheme.surfaceContainerHighest,
                child: imageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: imageUrl,
                        fit: BoxFit.cover,
                        fadeInDuration: Duration.zero,
                        fadeOutDuration: Duration.zero,
                        placeholder: (_, __) => Icon(
                          MdiIcons.bookOutline,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        errorWidget: (_, __, ___) => Icon(
                          MdiIcons.bookOutline,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      )
                    : Icon(
                        MdiIcons.bookOutline,
                        color: colorScheme.onSurfaceVariant,
                      ),
              ),
              if (book.progress > 0)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: LinearProgressIndicator(
                    value: book.progress,
                    backgroundColor: Colors.black54,
                    valueColor: AlwaysStoppedAnimation<Color>(colorScheme.primary),
                    minHeight: 2,
                  ),
                ),
            ],
          ),
        ),
      ),
      title: Hero(
        tag: HeroTags.audiobookTitle + (book.uri ?? book.itemId) + '_$heroSuffix',
        child: Material(
          color: Colors.transparent,
          child: Text(
            book.name,
            style: textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
      subtitle: Text(
        book.narratorsString != S.of(context)!.unknownNarrator
            ? S.of(context)!.narratedBy(book.narratorsString)
            : book.duration != null
                ? _formatDuration(book.duration!)
                : '',
        style: textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurface.withOpacity(0.7),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: book.progress > 0
          ? Text(
              '${(book.progress * 100).toInt()}%',
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.primary,
              ),
            )
          : null,
        onTap: () => _navigateToAudiobook(book, heroTagSuffix: heroSuffix, initialImageUrl: imageUrl),
      ),
    );
  }

  void _navigateToAudiobook(Audiobook book, {String? heroTagSuffix, String? initialImageUrl}) {
    Navigator.push(
      context,
      FadeSlidePageRoute(
        child: AudiobookDetailScreen(
          audiobook: book,
          heroTagSuffix: heroTagSuffix,
          initialImageUrl: initialImageUrl,
        ),
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
}
