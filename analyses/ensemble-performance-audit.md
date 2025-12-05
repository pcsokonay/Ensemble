# Ensemble Performance Audit: Animation Smoothness Optimization

**Date**: 2025-12-05
**Target**: Achieve buttery-smooth animations comparable to Symphonium media player
**Branch**: performance/animation-smoothness
**Auditor**: Claude Code

---

## Executive Summary

This audit focuses specifically on Flutter performance optimizations to achieve 60fps+ animations and eliminate jank in the Ensemble music player app. The codebase has good foundational work (RepaintBoundary on cards, image caching, AutomaticKeepAliveClientMixin), but there are several opportunities for improvement to match the smoothness of premium music players like Symphonium.

### Performance Status

**Current State:**
- ✅ RepaintBoundary on AlbumCard and ArtistCard
- ✅ Image caching with cacheWidth/cacheHeight
- ✅ AutomaticKeepAliveClientMixin on row widgets
- ⚠️ Missing keys on list items
- ⚠️ Missing const constructors in many widgets
- ⚠️ ListView.builder without itemExtent where applicable
- ⚠️ setState calls could be more targeted
- ⚠️ No state restoration (scroll positions lost on navigation)
- ⚠️ Hero animations missing in Library screen

### Performance Impact Categories

| Category | Impact | Complexity | Priority |
|----------|--------|------------|----------|
| Quick Wins | High | Low | Critical |
| Widget Rebuilds | High | Medium | High |
| Animation Tuning | Medium | Low | High |
| List Performance | Medium | Low | Medium |
| State Restoration | Low | Medium | Low |

---

## Category 1: Quick Wins (Immediate Impact, Low Effort)

### QW-1: Add Missing `const` Constructors

**Issue**: Many stateless widgets lack const constructors, causing unnecessary rebuilds.

**Impact**: High - const widgets are cached by Flutter and reused, reducing rebuild overhead significantly.

**Locations**:
- `/home/home-server/Ensemble/lib/screens/library_artists_screen.dart:8` - LibraryArtistsScreen
- `/home/home-server/Ensemble/lib/screens/library_albums_screen.dart:7` - LibraryAlbumsScreen
- Various SizedBox, Padding, Icon widgets throughout

**Fix**:
```dart
// Before:
class LibraryArtistsScreen extends StatelessWidget {
  LibraryArtistsScreen({super.key});

// After:
class LibraryArtistsScreen extends StatelessWidget {
  const LibraryArtistsScreen({super.key});
```

**Estimated Savings**: 5-10% reduction in widget rebuilds

---

### QW-2: Add Keys to List Items

**Issue**: ListView.builder and GridView.builder items lack keys, causing Flutter to rebuild entire items instead of reusing them.

**Impact**: High - Without keys, Flutter can't track widgets during list updates, causing full rebuilds.

**Locations**:
- `/home/home-server/Ensemble/lib/screens/library_artists_screen.dart:88-95` - Artists list
- `/home/home-server/Ensemble/lib/screens/library_albums_screen.dart:87-103` - Albums grid
- `/home/home-server/Ensemble/lib/widgets/album_row.dart:89-104` - Album horizontal list
- `/home/home-server/Ensemble/lib/widgets/artist_row.dart:89-104` - Artist horizontal list

**Fix**:
```dart
// Before:
itemBuilder: (context, index) {
  final artist = provider.artists[index];
  return _buildArtistTile(context, artist, provider);
}

// After:
itemBuilder: (context, index) {
  final artist = provider.artists[index];
  return _buildArtistTile(
    context,
    artist,
    provider,
    key: ValueKey(artist.uri ?? artist.itemId),
  );
}
```

**Estimated Savings**: 15-25% reduction in list scroll jank

---

### QW-3: Add itemExtent to Horizontal Lists

**Issue**: Horizontal lists don't specify itemExtent, forcing Flutter to measure every item.

**Impact**: Medium - itemExtent allows Flutter to calculate layout without measuring, improving scroll performance.

**Locations**:
- `/home/home-server/Ensemble/lib/widgets/album_row.dart:89` - Fixed width of 150 + 12 margins = 162
- `/home/home-server/Ensemble/lib/widgets/artist_row.dart:89` - Fixed width of 120 + 16 margins = 136

**Fix**:
```dart
// Before:
ListView.builder(
  scrollDirection: Axis.horizontal,
  itemCount: albums.length,
  itemBuilder: ...

// After:
ListView.builder(
  scrollDirection: Axis.horizontal,
  itemCount: albums.length,
  itemExtent: 162, // Width + margins
  itemBuilder: ...
```

