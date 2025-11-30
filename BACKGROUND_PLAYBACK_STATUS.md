# Background Playback Status

## Current State (2025-11-30)

**Branch:** `feature/background-playback`

### Working
- Local playback via fallback `just_audio` player
- Audio streams correctly from Music Assistant server
- Play/pause/seek controls work in-app
- Position tracking and state sync with MA server

### Not Working
- Background playback (audio stops when app is backgrounded)
- Media notification controls (no notification appears)

## The Problem

`AudioService.init()` causes the app to crash on playback. We tried:

1. **`FlutterActivity` (original)** - AudioService.init() fails silently, falls back to just_audio (worked)
2. **`AudioServiceActivity`** - App crashes on playback attempt
3. **`AudioServiceFragmentActivity`** - App crashes on playback attempt

The crash happens so fast that logs aren't written before the app dies. Android logcat doesn't show the exception (likely due to log restrictions on non-debuggable release builds).

## Temporary Fix

AudioService initialization is disabled in `lib/main.dart`. The app uses the fallback `just_audio` player directly, which works but doesn't support background playback.

## Files Involved

- `lib/main.dart` - AudioService init (currently commented out)
- `lib/services/audio_handler.dart` - MassivAudioHandler implementation
- `lib/services/local_player_service.dart` - Uses audioHandler with fallback to just_audio
- `android/app/src/main/kotlin/.../MainActivity.kt` - Currently extends FlutterActivity
- `android/app/src/main/AndroidManifest.xml` - Has all required permissions and service declarations

## AndroidManifest Configuration (Verified Correct)

```xml
<uses-permission android:name="android.permission.WAKE_LOCK"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>

<service android:name="com.ryanheise.audioservice.AudioService"
    android:foregroundServiceType="mediaPlayback"
    android:exported="true">
    <intent-filter>
        <action android:name="android.media.browse.MediaBrowserService" />
    </intent-filter>
</service>

<receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
    android:exported="true">
    <intent-filter>
        <action android:name="android.intent.action.MEDIA_BUTTON" />
    </intent-filter>
</receiver>
```

## Notification Icon (Verified Exists)

`android/app/src/main/res/drawable/ic_notification.xml` exists and is referenced in AudioServiceConfig.

## Dependencies

```yaml
just_audio: ^0.9.36
audio_service: ^0.18.12
audio_session: ^0.1.18
```

## Reference App

https://github.com/Dr-Blank/Vaani - Uses `just_audio_background` (a simpler wrapper) instead of raw `audio_service`

## Potential Solutions to Investigate

1. **Use `just_audio_background`** instead of `audio_service` directly
   - Simpler API, may avoid the crash
   - See Vaani app for implementation reference

2. **Debug with ADB on debug build**
   - Build a debug APK to get full crash logs
   - `flutter build apk --debug`
   - Connect via ADB and get full logcat output

3. **Check for Pixel 9 Pro Fold specific issues**
   - Foldable devices sometimes have quirks with foreground services
   - May need device-specific workarounds

4. **Try older audio_service version**
   - Downgrade to see if it's a regression

5. **Custom FlutterEngine setup**
   - Manually configure the audio service connection without extending AudioServiceActivity

## Next Session Prompt

```
Continue working on https://github.com/CollotsSpot/Massiv branch: feature/background-playback
Local folder: /home/home-server/Massiv

CURRENT STATUS:
- Local playback WORKING (using fallback just_audio player)
- Background playback + media notification NOT working (AudioService crashes app)

THE ISSUE:
AudioServiceActivity/AudioServiceFragmentActivity cause app crash on playback.
Crash happens too fast to capture logs.

POTENTIAL NEXT STEPS:
1. Try just_audio_background package instead of raw audio_service
2. Build debug APK and capture crash via ADB
3. Check for Pixel 9 Pro Fold specific issues

KEY FILES:
- lib/main.dart - AudioService init (currently disabled)
- lib/services/audio_handler.dart - MassivAudioHandler implementation
- lib/services/local_player_service.dart - Uses audioHandler with fallback
- android/app/src/main/kotlin/.../MainActivity.kt - Currently FlutterActivity

REFERENCE: See BACKGROUND_PLAYBACK_STATUS.md for full context
```
