# Discovery Rows Submenu - Implementation Plan

## Option: Hybrid with Discovery Badge

### Overview
Transform the "Discovery Mixes" toggle into a section that:
1. Shows individual discovery row toggles
2. Adds those rows to the main home row list with visual distinction
3. Allows full reordering alongside other rows

---

## UI Design

### Settings Screen - Discovery Section

```
┌─────────────────────────────────────────────┐
│ ⚬ Discovery Mixes                        ● │
│   Show discovery-based rows on home screen │
│   ──────────────────────────────────────── │
│   Discovery rows from Music Assistant:     │
│                                            │
│   ☑ New Releases                        ● │
│   ☑ Recently Played                     ● │
│   ☐ Recommended Albums                  ○ │
│   ☐ For You                             ○ │
│                                            │
│   [Refresh available rows]                │
└─────────────────────────────────────────────┘
```

### Main Home Row List - With Badge

Discovery rows appear interleaved with a badge:

```
┌─────────────────────────────────────────────┐
│ ⋮ ☑ Recent Albums                        ● │
│ ⋮ ☑ Discovery: New Releases    ●  [MUSIC] │ ← Badge
│ ⋮ ☑ Discover Artists                     ● │
│ ⋮ ☐ Discovery: For You           ○  [MUSIC] │
│ ⋮ ☑ Favorite Albums                      ● │
└─────────────────────────────────────────────┘
```

Badge style: Small chip/icon indicating this is a dynamic discovery row.

---

## Technical Changes

### 1. Settings Screen (`lib/screens/settings_screen.dart`)

**Add state for discovery folders:**
```dart
List<RecommendationFolder> _discoveryFolders = [];
Map<String, bool> _discoveryRowEnabled = {}; // itemId -> enabled
bool _isDiscoveryFoldersExpanded = false;
```

**New methods:**
```dart
Future<void> _loadDiscoveryFolders() async { }
Future<void> _refreshDiscoveryFolders() async { }
void _toggleDiscoveryRow(String itemId, bool enabled) { }
void _toggleDiscoveryMixes(bool enabled) { }
Widget _buildDiscoverySection() { }
```

**Modify existing:**
- `_loadSettings()` - load discovery row preferences
- Home row list builder - filter out individual discovery rows
- Add discovery section before home row list

### 2. Settings Service (`lib/services/settings_service.dart`)

**New methods:**
```dart
static Future<bool> getShowDiscoveryFolders() async { }
static Future<void> setShowDiscoveryFolders(bool value) async { }

// Per-row discovery preferences
static Future<Map<String, bool>> getDiscoveryRowPreferences() async { }
static Future<void> setDiscoveryRowPreference(String itemId, bool enabled) async { }
static Future<void> setDiscoveryRowPreferences(Map<String, bool> prefs) async { }
```

**Storage key pattern:**
- `discovery_folders_enabled` (bool)
- `discovery_row_{itemId}` (bool per row)

### 3. Provider (`lib/providers/music_assistant_provider.dart`)

**Already has:** `getDiscoveryFoldersWithCache()`

**Add method:**
```dart
Future<void> refreshDiscoveryFolders() async {
  // Clear cache and refetch from API
  _cacheService.clearDiscoveryFoldersCache();
  await getDiscoveryFoldersWithCache();
}
```

### 4. Home Screen (`lib/screens/new_home_screen.dart`)

**Changes to row rendering:**

Instead of a single `_discoveryFolders` list, discovery rows are integrated into `_homeRowOrder`:

```dart
// Before: static list of row IDs
List<String> _homeRowOrder = ['recent-albums', 'discover-artists', ...];

// After: can include discovery row IDs
List<String> _homeRowOrder = [
  'recent-albums',
  'discovery:abc123',  // Discovery row ID
  'discover-artists',
  'discovery:def456',
  ...
];
```

**New method:**
```dart
bool _isDiscoveryRowId(String rowId) {
  return rowId.startsWith('discovery:');
}

String _getDiscoveryRowItemId(String rowId) {
  return rowId.substring('discovery:'.length);
}
```

**Modify row rendering:**
- Check if rowId is a discovery row
- If yes, render DiscoveryRow widget with that folder
- Cache discovery folders for quick lookup

### 5. Localization (`lib/l10n/app_en.arb`)

**Add strings:**
```json
{
  "discoveryMixesDescription": "Show personalized recommendations from Music Assistant",
  "discoveryRows": "Discovery rows from Music Assistant",
  "refreshDiscoveryRows": "Refresh available rows",
  "noDiscoveryRows": "No discovery rows available",
  "discoveryRowBadge": "Music Assistant"
}
```

### 6. Models (`lib/models/recommendation_folder.dart`)

**Add property:**
```dart
class RecommendationFolder {
  ...
  /// Unique ID for use in row ordering and settings
  String get rowId => 'discovery:$itemId';
}
```

---

## Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                          Settings Screen                        │
├─────────────────────────────────────────────────────────────────┤
│  1. Load discovery folders from Provider                        │
│  2. Load per-row enabled state from Settings                    │
│  3. Render section with toggles                                 │
│  4. User toggles row → save to Settings                         │
│  5. User toggles main → save to Settings + update home row list │
│  6. User refreshes → Provider.fetch → update UI                 │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                        Home Screen                              │
├─────────────────────────────────────────────────────────────────┤
│  1. Load home row order from Settings                           │
│  2. Identify discovery row IDs (prefix "discovery:")             │
│  3. For discovery rows: look up folder from Provider cache      │
│  4. Render appropriate widget (DiscoveryRow or other)           │
│  5. Handle reordering including discovery rows                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Migration Path

### Phase 1: Settings Screen (No breaking changes)
- Add discovery section to settings
- Load and display discovery folders
- Individual row toggles (but don't affect home screen yet)
- Refresh button

### Phase 2: Home Screen Integration
- Modify home row order to support discovery row IDs
- Render discovery rows in main list
- Add badge visual distinction

### Phase 3: Polish
- Translations
- Edge cases (folder disappears from MA)
- Performance (lazy loading)

---

## Edge Cases & Considerations

| Issue | Solution |
|-------|----------|
| Discovery folder no longer returned by MA | Keep user preference, hide row if not found |
| User reorders then MA returns new folders | New folders appended to end of discovery section |
| All discovery rows disabled | Discovery section shows but appears empty/minimized |
| Many discovery folders (10+) | Show scrollable sublist, keep main setting compact |
| Row ID collision | Use `discovery:{itemId}` prefix ensures uniqueness |

---

## Implementation Checklist

- [ ] Settings: Add `_discoveryFolders` state
- [ ] Settings: Add `_discoveryRowEnabled` map
- [ ] Settings: Implement `_loadDiscoveryFolders()`
- [ ] Settings: Implement `_buildDiscoverySection()`
- [ ] Settings: Add refresh button handler
- [ ] SettingsService: Add discovery row preference methods
- [ ] Provider: Add `refreshDiscoveryFolders()`
- [ ] HomeScreen: Support discovery row IDs in order list
- [ ] HomeScreen: Render discovery rows with badge
- [ ] Localization: Add new strings
- [ ] Test: Toggle discovery rows on/off
- [ ] Test: Reorder discovery rows
- [ ] Test: Refresh discovery folders
- [ ] Test: Migrate existing preference to new system