**Estimated Savings**: 10-15% improvement in horizontal scroll smoothness

---

### QW-4: Add RepaintBoundary to List Tiles

**Issue**: Artist list tiles in library screens lack RepaintBoundary, causing entire lists to repaint.

**Impact**: Medium - RepaintBoundary isolates repaints to individual tiles.

**Locations**:
- `/home/home-server/Ensemble/lib/screens/library_artists_screen.dart:99-134` - Artist tiles
- `/home/home-server/Ensemble/lib/screens/new_library_screen.dart` - Library artist tiles (around line 200)

**Fix**:
```dart
Widget _buildArtistTile(...) {
  return RepaintBoundary(
    child: ListTile(
      leading: CircleAvatar(...),
      title: Text(...),
      onTap: () {...},
    ),
  );
}
```

**Estimated Savings**: 5-10% reduction in repaint overhead

---

### QW-5: Fix Library Screen Hero Animations

**Issue**: Library screen artist tiles are missing Hero widgets, breaking animations to ArtistDetailsScreen.

**Impact**: High (UX) - Smooth hero animations are critical for premium feel.

**Location**: `/home/home-server/Ensemble/lib/screens/new_library_screen.dart` (around lines 200-235)

**Fix**: Wrap CircleAvatar and Text with Hero widgets matching ArtistDetailsScreen tags.

```dart
Widget _buildArtistTile(BuildContext context, Artist artist, MusicAssistantProvider provider) {
  final imageUrl = provider.getImageUrl(artist, size: 128);
  final suffix = '_library';

  return ListTile(
    leading: Hero(
      tag: HeroTags.artistImage + (artist.uri ?? artist.itemId) + suffix,
      child: CircleAvatar(
        radius: 24,
        backgroundImage: imageUrl != null ? NetworkImage(imageUrl) : null,
      ),
    ),
    title: Hero(
      tag: HeroTags.artistName + (artist.uri ?? artist.itemId) + suffix,
      child: Material(
        color: Colors.transparent,
        child: Text(artist.name),
      ),
    ),
    onTap: () {...},
  );
}
```

**Estimated Impact**: Eliminates jarring cross-fade, creates smooth morphing animation

---

## Category 2: Widget Rebuild Optimization

### WR-1: Replace context.watch() with context.select() in Lists

**Issue**: Using context.watch<MusicAssistantProvider>() causes entire screen rebuilds when any provider property changes.

**Impact**: High - Lists rebuild unnecessarily when unrelated state changes (e.g., playback state).

**Locations**:
- `/home/home-server/Ensemble/lib/screens/library_artists_screen.dart:13`
- `/home/home-server/Ensemble/lib/screens/library_albums_screen.dart:12`
- `/home/home-server/Ensemble/lib/screens/new_library_screen.dart:62`

**Fix**:
```dart
// Before:
final provider = context.watch<MusicAssistantProvider>();
// Rebuilds when currentTrack, isPlaying, volume, etc. change

// After:
final artists = context.select<MusicAssistantProvider, List<Artist>>(
  (p) => p.artists
);
final isLoading = context.select<MusicAssistantProvider, bool>(
  (p) => p.isLoading
);
// Only rebuilds when artists or isLoading change
```

**Estimated Savings**: 30-50% reduction in unnecessary rebuilds

---

### WR-2: Extract Static Widgets

**Issue**: Static decoration widgets are recreated on every build.

**Impact**: Medium - Flutter recreates identical widgets instead of reusing them.

**Locations**: Throughout screens (Icons, Padding, SizedBox, etc.)

**Fix**:
```dart
// Before:
Icon(Icons.person_rounded, size: 60, color: colorScheme.onSurfaceVariant)

// After:
static const _placeholderIcon = Icon(Icons.person_rounded, size: 60);
// Use colorScheme.onSurfaceVariant in IconTheme instead
```

**Estimated Savings**: 2-5% reduction in widget allocations

---

### WR-3: Add const to BoxDecoration and TextStyle

**Issue**: Decorations and styles are recreated on every build.

**Impact**: Low-Medium - Small per-widget overhead that adds up in lists.

**Fix**: Use const where colors are not dynamic, extract to constants file for reuse.

---

## Category 3: Animation Improvements

### AN-1: Optimize Hero Animation Curves

**Issue**: FadeSlidePageRoute uses generic easeOut/easeIn curves.

