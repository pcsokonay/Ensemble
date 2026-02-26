# Android Auto Implementation Plan for Ensemble

## 1. Overview

This document describes adding Android Auto support to Ensemble. When a user connects their Android phone to a car head unit, Android Auto will browse and play music through Ensemble without touching the phone.

### What we're building

- A browse hierarchy (Favorites, Playlists, Albums, Radio) accessible from the car screen
- Playback from Android Auto routes through the builtin (local) player, which streams through MA as normal
- Voice search support

### Why builtin player only

Android Auto requires local audio output. The builtin player plays audio through `just_audio` on the device, which the car receives over Bluetooth. Remote MA players are irrelevant in a car context.

---

## 2. Architecture

### Provider reference

`MassivAudioHandler` has no reference to `MusicAssistantProvider` today. The handler is created before the provider (in `main()` before `runApp`). Solution: add a `setProvider()` method and call it from `_MusicAssistantAppState.initState()`.

```
main.dart
  audioHandler = await AudioService.init(...)   // global, created first
  runApp(MusicAssistantApp())
    _MusicAssistantAppState.initState()
      _musicProvider = MusicAssistantProvider()
      audioHandler.setProvider(_musicProvider)  // NEW
```

### Browse → play call flow

```
Android Auto          MassivAudioHandler              MusicAssistantProvider
     |                       |                                |
  getChildren('root') -----> | returns category items        |
  getChildren('cat|playlists')-> | SyncService.cachedPlaylists  |
  getChildren('playlist|lib|5')-> | provider.getPlaylistTracksWithCache()
                             |  populates _trackQueueCache   |
  playFromMediaId('track|lib|7|plist|lib|5') ->               |
                             | lookup _trackQueueCache        |
                             | provider.playTracks(builtinId, tracks, startIndex: i)
```

---

## 3. Media ID Scheme

Separator: `|` (pipe). Provider names use underscores/colons, never pipes — safe.

| ID | Meaning |
|----|---------|
| `root` | Root (browsable) |
| `recent` | Currently playing track (playable) |
| `cat\|favorites` | Favorites category (browsable) |
| `cat\|playlists` | Playlists category (browsable) |
| `cat\|albums` | Albums category (browsable) |
| `cat\|radio` | Radio stations category (browsable) |
| `playlist\|{provider}\|{itemId}` | A playlist (browsable) |
| `album\|{provider}\|{itemId}` | An album (browsable) |
| `track\|{tProvider}\|{tItemId}\|{ctxType}\|{ctxProvider}\|{ctxId}` | A track in context (playable) |
| `radio\|{provider}\|{itemId}` | A radio station (playable) |

The `ctxType|ctxProvider|ctxId` suffix in track IDs encodes the parent container. Context types: `plist`, `album`, `favs`, `search`.

**Track queue cache key** = `{ctxType}|{ctxProvider}|{ctxId}` (e.g. `plist|spotify|abc`). Stored when building children, looked up in `playFromMediaId`.

---

## 4. Browse Hierarchy

```
root
├── recent              (playable, shown if something is/was playing)
├── cat|favorites       (browsable → favorite tracks, all playable)
├── cat|playlists       (browsable → list of playlists, each browsable)
│   └── playlist|{provider}|{id}  → tracks (playable)
├── cat|albums          (browsable → list of albums, each browsable)
│   └── album|{provider}|{id}     → tracks (playable)
└── cat|radio           (browsable → radio stations, each playable)
```

Artists are **not included**. Navigating Artist → Albums → Album → Tracks is four taps — too many while driving. Can be added later.

---

## 5. Track Queue Cache

Tapping a track in Android Auto should play the full album/playlist from that track, not just the single track. The handler caches track lists when building children:

```dart
// Key: ctxKey e.g. "plist|spotify|abc" or "album|library|42" or "favs||"
// Value: ordered list of tracks in that container
final Map<String, List<ma.Track>> _trackQueueCache = {};
```

When `getChildren('playlist|spotify|abc')` is called:
1. Fetch tracks via `provider.getPlaylistTracksWithCache('spotify', 'abc')`
2. Store `_trackQueueCache['plist|spotify|abc'] = tracks`
3. Return each track as a playable `MediaItem` with id `track|{t.provider}|{t.itemId}|plist|spotify|abc`

When `playFromMediaId('track|lib|7|plist|spotify|abc')` is called:
1. Parse ctxKey = `plist|spotify|abc`
2. Look up `_trackQueueCache['plist|spotify|abc']`
3. Find track index where `itemId == '7'`
4. Call `provider.playTracks(builtinId, tracks, startIndex: index)`

