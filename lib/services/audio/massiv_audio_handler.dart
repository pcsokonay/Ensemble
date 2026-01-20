import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';
import '../debug_logger.dart';
import '../auth/auth_manager.dart';

/// Custom AudioHandler for Ensemble that provides full control over
/// notification actions and metadata updates.
class MassivAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();
  final AuthManager authManager;
  final _logger = DebugLogger();

  // Stream subscriptions for proper cleanup
  StreamSubscription? _interruptionSubscription;
  StreamSubscription? _becomingNoisySubscription;
  StreamSubscription? _playbackEventSubscription;
  StreamSubscription? _currentIndexSubscription;

  // Track current metadata separately from what's in the notification
  // This allows us to update the notification when metadata arrives late
  MediaItem? _currentMediaItem;

  // Callbacks for actions (wired up by MusicAssistantProvider)
  Function()? onSkipToNext;
  Function()? onSkipToPrevious;
  Function()? onPlay;
  Function()? onPause;
  Function()? onSwitchPlayer;

  // Track whether we're in remote control mode (controlling MA player, not playing locally)
  bool _isRemoteMode = false;

  // Custom control for switching players (uses stop action with custom icon)
  static const _switchPlayerControl = MediaControl(
    androidIcon: 'drawable/ic_switch_player',
    label: 'Switch Player',
    action: MediaAction.stop,
  );

  MassivAudioHandler({required this.authManager}) {
    _init();
  }

  Future<void> _init() async {
    // Configure audio session
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());

    // Handle audio interruptions
    _interruptionSubscription = session.interruptionEventStream.listen((event) {
      if (event.begin) {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _player.setVolume(0.5);
            break;
          case AudioInterruptionType.pause:
          case AudioInterruptionType.unknown:
            pause();
            break;
        }
      } else {
        switch (event.type) {
          case AudioInterruptionType.duck:
            _player.setVolume(1.0);
            break;
          case AudioInterruptionType.pause:
            play();
            break;
          case AudioInterruptionType.unknown:
            break;
        }
      }
    });

    // Handle becoming noisy (headphones unplugged)
    _becomingNoisySubscription = session.becomingNoisyEventStream.listen((_) {
      pause();
    });

    // Broadcast playback state changes
    _playbackEventSubscription = _player.playbackEventStream.listen(_broadcastState);

    // Broadcast current media item changes
    _currentIndexSubscription = _player.currentIndexStream.listen((_) {
      if (_currentMediaItem != null) {
        mediaItem.add(_currentMediaItem);
      }
    });
  }

  /// Broadcast the current playback state to the system
  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;

    playbackState.add(playbackState.value.copyWith(
      // Configure notification action buttons
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        _switchPlayerControl, // Switch player button
      ],
      // System-level actions (for headphones, car stereos, etc.)
      systemActions: const {
        MediaAction.seek,
        MediaAction.seekForward,
        MediaAction.seekBackward,
        MediaAction.play,
        MediaAction.pause,
        MediaAction.stop,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      // Which buttons to show in compact notification (max 3)
      // Show: play/pause (1), skip-next (2), switch-player (3)
      androidCompactActionIndices: const [1, 2, 3],
      processingState: {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    ));
  }

  // --- Playback control methods ---

  @override
  Future<void> play() async {
    if (_isRemoteMode) {
      onPlay?.call();
    } else {
      await _player.play();
    }
  }

  @override
  Future<void> pause() async {
    if (_isRemoteMode) {
      onPause?.call();
    } else {
      await _player.pause();
    }
  }

  @override
  Future<void> stop() async {
    // Stop action is used for switching players (both local and remote modes)
    onSwitchPlayer?.call();
    // Note: We don't actually stop playback - this button is repurposed for player switching
  }

  /// Fully stop the foreground service and release resources
  /// Called after idle timeout to save battery
  Future<void> stopService() async {
    _logger.log('MassivAudioHandler: Stopping foreground service (idle timeout)');
    _isRemoteMode = false;
    _currentMediaItem = null;
    await _player.stop();
    // Call the base stop() to properly stop the foreground service
    await super.stop();
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {
    onSkipToNext?.call();
  }

  @override
  Future<void> skipToPrevious() async {
    onSkipToPrevious?.call();
  }

  // --- Custom methods for Ensemble ---

  /// Play a URL with the given metadata
  Future<void> playUrl(String url, MediaItem item, {Map<String, String>? headers}) async {
    _currentMediaItem = item;
    mediaItem.add(item);

    try {
      final source = AudioSource.uri(
        Uri.parse(url),
        headers: headers,
        tag: item,
      );

      await _player.setAudioSource(source);
      await _player.play();
    } catch (e) {
      _logger.log('MassivAudioHandler: Error playing URL: $e');
      rethrow;
    }
  }

  /// Update the current media item (for notification display)
  /// This can be called when metadata arrives after playback starts
  @override
  Future<void> updateMediaItem(MediaItem item) async {
    _currentMediaItem = item;
    mediaItem.add(item);
  }

  /// Set volume (0.0 to 1.0)
  Future<void> setVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  /// Set remote playback state (for controlling MA players without local playback)
  /// This shows the notification and responds to media controls without playing audio locally.
  void setRemotePlaybackState({
    required MediaItem item,
    required bool playing,
    Duration position = Duration.zero,
    Duration? duration,
  }) {
    _isRemoteMode = true;
    _currentMediaItem = item;
    mediaItem.add(item);

    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.skipToPrevious,
        if (playing) MediaControl.pause else MediaControl.play,
        MediaControl.skipToNext,
        _switchPlayerControl,
      ],
      systemActions: const {
        MediaAction.play,
        MediaAction.pause,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
        MediaAction.stop,
      },
      // Which buttons to show in compact notification (max 3)
      // Show: play/pause (1), skip-next (2), switch-player (3)
      androidCompactActionIndices: const [1, 2, 3],
      processingState: AudioProcessingState.ready,
      playing: playing,
      updatePosition: position,
      bufferedPosition: duration ?? Duration.zero,
      speed: 1.0,
    ));
  }

  /// Clear remote playback state and hide notification
  void clearRemotePlaybackState() {
    _isRemoteMode = false;
    _currentMediaItem = null;

    playbackState.add(playbackState.value.copyWith(
      controls: [],
      processingState: AudioProcessingState.idle,
      playing: false,
    ));
  }

  /// Switch to local playback mode (when builtin player is selected)
  void setLocalMode() {
    _isRemoteMode = false;
  }

  /// Update notification for local mode (builtin player) without switching to remote mode
  /// This allows the notification to show the correct player/track info while keeping
  /// pause working for local audio playback.
  void updateLocalModeNotification({
    required MediaItem item,
    required bool playing,
    Duration? duration,
  }) {
    // Keep local mode - DON'T set _isRemoteMode = true
    // Only update mediaItem if it changed - avoid unnecessary notification refreshes
    // that cause blinking. The playbackState is managed by _broadcastState which
    // responds to actual player events.
    if (_currentMediaItem?.id != item.id ||
        _currentMediaItem?.title != item.title ||
        _currentMediaItem?.artist != item.artist) {
      _currentMediaItem = item;
      mediaItem.add(item);
    }
  }

  bool get isRemoteMode => _isRemoteMode;

  // --- Expose player state for provider ---

  bool get isPlaying => _player.playing;

  Duration get position => _player.position;

  Duration get duration => _player.duration ?? Duration.zero;

  double get volume => _player.volume;

  PlayerState get playerState => _player.playerState;

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Stream<Duration> get positionStream => _player.positionStream;

  Stream<Duration?> get durationStream => _player.durationStream;

  MediaItem? get currentMediaItem => _currentMediaItem;

  /// Dispose of resources and cancel all subscriptions
  Future<void> dispose() async {
    await _interruptionSubscription?.cancel();
    await _becomingNoisySubscription?.cancel();
    await _playbackEventSubscription?.cancel();
    await _currentIndexSubscription?.cancel();
    await _player.dispose();
  }
}
