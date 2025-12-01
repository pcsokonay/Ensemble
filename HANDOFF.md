# CONTEXT HANDOFF: Ensemble - Local Player Isolation Fix

## Current State

- **Branch:** `feature/fix-local-player-isolation`
- **Last build:** TBD (needs to be triggered)
- **Previous branch:** `feature/audio-service-migration` (contains audio_service migration work)

## CRITICAL BUG FIXED: Local Player Isolation

### The Problem
When the app was installed on multiple phones (e.g., Chris's phone and wife's phone), playing music on one device triggered playback on BOTH devices simultaneously. This was a critical bug caused by both devices sharing the same `player_id` with the Music Assistant server.

### Root Cause
The `DeviceIdService` generated player IDs by hashing hardware characteristics (`androidInfo.fingerprint`, `hardware`, `device`, `model`, `brand`). These values are **identical for devices of the same model** (e.g., two Pixel 8 phones), causing both phones to hash to the same player ID.

### The Fix (Based on KMP Client Pattern)

#### 1. UUID-Based Device ID Generation
**File:** `lib/services/device_id_service.dart`
- Replaced hardware-based ID generation with random UUID generation
- ID is generated ONCE per installation and persisted in SharedPreferences
- Format changed: `massiv_<hash>` → `ensemble_<uuid>`
- Key used: `local_player_id` (new), migrates from legacy `device_player_id` and `builtin_player_id`
- Migration: Detects legacy IDs and generates new UUID without attempting server cleanup

#### 2. Owner Name System
**File:** `lib/services/settings_service.dart`
- Added `_keyOwnerName` constant for storing user's name
- Added `getOwnerName()` and `setOwnerName(String)` methods
- Updated `getLocalPlayerName()` to derive name from owner name
- Added `_makePlayerName(String)` helper for proper possessive apostrophe handling:
  - "Chris" → "Chris' Phone" (ends with 's')
  - "Mom" → "Mom's Phone" (doesn't end with 's')

#### 3. Login Screen "Your Name" Field
**File:** `lib/screens/login_screen.dart`
- Added `_ownerNameController` text field controller
- Added "Your Name" field after server URL, before port
- Placeholder: "e.g., Chris, Mom, Dad"
- Validation: Required, non-empty
- Saves to `SettingsService.setOwnerName()` on successful connection
- Loads saved owner name on screen init

#### 4. Removed Local Player Settings Section
**File:** `lib/screens/settings_screen.dart`
- Removed `_localPlayerNameController` (no longer needed)
- Removed entire "Local Player" section (device name customization, enable/disable toggle)
- Moved "Ghost Players" purge button to appear after Disconnect button
- Local playback is now always enabled when connected

### Migration Strategy
- Existing installations with legacy hardware-based IDs will automatically migrate on next app start
- New UUID is generated and stored in `local_player_id`
- Legacy keys (`device_player_id`, `builtin_player_id`) are detected but not deleted
- No attempt to clean up old player from server (user can use "Purge Unavailable Players")
- Owner name defaults to empty; user will be prompted on next login

## Previous Work (audio_service Migration)

### Background playback with audio_service:
   - Replaced `just_audio_background` with `audio_service: ^0.18.12` and `rxdart: ^0.27.7`
   - Custom AudioHandler at `lib/services/audio/massiv_audio_handler.dart`
   - Notification buttons: Skip Prev, Play/Pause, Skip Next
   - Fixed white square stop button issue

### Ensemble Rebranding:
   - Grey logo at `assets/images/ensemble_logo.png`
   - Updated app name in all manifests and config files
   - Default player name: "Ensemble"
   - Notification channel: "Ensemble Audio"

## Key Files Changed (This Fix)

- `lib/services/device_id_service.dart` - **REWRITTEN** to use UUID instead of hardware hash
- `lib/services/settings_service.dart` - Added owner name storage and player name derivation
- `lib/screens/login_screen.dart` - Added "Your Name" field, validates owner name
- `lib/screens/settings_screen.dart` - Removed "Local Player" customization section

## What Needs Testing (Current Build)

### Critical Test - Player Isolation
1. Install app on two devices of the same model (e.g., two Pixel 8 phones)
2. Login with different owner names (e.g., "Chris" and "Sarah")
3. Verify each device gets unique player ID starting with `ensemble_`
4. Verify player names show as "Chris' Phone" and "Sarah's Phone"
5. Play music on one device - verify other device does NOT start playing
6. Check Music Assistant server shows TWO distinct players

### Owner Name Field
1. Login screen shows "Your Name" field after server URL, before port
2. Field is required - shows error if empty
3. Owner name is saved and persists across app restarts
4. Player name correctly handles possessive apostrophes

### Settings Screen
1. "Local Player" section is removed
2. "Ghost Players" button still appears when connected
3. No device name customization or local playback toggle

### Migration from Legacy
1. Existing installations detect legacy hardware-based ID
2. New UUID is generated automatically
3. Old player appears as "unavailable" in Music Assistant
4. User can purge unavailable players manually

## Outstanding Issues / Next Features

### 1. Remote Player Notification (HIGH PRIORITY)
**Problem:** Notification ONLY shows when playing locally on the phone. When controlling a remote player (e.g., Dining Room), there's NO notification at all.

**Why:** `audio_service` creates notifications for local audio playback only. When a remote player is active, the phone is just a remote control with no local audio.

**Solution needed:**
- Create a "remote control" notification using a foreground service
- Show notification for ALL playback (local or remote)
- Skip/play/pause buttons control the selected player
- Could add player switcher button to notification
- This is how the official KMP client works

### 2. Player Switcher in Notification (AFTER #1)
Once remote notifications work, add a speaker icon button that opens player selection.

### 3. App Icon
- Currently using old Massiv icon (`massiv_icon.png`)
- User doesn't have new Ensemble icon yet
- Keep current icon for now, notification uses music note

## MusicAssistantProvider Context

The provider at `lib/providers/music_assistant_provider.dart` handles:
- `_pendingTrackMetadata` - metadata captured from player_updated events
- `_currentNotificationMetadata` - what's actually showing in notification
- `_handlePlayerUpdatedEvent()` - captures metadata, detects stale notification
- `_handleLocalPlayerEvent()` - handles play_media, stop, etc from server
- Race condition on local IP: play_media arrives before player_updated with correct metadata

## KMP Client Reference

Looked at https://github.com/music-assistant/kmp-client-app for patterns:
- They use MediaSession directly (Kotlin)
- No stop button in their notification
- Have player switch button
- `MediaNotificationManager.kt` and `MediaSessionHelper.kt` are good references
- They show notification for ANY active player, not just local

## Commands

```bash
# Check build status
gh run list --workflow="Build Android APK" --limit 2

# Watch build
gh run watch <run_id>

# Trigger new build
gh workflow run "Build Android APK" --ref feature/fix-local-player-isolation
```

## Debug Logging Added

Player list debugging in `_loadAndSelectPlayers()`:
```
🎛️ getPlayers returned X players:
   - PlayerName (playerId) available=true/false powered=true/false
🎛️ After filtering: X players available
```