---

## 6. Key Code for `massiv_audio_handler.dart`

### New imports

```dart
import 'package:rxdart/rxdart.dart';
import '../../providers/music_assistant_provider.dart';
import '../settings_service.dart';
import '../sync_service.dart';
import '../../models/media_item.dart' as ma;
```

Note: `audio_service` exports its own `MediaItem`. Use `ma.MediaItem`, `ma.Track`, `ma.Album`, `ma.Playlist` for app models. The bare `MediaItem` refers to the audio_service type throughout new methods.

### New fields

```dart
MusicAssistantProvider? _provider;
final Map<String, ma.Track> _trackQueueCache = {}; // ctxKey -> tracks (see section 5)
final Map<String, BehaviorSubject<Map<String, dynamic>>> _childrenSubjects = {};

void setProvider(MusicAssistantProvider provider) {
  _provider = provider;
}
```

### `getChildren`

```dart
@override
Future<List<MediaItem>> getChildren(String parentMediaId,
    [Map<String, dynamic>? options]) async {
  final provider = _provider;
  if (provider == null) return [];

  switch (parentMediaId) {
    case AudioService.browsableRootId:
      return _buildRoot(provider);
    case 'cat|favorites':
      return _buildFavorites(provider);
    case 'cat|playlists':
      return _buildPlaylistList(provider);
    case 'cat|albums':
      return _buildAlbumList(provider);
    case 'cat|radio':
      return _buildRadioList(provider);
    default:
      if (parentMediaId.startsWith('playlist|')) {
        final parts = parentMediaId.split('|');
        if (parts.length >= 3) return _buildPlaylistTracks(provider, parts[1], parts[2]);
      }
      if (parentMediaId.startsWith('album|')) {
        final parts = parentMediaId.split('|');
        if (parts.length >= 3) return _buildAlbumTracks(provider, parts[1], parts[2]);
      }
      return [];
  }
}
```

### `playFromMediaId`

```dart
@override
Future<void> playFromMediaId(String mediaId, [Map<String, dynamic>? extras]) async {
  final provider = _provider;
  if (provider == null) return;

  final playerId = await SettingsService.getBuiltinPlayerId();
  if (playerId == null) return;

  _logger.log('AndroidAuto: playFromMediaId $mediaId');

  try {
    if (mediaId == 'recent') {
      await provider.playPauseSelectedPlayer();
      return;
    }

    if (mediaId.startsWith('radio|')) {
      final parts = mediaId.split('|'); // ['radio', provider, itemId]
      if (parts.length < 3) return;
      final station = provider.radioStations.firstWhere(
        (s) => s.provider == parts[1] && s.itemId == parts[2],
        orElse: () => throw Exception('Station not found: $mediaId'),
      );
      await provider.playRadio(playerId, station);
      return;
    }

    if (mediaId.startsWith('track|')) {
      // Format: track|{tProvider}|{tItemId}|{ctxType}|{ctxProvider}|{ctxId}
      final parts = mediaId.split('|');
      if (parts.length < 6) return;
      final tProvider = parts[1];
      final tItemId = parts[2];
      final ctxKey = parts.sublist(3).join('|');

      final trackList = _trackQueueCache[ctxKey];
      if (trackList == null || trackList.isEmpty) {
        // Fallback: play single track (minimal Track object)
        await provider.playTrack(playerId, ma.Track(itemId: tItemId, provider: tProvider, name: ''));
        return;
      }

      final index = trackList.indexWhere((t) => t.provider == tProvider && t.itemId == tItemId);
      await provider.playTracks(playerId, trackList, startIndex: index < 0 ? 0 : index);
      return;
    }
  } catch (e) {
    _logger.log('AndroidAuto: playFromMediaId error: $e');
  }
}
```

### `search`

```dart
@override
Future<List<MediaItem>> search(String query, [Map<String, dynamic>? extras]) async {
  final provider = _provider;
  if (provider == null || query.trim().isEmpty) return [];

  try {
    final results = await provider.searchWithCache(query);
    final tracks = (results['tracks'] ?? []).whereType<ma.Track>().toList();
    const ctxKey = 'search||';
    _trackQueueCache[ctxKey] = tracks;

    return tracks.map((t) => MediaItem(
      id: 'track|${t.provider}|${t.itemId}|$ctxKey',
      title: t.name,
      artist: t.artistsString,
      album: t.album?.name,
      duration: t.duration,
      artUri: _artUri(provider, t),
      playable: true,
    )).toList();
  } catch (e) {
    _logger.log('AndroidAuto: search error: $e');
    return [];
  }
}
```

