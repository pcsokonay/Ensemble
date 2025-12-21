import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/music_assistant_provider.dart';
import '../providers/navigation_provider.dart';
import '../theme/theme_provider.dart';
import 'expandable_player.dart';

/// Cached color with contrast adjustment
/// Avoids expensive HSL conversions during scroll
class _CachedNavColor {
  Color? _sourceColor;
  bool? _isDark;
  Color? _adjustedColor;

  Color getAdjustedColor(Color sourceColor, bool isDark) {
    // Return cached value if inputs haven't changed
    if (_sourceColor == sourceColor && _isDark == isDark && _adjustedColor != null) {
      return _adjustedColor!;
    }

    // Compute new adjusted color
    var navSelectedColor = sourceColor;
    if (isDark && navSelectedColor.computeLuminance() < 0.2) {
      final hsl = HSLColor.fromColor(navSelectedColor);
      navSelectedColor = hsl.withLightness((hsl.lightness + 0.3).clamp(0.0, 0.8)).toColor();
    } else if (!isDark && navSelectedColor.computeLuminance() > 0.8) {
      final hsl = HSLColor.fromColor(navSelectedColor);
      navSelectedColor = hsl.withLightness((hsl.lightness - 0.3).clamp(0.2, 1.0)).toColor();
    }

    // Cache the result
    _sourceColor = sourceColor;
    _isDark = isDark;
    _adjustedColor = navSelectedColor;

    return navSelectedColor;
  }
}

final _cachedNavColor = _CachedNavColor();

/// A global key to access the player state from anywhere in the app
final globalPlayerKey = GlobalKey<ExpandablePlayerState>();

/// Key for the overlay state to control visibility
final _overlayStateKey = GlobalKey<_GlobalPlayerOverlayState>();

/// Constants for bottom UI elements spacing
class BottomSpacing {
  /// Height of the bottom navigation bar
  static const double navBarHeight = 56.0;

  /// Height of mini player when visible (64px height + 12px margin)
  static const double miniPlayerHeight = 76.0;

  /// Space needed when only nav bar is visible (with some extra padding)
  static const double navBarOnly = navBarHeight + 16.0;

  /// Space needed when mini player is also visible
  static const double withMiniPlayer = navBarHeight + miniPlayerHeight + 22.0;
}

/// ValueNotifier for player expansion progress (0.0 to 1.0) and background color
class PlayerExpansionState {
  final double progress;
  final Color? backgroundColor;
  PlayerExpansionState(this.progress, this.backgroundColor);
}
final playerExpansionNotifier = ValueNotifier<PlayerExpansionState>(PlayerExpansionState(0.0, null));

/// Wrapper widget that provides a global player overlay above all navigation.
///
/// This ensures the mini player and expanded player are consistent across
/// all screens (home, library, album details, artist details, etc.) without
/// needing separate player instances in each screen.
class GlobalPlayerOverlay extends StatefulWidget {
  final Widget child;

  GlobalPlayerOverlay({
    required this.child,
  }) : super(key: _overlayStateKey);

  @override
  State<GlobalPlayerOverlay> createState() => _GlobalPlayerOverlayState();

  /// Collapse the player if it's expanded
  static void collapsePlayer() {
    globalPlayerKey.currentState?.collapse();
  }

  /// Check if the player is currently expanded
  static bool get isPlayerExpanded =>
      globalPlayerKey.currentState?.isExpanded ?? false;

  /// Get the current expansion progress (0.0 to 1.0)
  static double get expansionProgress =>
      globalPlayerKey.currentState?.expansionProgress ?? 0.0;

  /// Get the current expanded background color
  static Color? get expandedBackgroundColor =>
      globalPlayerKey.currentState?.currentExpandedBgColor;

  /// Hide the mini player temporarily (e.g., when showing device selector)
  /// The player slides down off-screen with animation
  static void hidePlayer() {
    _overlayStateKey.currentState?._setHidden(true);
  }

  /// Show the mini player again (slides back up)
  static void showPlayer() {
    _overlayStateKey.currentState?._setHidden(false);
  }
}

