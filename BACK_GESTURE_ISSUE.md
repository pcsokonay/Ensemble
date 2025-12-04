# Back Gesture Issue: Expanded Player vs Screen Navigation

## Problem Summary

When the full-screen player is expanded and the user performs a back gesture, the **screen behind the player** receives the back event instead of the player. This causes the underlying screen (e.g., AlbumDetailsScreen) to pop, while the expanded player remains visible.

### Steps to Reproduce
1. Have mini player active (playing music)
2. Navigate to an album (AlbumDetailsScreen)
3. Tap on mini player to expand to full-screen player
4. Perform back gesture (swipe from edge or press back button)
5. **Expected:** Full-screen player collapses to mini player
6. **Actual:** AlbumDetailsScreen pops, returning to home. Full-screen player stays expanded. Second back gesture then collapses the player.

## Architecture Context

### Widget Tree Structure
```
MaterialApp
├── builder: GlobalPlayerOverlay (wraps entire app)
│   └── Stack
│       ├── [0] widget.child (Navigator with all screens)
│       │   └── HomeScreen
│       │       └── [pushed routes: AlbumDetailsScreen, ArtistDetailsScreen, etc.]
│       ├── [1] Positioned: BottomNavigationBar
│       └── [2] ExpandablePlayer (mini player / full-screen player)
```

### Key Files
- `/lib/widgets/global_player_overlay.dart` - Wraps app, contains Stack with nav bar + player
- `/lib/widgets/expandable_player.dart` - The morphing mini-to-fullscreen player
- `/lib/screens/home_screen.dart` - Has PopScope with player collapse logic (works!)
- `/lib/screens/album_details_screen.dart` - Pushed route, needs back handling
- `/lib/screens/artist_details_screen.dart` - Pushed route, needs back handling
- `/lib/main.dart` - GlobalPlayerOverlay applied via `builder` parameter

### Why the Player is Outside Navigator
The player needs to:
1. Persist across all screen transitions (not rebuild/animate during navigation)
2. Overlay the bottom navigation bar
3. Expand to full screen above all content
4. Have smooth animations independent of page transitions

This is why it's in `GlobalPlayerOverlay` which wraps the entire app at the `builder` level.

## Attempted Solutions

### 1. PopScope on Detail Screens (FAILED)
**Approach:** Add `PopScope` to AlbumDetailsScreen with `canPop: !GlobalPlayerOverlay.isPlayerExpanded`

**Why it failed:** `canPop` is evaluated when the widget builds, not dynamically. When user taps an album, player isn't expanded, so `canPop` is `true`. Later when player expands, the PopScope doesn't re-evaluate.

```dart
// This doesn't work - canPop evaluated at build time
PopScope(
  canPop: !GlobalPlayerOverlay.isPlayerExpanded,  // Always true at build!
  onPopInvokedWithResult: (didPop, result) {
    if (GlobalPlayerOverlay.isPlayerExpanded) {
      GlobalPlayerOverlay.collapsePlayer();  // Never reached
    }
  },
)
```

### 2. BackButtonListener in GlobalPlayerOverlay (FAILED - WHITE SCREEN)
**Approach:** Use `BackButtonListener` widget to intercept back button at app level

**Why it failed:** `BackButtonListener` requires a `Router` ancestor in the widget tree. Since `GlobalPlayerOverlay` is applied via `builder` (before the Navigator/Router), there's no Router above it.

```dart
// This caused white screen crash - no Router ancestor
return BackButtonListener(
  onBackButtonPressed: () async {
    if (GlobalPlayerOverlay.isPlayerExpanded) {
      GlobalPlayerOverlay.collapsePlayer();
      return true;
    }
    return false;
  },
  child: Stack(...),
);
```

### 3. PopScope on ExpandablePlayer Itself (NOT ATTEMPTED)
**Hypothesis:** Wrapping the expanded player with PopScope might work since it's rendered as part of the widget tree.

**Concern:** The player is a `Positioned` widget inside a `Stack` that's outside the Navigator. PopScope might not receive route pop events for the same reason as #2.

## Potential Solutions to Explore

### A. WidgetsBindingObserver
Register the GlobalPlayerOverlay or ExpandablePlayer as a `WidgetsBindingObserver` to intercept `didPopRoute()` at the system level.

