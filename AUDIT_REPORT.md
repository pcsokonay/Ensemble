# Ensemble Codebase Audit Report

**Date**: 2026-01-14
**Scope**: Full codebase audit (104 Dart files, 18 screens)
**Focus Areas**: UI Continuity, Performance, Logic/Best Practices

---

## Executive Summary

The Ensemble codebase is a **mature, feature-rich Flutter application** with many good patterns already in place. However, the audit identified **significant architectural debt** that should be addressed:

| Severity | Count | Key Themes |
|----------|-------|------------|
| **Critical** | 6 | God classes (5,443 & 4,209 lines), design token adoption, startup blocking |
| **High** | 15 | Touch targets, batch DB operations, over-notification, code duplication |
| **Medium** | 25+ | Inconsistencies, memory issues, missing error boundaries |
| **Low** | 15+ | Minor polish items |

**Top 3 Priorities:**
1. **Split `MusicAssistantProvider` (5,443 lines)** - God object handling everything
2. **Split `new_library_screen.dart` (4,209 lines)** - 10 scroll controllers, 15+ view modes
3. **Fix startup performance** - Sequential blocking ops could save 1-8 seconds

---

## Critical Issues

### 1. God Object: MusicAssistantProvider (5,443 lines)
**File**: `lib/providers/music_assistant_provider.dart`
- 54 `notifyListeners()` calls
- 30+ state variables
- 100+ public methods
- Handles: connection, auth, players, library, search, caching, local playback, Sendspin
- **Fix**: Split into ConnectionManager, PlayerStateManager, LibraryStateManager, SearchStateManager

### 2. God Object: NewLibraryScreen (4,209 lines)
**File**: `lib/screens/new_library_screen.dart`
- 10 scroll controllers
- 15+ view mode states
- 15+ sort order states
- Handles: Music, Books, Podcasts, Radio tabs
- **Fix**: Extract to ArtistsTab, AlbumsTab, TracksTab, PlaylistsTab, BooksTab, PodcastsTab, RadioTab

### 3. Sequential Blocking Startup (500-1500ms wasted)
**File**: `lib/main.dart:33-66`
```dart
await DatabaseService.instance.initialize();
await ProfileService.instance.migrateFromOwnerName();
await SettingsService.migrateToSecureStorage();
await SyncService.instance.loadFromCache();
audioHandler = await AudioService.init(...);
```
- **Fix**: Parallelize with `Future.wait()`, defer AudioService to post-first-frame

### 4. Design Tokens Exist But Unused
**File**: `lib/theme/design_tokens.dart`
- `Spacing.*` used in only ~6 of 34+ widget files
- `Radii.*` used in only ~5 files
- `IconSizes.*` used in only ~4 files
- **Fix**: Systematic replacement of hardcoded values

### 5. Touch Targets Too Small (32x32)
**File**: `lib/screens/new_library_screen.dart:1805-1867`
- Sort, favorites, view mode buttons are 32x32
- Material Design minimum: 48x48
- **Fix**: Increase to 48x48 or add padding for hit area

### 6. No Batch Database Inserts
**File**: `lib/services/sync_service.dart:212-273`
- 1000 albums = 1000 separate DB transactions
- **Fix**: Wrap in single transaction or use Drift batch insert

---

## High Severity Issues

### Performance
| Issue | File | Impact |
|-------|------|--------|
| `context.watch()` in nested tabs | new_library_screen.dart:2960 | All tabs rebuild on any provider change |
| Consumer wrapping 800-line player | expandable_player.dart:1234 | Full rebuild on every state change |
| Inline sorting during build | new_library_screen.dart:3647 | 5-20ms for 1000+ albums |
| Multiple setState for author images | new_library_screen.dart:1017 | 20+ rebuilds as images load |
| SecureStorage migration every startup | secure_storage_service.dart:103 | 100-300ms wasted |

