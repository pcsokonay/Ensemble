# Feature: Replace "Play On" Popups with Player Selector

## Overview

Replace the `PlayerPickerSheet` popup modal with the existing Player Selector (reveal overlay) when users tap "Play on" buttons throughout the app. This provides a consistent, richer player selection experience.

## Current State

### PlayerPickerSheet Popup
Used in 7+ places:
- `album_details_screen.dart` - Play Album, Play From Here, Play Radio
- `playlist_details_screen.dart` - Play Playlist, Play Radio
- `search_screen.dart` - Play album/playlist/audiobook/radio from search
- `podcast_detail_screen.dart` - Play Episode
- `audiobook_detail_screen.dart` - Play Audiobook
- `queue_screen.dart` - Transfer Queue (special case - keep popup)

### Player Selector (Reveal Overlay)
- Location: `lib/widgets/player/player_reveal_overlay.dart`
- Shows vertical list of all players with artwork, current track, sync status
- Has hints above player list: "Long-press to sync" & "Swipe to adjust volume"
- Triggered by pull-down gesture or device button tap

## Proposed Changes

### 1. Modify PlayerRevealOverlay

**File:** `lib/widgets/player/player_reveal_overlay.dart`

Add new optional parameters:

```dart
class PlayerRevealOverlay extends StatefulWidget {
  final VoidCallback onDismiss;
  final double miniPlayerBottom;
  final double miniPlayerHeight;
  final bool showOnboardingHints;

  // NEW: Callback when player is selected for a pending action
  final void Function(Player player)? onPlayerSelected;

  // NEW: Context hint to display instead of default hints
  // e.g., "Select player to play album"
  final String? contextHint;

  // NEW: Icon for context hint (default: speaker icon)
  final IconData? contextHintIcon;
```

### 2. Modify Hint Display

**File:** `lib/widgets/player/player_reveal_overlay.dart` (around line 386-394)

```dart
// Current:
: Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      buildHintRow(Icons.lightbulb_outline, S.of(context)!.holdToSync),
      const SizedBox(height: 4),
      buildHintRow(Icons.lightbulb_outline, S.of(context)!.swipeToAdjustVolume),
    ],
  ),

// New:
: widget.contextHint != null
    ? buildHintRow(
        widget.contextHintIcon ?? Icons.play_circle_outline,
        widget.contextHint!,
      )
    : Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildHintRow(Icons.lightbulb_outline, S.of(context)!.holdToSync),
          const SizedBox(height: 4),
          buildHintRow(Icons.lightbulb_outline, S.of(context)!.swipeToAdjustVolume),
        ],
      ),
```

### 3. Modify Player Card onTap

**File:** `lib/widgets/player/player_reveal_overlay.dart` (around line 437-441 and 490-494)

```dart
// Current:
onTap: () {
  HapticFeedback.mediumImpact();
  maProvider.selectPlayer(data.player);
  dismiss();
},

// New:
onTap: () {
  HapticFeedback.mediumImpact();
  if (widget.onPlayerSelected != null) {
    // Execute the pending action with selected player
    widget.onPlayerSelected!(data.player);
  } else {
    // Default behavior: just select the player
    maProvider.selectPlayer(data.player);
  }
  dismiss();
},
```

### 4. Add Helper Method to GlobalPlayerOverlay

**File:** `lib/widgets/global_player_overlay.dart`

Add a static method to show player selector with pending action:

```dart
/// Show player selector for a "Play on" action
///
/// [contextHint] - Message shown instead of default hints
/// [onPlayerSelected] - Called when user taps a player
///
/// Example:
/// ```dart
/// GlobalPlayerOverlay.showPlayerSelectorForAction(
///   contextHint: "Select player to play album",
///   onPlayerSelected: (player) {
///     provider.playAlbum(albumId, playerId: player.playerId);
///   },
/// );
/// ```
static void showPlayerSelectorForAction({
  required String contextHint,
  required void Function(Player player) onPlayerSelected,
  IconData? hintIcon,
}) {
  // Implementation: trigger the player reveal overlay with these parameters
  // May need to store pending action in state and pass to overlay
}
```

### 5. Update Calling Sites

Replace `showPlayerPickerSheet()` calls with new method:

**Example - album_details_screen.dart:**

```dart
// Current (around line 1305-1316):
showPlayerPickerSheet(
  context: context,
  title: 'Play Album',
  onPlayerSelected: (player) async {
    GlobalPlayerOverlay.hidePlayer();
    await maProvider.playAlbum(albumId, playerId: player.playerId);
    GlobalPlayerOverlay.showPlayer();
  },
);

// New:
GlobalPlayerOverlay.showPlayerSelectorForAction(
  contextHint: S.of(context)!.selectPlayerToPlayAlbum, // Add localization
  onPlayerSelected: (player) async {
    await maProvider.playAlbum(albumId, playerId: player.playerId);
  },
);
```

### 6. Add Localizations

**File:** `lib/l10n/app_en.arb` (and other language files)

```json
"selectPlayerToPlay": "Select player to play",
"selectPlayerToPlayAlbum": "Select player to play album",
"selectPlayerToPlayPlaylist": "Select player to play playlist",
"selectPlayerToPlayRadio": "Select player to start radio",
"selectPlayerToPlayEpisode": "Select player to play episode",
"selectPlayerToPlayAudiobook": "Select player to play audiobook"
```

## Files to Modify

1. `lib/widgets/player/player_reveal_overlay.dart` - Add parameters, modify hints & onTap
2. `lib/widgets/global_player_overlay.dart` - Add helper method
3. `lib/screens/album_details_screen.dart` - Replace 3 popup calls
4. `lib/screens/playlist_details_screen.dart` - Replace 2 popup calls
5. `lib/screens/search_screen.dart` - Replace ~5 popup calls
6. `lib/screens/podcast_detail_screen.dart` - Replace 1 popup call
7. `lib/screens/audiobook_detail_screen.dart` - Replace 1 popup call
8. `lib/l10n/app_en.arb` - Add new strings
9. `lib/l10n/app_de.arb`, `app_fr.arb`, `app_es.arb` - Translations

## Exception: Queue Transfer

**Keep the popup for `queue_screen.dart`** because:
- Needs to filter out current player (can't transfer to self)
- Needs to filter out certain player types
- Different UX intent (transfer vs play)

## Implementation Order

1. Modify `PlayerRevealOverlay` to accept new parameters
2. Add helper method to `GlobalPlayerOverlay`
3. Test with one screen (album_details_screen.dart)
4. Add localizations
5. Migrate remaining screens
6. Clean up unused code from PlayerPickerSheet if no longer needed elsewhere

## Testing Checklist

- [ ] Album details: Play Album button
- [ ] Album details: Play From Here (track context menu)
- [ ] Album details: Play Radio (track context menu)
- [ ] Playlist details: Play Playlist button
- [ ] Playlist details: Play Radio (track context menu)
- [ ] Search: Play album from results
- [ ] Search: Play playlist from results
- [ ] Search: Play radio from results
- [ ] Podcast detail: Play episode
- [ ] Audiobook detail: Play audiobook
- [ ] Queue transfer still works with popup
- [ ] Long-press to sync still works in player selector
- [ ] Dismiss by tapping backdrop works
- [ ] Dismiss by swiping down works