```dart
class _GlobalPlayerOverlayState extends State<GlobalPlayerOverlay>
    with WidgetsBindingObserver {

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Future<bool> didPopRoute() async {
    if (GlobalPlayerOverlay.isPlayerExpanded) {
      GlobalPlayerOverlay.collapsePlayer();
      return true;  // Consumed
    }
    return false;  // Let Navigator handle
  }
}
```

**Pros:** Intercepts at system level before Navigator
**Cons:** May interfere with other back handling, need to test priority

### B. Custom NavigatorObserver
Create a NavigatorObserver that checks player state and prevents/modifies pops.

**Concern:** NavigatorObserver sees pops but can't easily prevent them.

### C. Nested Navigator for Player
Wrap the expanded player content in its own Navigator so it has its own route stack.

**Concern:** Complex, may break the smooth expand/collapse animation.

### D. Platform Channel for Back Button
Use a platform channel to intercept Android back button before Flutter receives it.

**Concern:** Overkill, platform-specific, maintenance burden.

### E. HardwareKeyboard Listener
Listen for hardware back key events.

**Concern:** Doesn't intercept gesture navigation on Android 10+.

### F. Predictive Back Gesture API
Android 13+ has predictive back gesture API. May need special handling.

### G. Focus-Based Approach
When player expands, request focus and handle key events.

**Concern:** May not work for gesture navigation.

## Relevant Code Snippets

### HomeScreen PopScope (WORKS)
This works because HomeScreen is the root of the Navigator and always exists:
```dart
// lib/screens/home_screen.dart lines 59-92
PopScope(
  canPop: false,  // Always false - we handle all pops
  onPopInvokedWithResult: (didPop, result) {
    if (didPop) return;

    // If global player is expanded, collapse it first
    if (GlobalPlayerOverlay.isPlayerExpanded) {
      GlobalPlayerOverlay.collapsePlayer();
      return;
    }

    // If not on home tab, navigate to home
    if (selectedIndex != 0) {
      navigationProvider.setSelectedIndex(0);
      return;
    }

    // On home tab - double press to minimize
    // ...
  },
)
```

### ExpandablePlayer Collapse Method
```dart
// lib/widgets/expandable_player.dart lines 143-148
void collapse() {
  _queuePanelController.value = 0;
  _controller.reverse();
}

bool get isExpanded => _controller.value > 0.5;
```

### GlobalPlayerOverlay Static Methods
```dart
// lib/widgets/global_player_overlay.dart lines 52-63
static void collapsePlayer() {
  globalPlayerKey.currentState?.collapse();
}

static bool get isPlayerExpanded =>
    globalPlayerKey.currentState?.isExpanded ?? false;
```

## Testing Checklist

When testing a solution:
- [ ] Back gesture from expanded player on HomeScreen
- [ ] Back gesture from expanded player on AlbumDetailsScreen
- [ ] Back gesture from expanded player on ArtistDetailsScreen
- [ ] Back gesture from expanded player on PlaylistDetailsScreen
- [ ] Back gesture from expanded player on SearchScreen
- [ ] Android back button (not gesture)
- [ ] Android 10+ gesture navigation
- [ ] Android 13+ predictive back gesture
- [ ] Queue panel open + back gesture (should close queue first)
- [ ] App doesn't crash/white screen on any scenario

## Priority

HIGH - This is a UX-breaking issue. Users instinctively press back to close the full-screen player, but instead lose their navigation context.

## Related Files to Understand

1. `lib/widgets/global_player_overlay.dart` - Where the player lives
2. `lib/widgets/expandable_player.dart` - Player implementation
3. `lib/screens/home_screen.dart` - Working PopScope example
4. `lib/main.dart` - How GlobalPlayerOverlay wraps the app
5. `lib/providers/navigation_provider.dart` - Navigation state management

## Build/Test Commands

```bash
# Trigger build
gh workflow run "Build Android APK" --ref fix/player-discovery-auth

# Watch build
gh run watch <run_id>

# Check recent builds
gh run list --limit 5
```

---

**Created:** 2025-12-04
**Status:** UNSOLVED
**Last Attempted:** BackButtonListener (caused white screen crash)
**Recommended Next Step:** Try WidgetsBindingObserver approach (Solution A)
