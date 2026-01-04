# Ensemble Flutter App - Code Audit Report

**Date:** January 4, 2026
**Branch:** `audit/code-quality-review`
**Files Audited:** 93 Dart files

---

## Executive Summary

The codebase is generally well-maintained with good existing performance optimizations (RepaintBoundary, ListView.builder, cacheExtent settings). Key improvement areas identified:

| Category | Issues Found | Priority |
|----------|-------------|----------|
| Deprecated APIs | 20 instances | HIGH |
| Missing const constructors | 100+ instances | MEDIUM |
| Image cache parameters | 7 locations | MEDIUM |
| Code duplication | 8 view mode functions | LOW |
| Color constants | 3 files with duplicates | LOW |

---

## 1. CRITICAL: Deprecated API Usage

### `colorScheme.background` (20 instances)
Flutter Material 3 deprecates `ColorScheme.background`. Replace with `colorScheme.surface`.

**Files affected:**
- lib/main.dart:335, 336
- lib/screens/library_artists_screen.dart:21
- lib/screens/new_home_screen.dart:121
- lib/screens/artist_details_screen.dart:708, 720
- lib/screens/library_playlists_screen.dart:53
- lib/screens/library_tracks_screen.dart:19
- lib/screens/login_screen.dart:489
- lib/screens/new_library_screen.dart:933, 957, 1020, 1021
- lib/screens/album_details_screen.dart:807, 819
- lib/screens/library_albums_screen.dart:19
- lib/screens/search_screen.dart:427, 738, 739
- lib/screens/settings_screen.dart:245

---

## 2. HIGH: Missing const Constructors

### EdgeInsets.zero (64 instances)
High-impact optimization - used extensively in button padding.

**Key files:**
- lib/screens/album_details_screen.dart (12 instances)
- lib/screens/artist_details_screen.dart (8 instances)
- lib/screens/audiobook_detail_screen.dart (3 instances)
- lib/screens/audiobook_series_screen.dart (2 instances)
- lib/screens/audiobook_author_screen.dart (2 instances)

### BorderRadius.circular (40+ instances)
Cannot use `const BorderRadius.circular()` directly. Alternative: `const BorderRadius.all(Radius.circular(X))`.

---

## 3. MEDIUM: Scroll Performance - Missing Image Cache Parameters

### CachedNetworkImage without memCacheWidth/Height

**lib/screens/new_library_screen.dart:**
- Line 1395-1402: Author image (48x48) - missing cache params
- Line 1480-1486: Author card image - missing cache params
- Line 1572-1580: Audiobook cover (56x56) - missing cache params
- Line 1740-1745: Audiobook grid cover - missing cache params
- Line 1959-1969: Playlist cover (56x56) - missing cache params
- Line 2143-2152: Playlist grid covers - missing cache params
- Line 2973-2981: Album cover (56x56) - missing cache params

**Note:** DecorationImage with CachedNetworkImageProvider cannot have cache size specified (structural Flutter limitation).

---

## 4. LOW: Code Duplication

### View Mode Cycling Functions (8 nearly identical functions)
**File:** lib/screens/new_library_screen.dart

Functions that follow identical switch/case pattern:
- `_cycleArtistsViewMode()` (line 184)
- `_cycleAlbumsViewMode()` (line 200)
- `_cyclePlaylistsViewMode()` (line 216)
- `_cycleAuthorsViewMode()` (line 232)
- `_cycleAudiobooksViewMode()` (line 248)
- `_cycleSeriesViewMode()` (line 286)
- `_cycleRadioViewMode()` (line 303)
- `_cyclePodcastsViewMode()` (line 319)

**Recommendation:** Create generic utility function.

### Duplicated Color Constants (3 files)
Series fallback colors defined identically in:
- lib/widgets/series_row.dart:246-253
- lib/screens/audiobook_series_screen.dart:466-473
- lib/screens/new_library_screen.dart:2112-2119

**Recommendation:** Extract to lib/constants/colors.dart

---

## 5. POSITIVE FINDINGS (Already Optimized)

- **RepaintBoundary**: Properly implemented in all list item widgets
- **ListView.builder**: Used consistently with cacheExtent: 1000
- **ScrollController disposal**: All 8+ controllers properly disposed
- **Animation patterns**: Proper listener cleanup in expandable_player.dart
- **Debounced operations**: Color extraction debounced to 300ms

---

## Recommended Action Plan

### Phase 1: Quick Wins (Low Risk)
1. Replace `colorScheme.background` with `colorScheme.surface` (20 locations)
2. Add `const` to EdgeInsets.zero instances

### Phase 2: Image Optimization
1. Add memCacheWidth/memCacheHeight to CachedNetworkImage instances in new_library_screen.dart

### Phase 3: Code Cleanup (Optional)
1. Extract view mode cycling to utility function
2. Centralize color constants

---

## Files by Complexity

| File | Lines | Status |
|------|-------|--------|
| lib/screens/search_screen.dart | 3,489 | Good structure, minor fixes needed |
| lib/screens/new_library_screen.dart | 3,351 | Good performance, some duplication |
| lib/widgets/expandable_player.dart | 2,577 | Well-optimized animations |