class _GlobalPlayerOverlayState extends State<GlobalPlayerOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _slideAnimation = CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  void _setHidden(bool hidden) {
    if (hidden) {
      _slideController.forward();
    } else {
      _slideController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Stack(
      children: [
        // The main app content (Navigator, screens, etc.)
        // Add bottom padding to account for bottom nav + mini player
        Padding(
          padding: const EdgeInsets.only(bottom: 0), // Content manages its own padding
          child: widget.child,
        ),
        // Global persistent bottom navigation bar - positioned at bottom
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: ListenableBuilder(
            listenable: navigationProvider,
            builder: (context, _) {
              return Consumer<ThemeProvider>(
                builder: (context, themeProvider, _) {
                  // Use adaptive primary color for bottom nav when adaptive theme is enabled
                  final sourceColor = themeProvider.adaptiveTheme
                      ? themeProvider.adaptivePrimaryColor
                      : colorScheme.primary;

                  // Use cached color computation to avoid expensive HSL operations during scroll
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  final navSelectedColor = _cachedNavColor.getAdjustedColor(sourceColor, isDark);

                  // Base background: use adaptive surface color if available, otherwise default surface
                  final baseBgColor = (themeProvider.adaptiveTheme && themeProvider.adaptiveSurfaceColor != null)
                      ? themeProvider.adaptiveSurfaceColor!
                      : colorScheme.surface;

                  return ValueListenableBuilder<PlayerExpansionState>(
                    valueListenable: playerExpansionNotifier,
                    // Pass BottomNavigationBar as child to avoid rebuilding it every frame
                    child: BottomNavigationBar(
                      currentIndex: navigationProvider.selectedIndex,
                      onTap: (index) {
                        if (GlobalPlayerOverlay.isPlayerExpanded) {
                          GlobalPlayerOverlay.collapsePlayer();
                        }
                        navigationProvider.navigatorKey.currentState?.popUntil((route) => route.isFirst);
                        if (index == 3) {
                          GlobalPlayerOverlay.hidePlayer();
                        } else if (navigationProvider.selectedIndex == 3) {
                          GlobalPlayerOverlay.showPlayer();
                        }
                        navigationProvider.setSelectedIndex(index);
                      },
                      backgroundColor: Colors.transparent,
                      selectedItemColor: navSelectedColor,
                      unselectedItemColor: colorScheme.onSurface.withOpacity(0.54),
                      elevation: 0,
                      type: BottomNavigationBarType.fixed,
                      selectedFontSize: 12,
                      unselectedFontSize: 12,
                      items: [
                        BottomNavigationBarItem(
                          icon: const Icon(Icons.home_outlined),
                          activeIcon: const Icon(Icons.home_rounded),
                          label: S.of(context)!.home,
                        ),
                        BottomNavigationBarItem(
                          icon: const Icon(Icons.library_music_outlined),
                          activeIcon: const Icon(Icons.library_music_rounded),
                          label: S.of(context)!.library,
                        ),
                        BottomNavigationBarItem(
                          icon: const Icon(Icons.search_rounded),
                          activeIcon: const Icon(Icons.search_rounded),
                          label: S.of(context)!.search,
                        ),
                        BottomNavigationBarItem(
                          icon: const Icon(Icons.settings_outlined),
                          activeIcon: const Icon(Icons.settings_rounded),
                          label: S.of(context)!.settings,
                        ),
                      ],
                    ),
                    builder: (context, expansionState, navBar) {
                      // Only compute colors during animation - this is the hot path
                      final navBgColor = expansionState.progress > 0 && expansionState.backgroundColor != null
                          ? Color.lerp(baseBgColor, expansionState.backgroundColor, expansionState.progress)!
                          : baseBgColor;

                      // Use AnimatedContainer for smoother transitions instead of rebuilding
                      return Container(
                        decoration: BoxDecoration(
                          color: navBgColor,
                          boxShadow: expansionState.progress < 0.5
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 10,
                                    offset: const Offset(0, -2),
                                  ),
                                ]
                              : null,
                        ),
                        child: navBar, // Reuse pre-built navigation bar
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
        // Global player overlay - slides down when hidden, renders ON TOP of bottom nav
        // Use Selector instead of Consumer to avoid rebuilds during animation
        Selector<MusicAssistantProvider, ({bool isConnected, bool hasPlayer})>(
          selector: (_, provider) => (
            isConnected: provider.isConnected,
            hasPlayer: provider.selectedPlayer != null,
          ),
          builder: (context, state, child) {
            // Only show player if connected and has a selected player
            if (!state.isConnected || !state.hasPlayer) {
              return const SizedBox.shrink();
            }
            return AnimatedBuilder(
              animation: _slideAnimation,
              child: ExpandablePlayer(key: globalPlayerKey, slideOffset: 0),
              builder: (context, staticChild) {
                // Only slideOffset changes during animation, player widget stays same
                return ExpandablePlayer(
                  key: globalPlayerKey,
                  slideOffset: _slideAnimation.value,
                );
              },
            );
          },
        ),
      ],
    );
  }
}