**Impact**: Medium - Better curves create more natural animations.

**Location**: `/home/home-server/Ensemble/lib/utils/page_transitions.dart`

**Recommendation**:
```dart
// Current:
curve: Curves.easeOut,
reverseCurve: Curves.easeIn,

// Better for hero animations:
curve: Curves.easeOutCubic,
reverseCurve: Curves.easeInCubic,

// Or match Material Design 3:
curve: Curves.easeInOutCubicEmphasized,
```

**Note**: ExpandablePlayer already uses easeOutCubic/easeInCubic (good!)

---

### AN-2: Reduce Overdraw with Transparent Backgrounds

**Issue**: Some widgets have unnecessary background colors causing overdraw.

**Impact**: Low - Minor GPU savings, more noticeable on older devices.

**Recommendation**: Audit Material widgets for unnecessary color properties.

---

### AN-3: Animation Disposal

**Issue**: Verify all AnimationController instances are disposed.

**Status**: ✅ Already handled correctly in ExpandablePlayer and GlobalPlayerOverlay

---

## Category 4: List Performance

### LP-1: Enable ListView.builder cacheExtent Tuning

**Issue**: Default cacheExtent may not be optimal for music library browsing.

**Impact**: Medium - Prebuilding items off-screen prevents scroll stutters.

**Recommendation**:
```dart
ListView.builder(
  cacheExtent: 500, // Prebuild ~500px off-screen
  itemCount: items.length,
  itemBuilder: ...
)
```

**Note**: Test on device to find optimal value (300-1000px typical range).

---

### LP-2: Lazy Load Images in Lists

**Issue**: NetworkImage starts loading immediately, even for off-screen items.

**Impact**: Low - Flutter already lazy-loads decoding, but could optimize further.

**Current State**: ✅ Already using cacheWidth/cacheHeight (good!)

**Optional Enhancement**: Use cached_network_image package for better caching.

---

### LP-3: GridView childAspectRatio Precision

**Issue**: GridView.builder uses childAspectRatio: 0.75, causing layout calculations.

**Impact**: Very Low - Already efficient, no changes needed.

**Status**: ✅ Current implementation is optimal

---

## Category 5: State Restoration

### SR-1: Preserve Scroll Positions

**Issue**: Scroll positions are lost when navigating away and back to library screens.

**Impact**: Medium (UX) - Users have to scroll back to where they were.

**Locations**:
- Library artists/albums/playlists tabs
- Home screen rows

**Fix**: Implement PageStorageKey for lists
```dart
ListView.builder(
  key: const PageStorageKey<String>('artists_list'),
  itemCount: items.length,
  itemBuilder: ...
)
```

---

### SR-2: Implement RestorationMixin for Tab State

**Issue**: NewLibraryScreen tab selection is lost on app restart.

**Impact**: Low (UX) - Minor annoyance, not performance-related.

**Recommendation**: Add RestorationMixin to NewLibraryScreen state.

---

## Performance Benchmarking Recommendations

### Metrics to Track

1. **Frame Rendering Time**: Should be <16ms (60fps) or <11ms (90fps on capable devices)
2. **Jank Count**: Number of frames >16ms (target: <5% of frames)
3. **Overdraw**: Use Flutter DevTools Performance Overlay
4. **Widget Rebuild Count**: Use performance overlay to track rebuilds
5. **Memory Usage**: Track during long scrolling sessions

### Testing Scenarios

1. **Scroll Performance Test**:
   - Library with 1000+ albums
   - Continuous fast scroll for 30 seconds
   - Measure frame drops and jank count

2. **Animation Smoothness Test**:
   - Navigate Album → Details → Back 20 times rapidly
   - Measure hero animation frame rate
   - Check for stutter or dropped frames

3. **Mini Player Expansion Test**:
   - Expand/collapse player 20 times
   - Measure animation consistency
   - Check for layout jank

4. **Concurrent Operations Test**:
   - Play music while scrolling library
   - Navigate between screens during playback
   - Ensure no frame drops during animations

### Tools

- Flutter DevTools Performance View
- Timeline profiler
- Performance overlay: `flutter run --profile`
- fps_monitor package for production monitoring

---

## Implementation Priority

### Phase 1: Quick Wins (1-2 hours)
Priority: **CRITICAL** - Highest impact/effort ratio

- [ ] QW-1: Add const constructors
- [ ] QW-2: Add keys to list items
- [ ] QW-3: Add itemExtent to horizontal lists
- [ ] QW-4: Add RepaintBoundary to list tiles
- [ ] QW-5: Fix Library hero animations