### Architecture
| Issue | File | Impact |
|-------|------|--------|
| State duplication across 4 providers | providers/*.dart | Maintenance burden, sync issues |
| 8 duplicate `_cycle*ViewMode()` methods | new_library_screen.dart:251-402 | DRY violation |
| 60+ duplicate getter/setter pairs | settings_service.dart:500-1000 | Code bloat |
| Global singleton NavigationProvider | navigation_provider.dart:40 | Untestable |
| CacheService duplicated in providers | Multiple | Memory waste, inconsistency |

### UI/UX
| Issue | File | Impact |
|-------|------|--------|
| Hardcoded bottom spacing (140, 164, 100) | Multiple detail screens | Content obscured by player |
| Inconsistent button sizes (44 vs 50) | Multiple screens | Visual disharmony |
| No debounce on card taps | album_card.dart:118 | Double navigation possible |
| Missing PopScope on AudiobookSeriesScreen | audiobook_series_screen.dart:276 | Adaptive colors not cleared |

### Error Handling
| Issue | File | Impact |
|-------|------|--------|
| No Flutter error boundaries | main.dart | Red error screen on build failure |
| API returns empty list on error | music_assistant_api.dart | Can't distinguish error from empty |

---

## Medium Severity Issues

### Performance
- PaletteGenerator on main isolate (10-30ms blocking)
- Multiple `SharedPreferences.getInstance()` calls (132 occurrences)
- AppStartup polling loop with fixed 250ms delay
- SystemThemeHelper FutureBuilder recreated on every build

### UI Consistency
- Border radius varies: 8, 12, 20, 22, 25 for same element types
- `SizedBox(height: 8)` appears 40+ times instead of `Spacing.vGap8`
- Hardcoded colors for status (Colors.red, Colors.green)
- Inconsistent icon sizes across screens

### State Management
- Over-notification (multiple notifyListeners in single methods)
- Wide Consumer scope (watch instead of select)
- Missing dispose() in some providers
- Inconsistent async state handling (loading/error)

### Navigation
- `isQueuePanelOpen` vs `isQueuePanelTargetOpen` inconsistency
- `popToHome()` doesn't clear adaptive colors
- Infinite navigation loop possible (Album → Artist → Album)
- Orphaned Hero animations in podcast_card, radio_station_card

### Data/Caching
- Unbounded `_podcastCoverCache`
- SyncService listener not removed on error
- Redundant API calls between providers
- Fire-and-forget persistence race condition

### Error Handling
- No zone error handler for async exceptions
- `retryCritical()` retries all errors including non-recoverable
- No user notification of offline queue status
- DisconnectedState not used consistently

---

## Quick Wins (High Impact, Low Effort)

| # | Task | File(s) | Effort |
|---|------|---------|--------|
| 1 | Replace hardcoded bottom spacing with `BottomSpacing.withMiniPlayer` | Detail screens | 30 min |
| 2 | Add navigation debounce to card widgets | album_card, artist_card, etc. | 1 hr |
| 3 | Fix touch targets to 48x48 minimum | new_library_screen.dart | 15 min |
| 4 | Add migration skip flag for SecureStorage | secure_storage_service.dart | 30 min |
| 5 | Add Flutter error boundary | main.dart | 30 min |
| 6 | Use `context.select()` instead of `context.watch()` | global_player_overlay, etc. | 2 hr |
| 7 | Cache `SharedPreferences.getInstance()` | settings_service.dart | 30 min |

---

## Refactoring Roadmap

### Phase 1: Quick Wins (1-2 days)
- Fix touch targets
- Fix bottom spacing
- Add navigation debounce
- Add error boundaries
- Cache SharedPreferences singleton

### Phase 2: Performance (3-5 days)
- Parallelize startup operations
- Replace `context.watch()` with `context.select()`
- Batch database inserts
- Add SecureStorage migration skip flag
- Fix over-notification in provider

### Phase 3: Design System (1 week)
- Systematic design token adoption
- Standardize button sizes (44 vs 50)
- Standardize border radius values
- Create StatusColors semantic tokens
- Replace all magic numbers

### Phase 4: Architecture (2-3 weeks)
- ~~Split MusicAssistantProvider into focused managers~~ **DEFERRED** - MusicAssistantProvider has evolved with Sendspin, Cast-Sendspin ID mapping, position tracker integration. Splitting would require ~1600 lines of sync work. Code is working and tested.
- ~~Split new_library_screen into tab widgets~~ **DEFERRED** - Tabs have tight state coupling (15+ view modes, 15+ sort orders, 10 scroll controllers). Extraction would require InheritedWidget/callbacks for all shared state. Risk outweighs benefit.
- ✅ Extract generic helpers for SettingsService - Reduced from 1,031 to 874 lines (~15%)
- ✅ Remove/integrate unused providers - Deleted PlayerProvider (964 lines), LibraryProvider, ConnectionProvider (651 lines total)
- ~~Split music_assistant_api.dart by domain~~ **DEFERRED** - All methods share WebSocket connection and auth state. Clean extraction would require connection manager abstraction.

---

## Positive Findings

The codebase already demonstrates many good practices:

- **Performance awareness**: `// PERF:` comments, RepaintBoundary (55 occurrences), image caching (80 memCacheWidth/Height)
- **Caching**: Multi-tier caching with LRU eviction, proper TTLs, proper DB indexes
- **Error handling**: DebugLogger, RetryHelper, OfflineActionQueue well-implemented
- **Theme system**: Material You support, adaptive colors from album art
- **Offline support**: Cache-first loading, graceful degradation
- **Navigation**: Consistent FadeSlidePageRoute, proper Hero animations (mostly)

---

## Files by Priority

| Priority | File | Lines | Key Issues |
|----------|------|-------|------------|
| 1 | music_assistant_provider.dart | 5,443 | God object, over-notification |
| 2 | new_library_screen.dart | 4,209 | God class, performance, touch targets |
| 3 | main.dart | 549 | Startup blocking, error boundaries |
| 4 | music_assistant_api.dart | 3,434 | Silent failures, needs splitting |
| 5 | settings_service.dart | 1,019 | Code duplication, no caching |
| 6 | expandable_player.dart | ~800 | Wide Consumer scope |
| 7 | global_player_overlay.dart | ~500 | BottomSpacing source, Consumer scope |
| 8 | All detail screens | Various | Hardcoded bottom spacing |
| 9 | All card widgets | Various | Navigation debounce, design tokens |

---

## Audit Methodology

This audit was conducted using 9 parallel sub-agents analyzing:

**UI Continuity (3 agents)**
1. Navigation & Flow - back button, Hero animations, tab preservation
2. Visual Consistency - design tokens, spacing, typography
3. Component Placement - touch targets, bottom spacing, modals

**Performance (3 agents)**
4. Rendering Performance - ListView.builder, const, rebuilds
5. Data & Caching - streams, invalidation, memory bounds
6. Startup & Load Time - blocking operations, initialization order

**Logic/Best Practices (3 agents)**
7. State Management - Provider patterns, notification frequency
8. Error Handling - try-catch, boundaries, resilience
9. Code Quality - file size, duplication, SOLID principles

---

## Conclusion

The Ensemble app is well-architected at the macro level but has accumulated technical debt in its largest files. The most impactful improvements would be:

1. **Splitting the two 4,000+ line files** into focused components
2. **Adopting design tokens systematically** for visual consistency
3. **Optimizing startup sequence** for faster app launch
4. **Using granular state management** (select vs watch) for better performance

The quick wins section provides immediate value with minimal risk, while the roadmap offers a path to sustainable improvement.