### `subscribeToChildren`

```dart
@override
ValueStream<Map<String, dynamic>> subscribeToChildren(String parentMediaId) {
  _childrenSubjects[parentMediaId] ??= BehaviorSubject.seeded({});
  return _childrenSubjects[parentMediaId]!.stream;
}
```

### `_artUri` helper

```dart
Uri? _artUri(MusicAssistantProvider provider, ma.MediaItem item) {
  final url = provider.getImageUrl(item, size: 256);
  return url != null ? Uri.tryParse(url) : null;
}
```

---

## 7. Files to Change

### `pubspec.yaml`
Add `rxdart: ^0.28.0` as direct dependency. The `^0.28.0` constraint matches the already-resolved transitive version so no upgrade occurs.

### `android/app/build.gradle`
Change:
```groovy
minSdkVersion flutter.minSdkVersion
```
To:
```groovy
minSdkVersion 23
```
Android Auto requires API 23+. `flutter.minSdkVersion` resolves to 21 — too low.

### `android/app/src/main/AndroidManifest.xml`
Add inside `<application>` tag:
```xml
<meta-data
    android:name="com.google.android.gms.car.application"
    android:resource="@xml/automotive_app_desc" />
```
The `MediaBrowserService` intent filter on `AudioService` is already present — no changes needed there.

### `android/app/src/main/res/xml/automotive_app_desc.xml` (NEW)
```xml
<?xml version="1.0" encoding="utf-8"?>
<automotiveApp>
    <uses name="media" />
</automotiveApp>
```

### `lib/main.dart`
In `_MusicAssistantAppState.initState()`, after creating `_musicProvider`:
```dart
audioHandler.setProvider(_musicProvider);
```

### `lib/services/audio/massiv_audio_handler.dart`
Add ~200 lines. New imports, fields, `setProvider()`, `getChildren()`, `playFromMediaId()`, `search()`, `subscribeToChildren()`, and private builder helpers. All existing code is untouched.

---

## 8. Testing with DHU (No Car Required)

### Install DHU
In Android Studio: SDK Manager → SDK Tools → Android Auto Desktop Head Unit Emulator.

Or via command line:
```bash
sdkmanager "extras;google;auto"
```

### Enable Android Auto developer mode on phone
1. Settings → Apps → Android Auto → tap version number 10 times
2. In Android Auto developer settings: enable "Unknown sources"

### Run the test session
```bash
# Terminal 1: forward the port
adb forward tcp:5277 tcp:5277

# Terminal 2: start the DHU
$ANDROID_SDK_ROOT/extras/google/auto/desktop-head-unit
```

In Android Auto developer settings on phone: tap "Start head unit server".

### Build and install
```bash
flutter build apk --debug
adb install build/app/outputs/flutter-apk/app-debug.apk
```

Launch Ensemble on phone first (so audio service starts). Then tap the media icon in DHU — Ensemble should appear.

### Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| App not visible in DHU | Missing `automotive_app_desc.xml` or wrong meta-data name | Check manifest and XML |
| App visible, browse is empty | `setProvider` not yet called | Check `initState` wiring |
| Build fails | `minSdkVersion` too low | Check `build.gradle` |
| Track plays but wrong song | `_trackQueueCache` miss | Ensure `getChildren` ran before `playFromMediaId` |

---

## 9. Implementation Order

Do these steps in order to test incrementally:

1. Android config files (`build.gradle`, `AndroidManifest.xml`, `automotive_app_desc.xml`) — verify app appears in DHU before writing Dart
2. `pubspec.yaml` + `flutter pub get`
3. `massiv_audio_handler.dart`: add `setProvider`, fields, `subscribeToChildren` — minimum to not crash
4. `main.dart`: wire `setProvider`
5. `massiv_audio_handler.dart`: `getChildren` with hardcoded root categories — verify tree appears in DHU
6. `massiv_audio_handler.dart`: add all `_build*` helpers one by one, test each
7. `massiv_audio_handler.dart`: add `playFromMediaId` — test track playback
8. `massiv_audio_handler.dart`: add `search` — test voice search

---

## 10. Not In Scope

- **Artists browse** — too many taps for driving; albums alone suffice
- **Audiobooks/podcasts** — different UX needs; add later
- **Queue management from Android Auto** — MA queue model is complex
- **Push updates** — `notifyChildrenChanged` stubbed but not wired to sync events
- **Android Automotive OS** — different platform, requires a separate flavor
