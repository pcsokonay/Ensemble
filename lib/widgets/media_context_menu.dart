import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/media_item.dart';
import '../providers/music_assistant_provider.dart';
import '../widgets/global_player_overlay.dart' show GlobalPlayerOverlay, BottomSpacing;
import '../l10n/app_localizations.dart';
import '../services/debug_logger.dart';

/// The type of media item for the context menu
enum ContextMenuMediaType {
  album,
  artist,
  playlist,
  track,
  audiobook,
  podcast,
  radio,
}

/// Shows a floating context menu for media actions
class MediaContextMenu {
  static OverlayEntry? _currentOverlay;

  /// Show the context menu at the given position
  static void show({
    required BuildContext context,
    required Offset position,
    required ContextMenuMediaType mediaType,
    required dynamic item,
    required bool isFavorite,
    required bool isInLibrary,
    ColorScheme? adaptiveColorScheme,
    VoidCallback? onDismiss,
    VoidCallback? onToggleFavorite,
    VoidCallback? onToggleLibrary,
    bool showTopRow = true,
  }) {
    // Close any existing menu
    hide();

    // Haptic feedback for long-press menu
    HapticFeedback.mediumImpact();

    final overlay = Navigator.of(context).overlay;
    if (overlay == null) return;

    _currentOverlay = OverlayEntry(
      builder: (context) => _MediaContextMenuOverlay(
        position: position,
        mediaType: mediaType,
        item: item,
        isFavorite: isFavorite,
        isInLibrary: isInLibrary,
        adaptiveColorScheme: adaptiveColorScheme,
        onToggleFavorite: onToggleFavorite,
        onToggleLibrary: onToggleLibrary,
        showTopRow: showTopRow,
        onDismiss: () {
          hide();
          onDismiss?.call();
        },
      ),
    );

    overlay.insert(_currentOverlay!);
  }

  /// Hide the current context menu
  static void hide() {
    _currentOverlay?.remove();
    _currentOverlay = null;
  }
}

class _MediaContextMenuOverlay extends StatefulWidget {
  final Offset position;
  final ContextMenuMediaType mediaType;
  final dynamic item;
  final bool isFavorite;
  final bool isInLibrary;
  final ColorScheme? adaptiveColorScheme;
  final VoidCallback onDismiss;
  final VoidCallback? onToggleFavorite;
  final VoidCallback? onToggleLibrary;
  final bool showTopRow;

  const _MediaContextMenuOverlay({
    required this.position,
    required this.mediaType,
    required this.item,
    required this.isFavorite,
    required this.isInLibrary,
    this.adaptiveColorScheme,
    required this.onDismiss,
    this.onToggleFavorite,
    this.onToggleLibrary,
    this.showTopRow = true,
  });

  @override
  State<_MediaContextMenuOverlay> createState() => _MediaContextMenuOverlayState();
}