**Expected Impact**: 20-35% improvement in scroll smoothness, eliminate hero animation jank

---

### Phase 2: Widget Rebuilds (2-3 hours)
Priority: **HIGH** - Significant performance gains

- [ ] WR-1: Replace context.watch() with context.select()
- [ ] WR-2: Extract static widgets
- [ ] WR-3: Add const to decorations/styles

**Expected Impact**: 25-40% reduction in unnecessary rebuilds

---

### Phase 3: Animation Tuning (30 min)
Priority: **HIGH** - Polish that users notice

- [ ] AN-1: Optimize curve selection
- [ ] AN-2: Reduce overdraw

**Expected Impact**: Subtle but noticeable smoothness improvement

---

### Phase 4: List Optimization (1 hour)
Priority: **MEDIUM** - Performance headroom for large libraries

- [ ] LP-1: Add cacheExtent tuning
- [ ] LP-2: Verify image lazy loading (already good)

**Expected Impact**: 10-15% improvement in large list scroll performance

---

### Phase 5: State Restoration (1-2 hours)
Priority: **LOW** - UX polish, not performance

- [ ] SR-1: Add PageStorageKey to lists
- [ ] SR-2: Implement RestorationMixin for tabs

**Expected Impact**: Better UX, maintains user context

---

## Files to Modify

### High Priority (Phase 1-2)
1. `/home/home-server/Ensemble/lib/screens/library_artists_screen.dart`
2. `/home/home-server/Ensemble/lib/screens/library_albums_screen.dart`
3. `/home/home-server/Ensemble/lib/screens/new_library_screen.dart`
4. `/home/home-server/Ensemble/lib/widgets/album_row.dart`
5. `/home/home-server/Ensemble/lib/widgets/artist_row.dart`

### Medium Priority (Phase 3-4)
6. `/home/home-server/Ensemble/lib/utils/page_transitions.dart`
7. `/home/home-server/Ensemble/lib/widgets/album_card.dart` (verify, already good)
8. `/home/home-server/Ensemble/lib/widgets/artist_card.dart` (verify, already good)

### Low Priority (Phase 5)
9. State restoration utilities (may need new file)

---

## Success Criteria

### Performance Targets
- [ ] 95%+ of frames render in <16ms (60fps)
- [ ] <5% jank rate during scroll/animations
- [ ] Hero animations consistently smooth (no visible stutter)
- [ ] Mini player expansion/collapse at 60fps
- [ ] Library scroll maintains 60fps with 1000+ items

### Code Quality
- [ ] flutter analyze: 0 errors, 0 warnings
- [ ] No performance-related lint warnings
- [ ] All AnimationControllers properly disposed
- [ ] Consistent use of const constructors

### User Experience
- [ ] Animations feel comparable to Symphonium
- [ ] No visible lag during navigation
- [ ] Scroll positions preserved (Phase 5)
- [ ] Smooth transitions throughout app

---

## Notes

**What's Already Good:**
- RepaintBoundary on cards ✅
- Image caching with dimensions ✅
- AutomaticKeepAliveClientMixin on rows ✅
- Proper animation controller disposal ✅
- Good use of CurvedAnimation ✅

**Biggest Opportunities:**
1. Adding keys to list items (huge impact, easy fix)
2. Replacing context.watch() with context.select() (massive rebuild reduction)
3. Adding const constructors (free performance)
4. Fixing hero animations (UX polish)

**Reference Implementation:**
The ExpandablePlayer and card widgets are well-optimized examples. Use them as templates for other widgets.

---

## Appendix: Flutter Performance Best Practices Applied

### ✅ Already Implemented
- RepaintBoundary for expensive widgets
- const constructors where appropriate
- AutomaticKeepAliveClientMixin for stateful widgets
- Image caching with explicit dimensions
- CurvedAnimation for smooth curves
- Proper animation controller management
- SingleTickerProviderStateMixin where needed

### ⚠️ Partially Implemented
- Keys on list items (missing in several places)
- const constructors (many widgets still mutable)
- Targeted rebuilds (some broad context.watch() usage)

### ❌ Not Yet Implemented
- PageStorageKey for scroll restoration
- itemExtent for fixed-size lists
- cacheExtent tuning
- Comprehensive use of context.select()

---

**End of Audit**

**Next Steps**: Implement Phase 1 (Quick Wins) on `performance/animation-smoothness` branch and measure impact before proceeding to Phase 2.