class _MediaContextMenuOverlayState extends State<_MediaContextMenuOverlay>
    with SingleTickerProviderStateMixin {
  static final _logger = DebugLogger();
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 150),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOut),
    );
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  /// Get the item name for display
  String get _itemName {
    switch (widget.mediaType) {
      case ContextMenuMediaType.album:
        return (widget.item as Album).name;
      case ContextMenuMediaType.artist:
        return (widget.item as Artist).name;
      case ContextMenuMediaType.playlist:
        return (widget.item as Playlist).name;
      case ContextMenuMediaType.track:
        return (widget.item as Track).name;
      case ContextMenuMediaType.audiobook:
        return (widget.item as Audiobook).name;
      case ContextMenuMediaType.podcast:
      case ContextMenuMediaType.radio:
        return (widget.item as MediaItem).name;
    }
  }

  /// Play the item instantly using selected player
  Future<void> _play(BuildContext context) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;
    final l10n = S.of(context)!;

    if (player == null) {
      _showSnackBar(context, l10n.noPlayerSelected);
      return;
    }

    widget.onDismiss();

    try {
      switch (widget.mediaType) {
        case ContextMenuMediaType.album:
          final album = widget.item as Album;
          await maProvider.api?.playAlbum(player.playerId, album);
          break;
        case ContextMenuMediaType.artist:
          // For artists, play artist radio (no direct "play artist" method)
          final artist = widget.item as Artist;
          await maProvider.api?.playArtistRadio(player.playerId, artist);
          break;
        case ContextMenuMediaType.playlist:
          final playlist = widget.item as Playlist;
          await maProvider.api?.playPlaylist(player.playerId, playlist);
          break;
        case ContextMenuMediaType.track:
          final track = widget.item as Track;
          await maProvider.playTracks(player.playerId, [track], startIndex: 0);
          break;
        case ContextMenuMediaType.audiobook:
          final audiobook = widget.item as Audiobook;
          await maProvider.api?.playAudiobook(player.playerId, audiobook);
          break;
        case ContextMenuMediaType.podcast:
          // Podcasts are shows, not directly playable - would need to play latest episode
          break;
        case ContextMenuMediaType.radio:
          final station = widget.item as MediaItem;
          await maProvider.api?.playRadioStation(player.playerId, station);
          break;
      }
    } catch (e) {
      _logger.log('Error playing item: $e');
    }
  }

  /// Show player selector for play
  void _playOn(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final l10n = S.of(context)!;

    widget.onDismiss();

    GlobalPlayerOverlay.showPlayerSelectorForAction(
      contextHint: l10n.playOn,
      onPlayerSelected: (player) async {
        try {
          switch (widget.mediaType) {
            case ContextMenuMediaType.album:
              final album = widget.item as Album;
              await maProvider.api?.playAlbum(player.playerId, album);
              break;
            case ContextMenuMediaType.artist:
              final artist = widget.item as Artist;
              await maProvider.api?.playArtistRadio(player.playerId, artist);
              break;
            case ContextMenuMediaType.playlist:
              final playlist = widget.item as Playlist;
              await maProvider.api?.playPlaylist(player.playerId, playlist);
              break;
            case ContextMenuMediaType.track:
              final track = widget.item as Track;
              await maProvider.playTracks(player.playerId, [track], startIndex: 0);
              break;
            case ContextMenuMediaType.audiobook:
              final audiobook = widget.item as Audiobook;
              await maProvider.api?.playAudiobook(player.playerId, audiobook);
              break;
            case ContextMenuMediaType.podcast:
              // Podcasts are shows, not directly playable
              break;
            case ContextMenuMediaType.radio:
              final station = widget.item as MediaItem;
              await maProvider.api?.playRadioStation(player.playerId, station);
              break;
          }
        } catch (e) {
          _logger.log('Error playing item: $e');
        }
      },
    );
  }

  /// Add to queue instantly using selected player
  Future<void> _addToQueue(BuildContext context) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;
    final l10n = S.of(context)!;

    if (player == null) {
      _showSnackBar(context, l10n.noPlayerSelected);
      return;
    }

    widget.onDismiss();

    try {
      switch (widget.mediaType) {
        case ContextMenuMediaType.album:
          final album = widget.item as Album;
          final tracks = await maProvider.api?.getAlbumTracks(album.provider, album.itemId);
          if (tracks != null && tracks.isNotEmpty) {
            await maProvider.addTracksToQueue(player.playerId, tracks);
            if (context.mounted) _showSnackBar(context, l10n.albumAddedToQueue);
          }
          break;
        case ContextMenuMediaType.playlist:
          final playlist = widget.item as Playlist;
          final tracks = await maProvider.api?.getPlaylistTracks(playlist.provider, playlist.itemId);
          if (tracks != null && tracks.isNotEmpty) {
            await maProvider.addTracksToQueue(player.playerId, tracks);
            if (context.mounted) _showSnackBar(context, l10n.tracksAddedToQueue);
          }
          break;
        case ContextMenuMediaType.track:
          final track = widget.item as Track;
          await maProvider.addTracksToQueue(player.playerId, [track]);
          if (context.mounted) _showSnackBar(context, l10n.trackAddedToQueue);
          break;
        case ContextMenuMediaType.artist:
        case ContextMenuMediaType.audiobook:
        case ContextMenuMediaType.podcast:
        case ContextMenuMediaType.radio:
          // These types don't support direct queue addition
          break;
      }
    } catch (e) {
      _logger.log('Error adding to queue: $e');
    }
  }

  /// Show player selector for add to queue
  void _addToQueueOn(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final l10n = S.of(context)!;

    widget.onDismiss();

    GlobalPlayerOverlay.showPlayerSelectorForAction(
      contextHint: l10n.addToQueueOn,
      onPlayerSelected: (player) async {
        try {
          switch (widget.mediaType) {
            case ContextMenuMediaType.album:
              final album = widget.item as Album;
              final tracks = await maProvider.api?.getAlbumTracks(album.provider, album.itemId);
              if (tracks != null && tracks.isNotEmpty) {
                await maProvider.addTracksToQueue(player.playerId, tracks);
              }
              break;
            case ContextMenuMediaType.playlist:
              final playlist = widget.item as Playlist;
              final tracks = await maProvider.api?.getPlaylistTracks(playlist.provider, playlist.itemId);
              if (tracks != null && tracks.isNotEmpty) {
                await maProvider.addTracksToQueue(player.playerId, tracks);
              }
              break;
            case ContextMenuMediaType.track:
              final track = widget.item as Track;
              await maProvider.addTracksToQueue(player.playerId, [track]);
              break;
            case ContextMenuMediaType.artist:
            case ContextMenuMediaType.audiobook:
            case ContextMenuMediaType.podcast:
            case ContextMenuMediaType.radio:
              // These types don't support direct queue addition
              break;
          }
        } catch (e) {
          _logger.log('Error adding to queue: $e');
        }
      },
    );
  }

  /// Start radio instantly using selected player
  Future<void> _startRadio(BuildContext context) async {
    final maProvider = context.read<MusicAssistantProvider>();
    final player = maProvider.selectedPlayer;
    final l10n = S.of(context)!;

    if (player == null) {
      _showSnackBar(context, l10n.noPlayerSelected);
      return;
    }

    widget.onDismiss();

    try {
      switch (widget.mediaType) {
        case ContextMenuMediaType.artist:
          final artist = widget.item as Artist;
          await maProvider.api?.playArtistRadio(player.playerId, artist);
          break;
        case ContextMenuMediaType.track:
          final track = widget.item as Track;
          await maProvider.playRadio(player.playerId, track);
          break;
        case ContextMenuMediaType.album:
        case ContextMenuMediaType.playlist:
        case ContextMenuMediaType.audiobook:
        case ContextMenuMediaType.podcast:
        case ContextMenuMediaType.radio:
          // These types don't support radio mode
          break;
      }
    } catch (e) {
      _logger.log('Error starting radio: $e');
    }
  }

  /// Show player selector for start radio
  void _startRadioOn(BuildContext context) {
    final maProvider = context.read<MusicAssistantProvider>();
    final l10n = S.of(context)!;

    widget.onDismiss();

    GlobalPlayerOverlay.showPlayerSelectorForAction(
      contextHint: l10n.startRadioOn(_itemName),
      onPlayerSelected: (player) async {
        try {
          switch (widget.mediaType) {
            case ContextMenuMediaType.artist:
              final artist = widget.item as Artist;
              await maProvider.api?.playArtistRadio(player.playerId, artist);
              break;
            case ContextMenuMediaType.track:
              final track = widget.item as Track;
              await maProvider.playRadio(player.playerId, track);
              break;
            case ContextMenuMediaType.album:
            case ContextMenuMediaType.playlist:
            case ContextMenuMediaType.audiobook:
            case ContextMenuMediaType.podcast:
            case ContextMenuMediaType.radio:
              // These types don't support radio mode
              break;
          }
        } catch (e) {
          _logger.log('Error starting radio: $e');
        }
      },
    );
  }

  void _handleToggleFavorite() {
    widget.onDismiss();
    widget.onToggleFavorite?.call();
  }

  void _handleToggleLibrary() {
    widget.onDismiss();
    widget.onToggleLibrary?.call();
  }

  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  /// Check if queue actions should be shown for this media type
  bool get _supportsQueue {
    return widget.mediaType == ContextMenuMediaType.album ||
        widget.mediaType == ContextMenuMediaType.playlist ||
        widget.mediaType == ContextMenuMediaType.track;
  }

  /// Check if radio actions should be shown for this media type
  bool get _supportsRadio {
    return widget.mediaType == ContextMenuMediaType.artist ||
        widget.mediaType == ContextMenuMediaType.track;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.adaptiveColorScheme ?? Theme.of(context).colorScheme;
    final l10n = S.of(context)!;

    // Calculate menu position
    const menuWidth = 180.0;
    final screenSize = MediaQuery.of(context).size;
    final viewPadding = MediaQuery.of(context).viewPadding;

    // Account for mini player and bottom nav bar
    final bottomInset = BottomSpacing.withMiniPlayer + viewPadding.bottom;

    // Position near the tap, but keep on screen
    double left = widget.position.dx - menuWidth / 2;
    double top = widget.position.dy;

    // Keep menu on screen horizontally
    left = left.clamp(8.0, screenSize.width - menuWidth - 8);

    // Estimate menu height based on whether top row is shown
    final estimatedHeight = widget.showTopRow ? 280.0 : 180.0;

    // If menu would go off bottom (accounting for mini player), position above the tap point
    if (top + estimatedHeight > screenSize.height - bottomInset) {
      top = widget.position.dy - estimatedHeight;
    }
    top = top.clamp(viewPadding.top + 8, screenSize.height - estimatedHeight - bottomInset);

    return Stack(
      children: [
        // Dismiss on tap outside
        FadeTransition(
          opacity: _fadeAnimation,
          child: ModalBarrier(
            dismissible: true,
            onDismiss: widget.onDismiss,
            color: Colors.black12,
          ),
        ),
        // Menu with scale and fade animation
        Positioned(
          left: left,
          top: top,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ScaleTransition(
              scale: _scaleAnimation,
              alignment: Alignment.center,
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                // Use lighter surface when adaptive colors are applied for better contrast
                // Blend with white to make it noticeably lighter than the background
                color: widget.adaptiveColorScheme != null
                    ? Color.lerp(colorScheme.surface, Colors.white, 0.25)!
                    : colorScheme.surface,
                child: Container(
                  width: menuWidth,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Top row: instant action buttons
                      if (widget.showTopRow) ...[
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // Play button
                              _buildIconButton(
                                icon: Icons.play_arrow_rounded,
                                label: l10n.play,
                                onTap: () => _play(context),
                                colorScheme: colorScheme,
                              ),
                              // Library button
                              if (widget.onToggleLibrary != null) ...[
                                const SizedBox(width: 12),
                                _buildIconButton(
                                  icon: widget.isInLibrary ? Icons.library_add_check : Icons.library_add,
                                  label: widget.isInLibrary ? l10n.inLibrary : l10n.addToLibrary,
                                  onTap: _handleToggleLibrary,
                                  colorScheme: colorScheme,
                                  isActive: widget.isInLibrary,
                                ),
                              ],
                              // Favorite button
                              if (widget.onToggleFavorite != null) ...[
                                const SizedBox(width: 12),
                                _buildIconButton(
                                  icon: widget.isFavorite ? Icons.favorite : Icons.favorite_border,
                                  label: l10n.favorite,
                                  onTap: _handleToggleFavorite,
                                  colorScheme: colorScheme,
                                  isActive: widget.isFavorite,
                                  activeColor: Colors.red,
                                ),
                              ],
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                      ],
                      // List items
                      _buildMenuItem(
                        icon: Icons.speaker_group_outlined,
                        label: l10n.playOn,
                        onTap: () => _playOn(context),
                        colorScheme: colorScheme,
                      ),
                      if (_supportsQueue) ...[
                        _buildMenuItem(
                          icon: Icons.playlist_add,
                          label: l10n.addToQueue,
                          onTap: () => _addToQueue(context),
                          colorScheme: colorScheme,
                        ),
                        _buildMenuItem(
                          icon: Icons.speaker_group_outlined,
                          label: l10n.addToQueueOn,
                          onTap: () => _addToQueueOn(context),
                          colorScheme: colorScheme,
                        ),
                      ],
                      if (_supportsRadio) ...[
                        _buildMenuItem(
                          icon: Icons.radio,
                          label: l10n.startRadio,
                          onTap: () => _startRadio(context),
                          colorScheme: colorScheme,
                        ),
                        _buildMenuItem(
                          icon: Icons.speaker_group_outlined,
                          label: l10n.startRadioOn(_itemName),
                          onTap: () => _startRadioOn(context),
                          colorScheme: colorScheme,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    bool isActive = false,
    Color? activeColor,
  }) {
    final iconColor = isActive
        ? (activeColor ?? colorScheme.primary)
        : colorScheme.onSurfaceVariant;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 44,
          height: 44,
          child: FilledButton.tonal(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: 22,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isActive ? iconColor : colorScheme.onSurface,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
