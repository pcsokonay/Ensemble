import 'dart:async';
import 'package:flutter/foundation.dart';
import 'debug_logger.dart';

/// Single source of truth for playback position tracking.
///
/// This service eliminates race conditions by:
/// 1. Being the ONLY place that calculates interpolated position
/// 2. Using consistent interpolation (no mode switching mid-stream)
/// 3. Capping position at track duration
/// 4. Broadcasting position updates via a single stream
///
/// All consumers (UI, notification) should listen to [positionStream]
/// instead of calculating position themselves.
class PositionTracker {
  final DebugLogger _logger = DebugLogger();

  // Current state
  String? _playerId;
  bool _isPlaying = false;
  Duration _duration = Duration.zero;

  // Position tracking - we anchor to a known position and interpolate from there
  double _anchorPosition = 0.0;  // Position in seconds at anchor time
  DateTime _anchorTime = DateTime.now();  // When we set the anchor

  // Interpolation timer
  Timer? _interpolationTimer;

  // Stream controller for position updates
  final _positionController = StreamController<Duration>.broadcast();

  // Last emitted position (to avoid redundant updates)
  int _lastEmittedSeconds = -1;

  /// Stream of position updates (emits every second when playing)
  Stream<Duration> get positionStream => _positionController.stream;

  /// Current position (can be called synchronously)
  Duration get currentPosition {
    if (!_isPlaying) {
      return Duration(seconds: _anchorPosition.round());
    }

    final now = DateTime.now();
    final elapsed = now.difference(_anchorTime).inMilliseconds / 1000.0;
    final interpolated = _anchorPosition + elapsed;

    // Cap at duration to prevent overflow
    final capped = _duration.inSeconds > 0
        ? interpolated.clamp(0.0, _duration.inSeconds.toDouble())
        : interpolated.clamp(0.0, double.infinity);

    return Duration(seconds: capped.round());
  }

  /// Current position in seconds (for compatibility)
  double get currentPositionSeconds {
    if (!_isPlaying) {
      return _anchorPosition;
    }

    final now = DateTime.now();
    final elapsed = now.difference(_anchorTime).inMilliseconds / 1000.0;
    final interpolated = _anchorPosition + elapsed;

    // Cap at duration
    if (_duration.inSeconds > 0) {
      return interpolated.clamp(0.0, _duration.inSeconds.toDouble());
    }
    return interpolated.clamp(0.0, double.infinity);
  }

  /// Update with fresh data from server.
  ///
  /// [playerId] - The player this update is for
  /// [position] - Current position in seconds from server
  /// [isPlaying] - Whether the player is currently playing
  /// [duration] - Track duration (null if unknown)
  /// [serverTimestamp] - Server's timestamp for when position was recorded (optional)
  void updateFromServer({
    required String playerId,
    required double position,
    required bool isPlaying,
    Duration? duration,
    double? serverTimestamp,
  }) {
    final bool playerChanged = _playerId != playerId;
    final bool playStateChanged = _isPlaying != isPlaying;
    final bool durationChanged = duration != null && _duration != duration;

    // Log significant changes
    if (playerChanged || playStateChanged) {
      _logger.log('PositionTracker: player=$playerId, playing=$isPlaying, pos=${position.toStringAsFixed(1)}s');
    }

    _playerId = playerId;
    _duration = duration ?? _duration;

    // Calculate the best anchor position
    double anchorPos = position;
    bool hasStaleTimestamp = false;

    // If server provides timestamp, use it to calculate current position more accurately
    if (serverTimestamp != null && isPlaying) {
      final now = DateTime.now().millisecondsSinceEpoch / 1000.0;
      final serverAge = now - serverTimestamp;

      // Only use server timestamp if it's reasonably fresh (< 30 seconds)
      // and not in the future (clock skew)
      if (serverAge >= 0 && serverAge < 30) {
        anchorPos = position + serverAge;
        _logger.log('PositionTracker: Using server timestamp, age=${serverAge.toStringAsFixed(1)}s, adjusted pos=${anchorPos.toStringAsFixed(1)}s');
      } else {
        // Timestamp is stale - mark this so we don't blindly trust the position
        hasStaleTimestamp = true;
        if (serverAge >= 30) {
          _logger.log('PositionTracker: Stale timestamp (age=${serverAge.toStringAsFixed(0)}s), raw pos=${position.toStringAsFixed(1)}s');
        }
      }
    }

    // Cap at duration
    if (_duration.inSeconds > 0) {
      anchorPos = anchorPos.clamp(0.0, _duration.inSeconds.toDouble());
    }

    // Detect if position jumped significantly (more than 3 seconds difference)
    // This helps identify seeks or track changes
    final currentInterpolated = currentPositionSeconds;
    final positionDiff = (anchorPos - currentInterpolated).abs();
    final isBackwardJump = anchorPos < currentInterpolated;
    final isJumpToNearZero = anchorPos < 3.0;

    // Detect suspicious backward jumps to 0 - likely bad server data
    // This happens when some player types don't report elapsed_time correctly
    final isSuspiciousReset = !playerChanged
        && !playStateChanged
        && !durationChanged
        && isPlaying
        && _isPlaying
        && isBackwardJump
        && isJumpToNearZero
        && currentInterpolated > 3.0;

    if (positionDiff > 3 && _isPlaying && isPlaying && !playerChanged) {
      if (isSuspiciousReset) {
        _logger.log('PositionTracker: Ignoring suspicious reset to 0: ${currentInterpolated.toStringAsFixed(1)}s -> ${anchorPos.toStringAsFixed(1)}s (likely bad server data)');
      } else if (hasStaleTimestamp) {
        _logger.log('PositionTracker: Ignoring position diff due to stale timestamp: ${currentInterpolated.toStringAsFixed(1)}s -> ${anchorPos.toStringAsFixed(1)}s (keeping interpolated)');
      } else {
        _logger.log('PositionTracker: Position jump detected: ${currentInterpolated.toStringAsFixed(1)}s -> ${anchorPos.toStringAsFixed(1)}s (diff: ${positionDiff.toStringAsFixed(1)}s)');
      }
    }

    // Always update anchor when:
    // 1. Player changed
    // 2. Play state changed
    // 3. Position jumped significantly (seek or track change) - BUT NOT if it's a suspicious reset
    //    AND NOT if the timestamp is stale (stale data shouldn't override interpolated position)
    // 4. We're not playing (paused state should reflect server position)
    //
    // Key insight: When timestamp is stale, the raw position from server is likely outdated.
    // Our interpolated position is probably more accurate, so don't let stale data override it.
    final shouldUpdateAnchor = playerChanged
        || playStateChanged
        || (positionDiff > 2 && !isSuspiciousReset && !hasStaleTimestamp)
        || !isPlaying;

    if (shouldUpdateAnchor) {
      _anchorPosition = anchorPos;
      _anchorTime = DateTime.now();
    }

    _isPlaying = isPlaying;

    // Manage interpolation timer
    if (isPlaying) {
      _startInterpolationTimer();
    } else {
      _stopInterpolationTimer();
      // Emit current position for paused state
      _emitPosition();
    }
  }

  /// Handle seek - immediately update position without waiting for server
  void onSeek(double positionSeconds) {
    _logger.log('PositionTracker: Seek to ${positionSeconds.toStringAsFixed(1)}s');
    _anchorPosition = positionSeconds;
    _anchorTime = DateTime.now();
    _lastEmittedSeconds = -1; // Force emit
    _emitPosition();
  }

  /// Handle track change - reset position to 0
  void onTrackChange(String playerId, Duration? newDuration) {
    _logger.log('PositionTracker: Track change, duration=${newDuration?.inSeconds}s');
    _playerId = playerId;
    _duration = newDuration ?? Duration.zero;
    _anchorPosition = 0.0;
    _anchorTime = DateTime.now();
    _lastEmittedSeconds = -1;
    _emitPosition();
  }

  /// Handle player selection change
  void onPlayerSelected(String playerId) {
    if (_playerId != playerId) {
      _logger.log('PositionTracker: Player selected: $playerId');
      _playerId = playerId;
      // Don't reset position - let updateFromServer handle it with actual data
      _lastEmittedSeconds = -1;
    }
  }

  /// Clear tracker state (e.g., when disconnecting)
  void clear() {
    _logger.log('PositionTracker: Cleared');
    _stopInterpolationTimer();
    _playerId = null;
    _isPlaying = false;
    _anchorPosition = 0.0;
    _duration = Duration.zero;
    _lastEmittedSeconds = -1;
  }

  void _startInterpolationTimer() {
    if (_interpolationTimer != null) return;

    _interpolationTimer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      _emitPosition();
    });

    // Emit immediately
    _emitPosition();
  }

  void _stopInterpolationTimer() {
    _interpolationTimer?.cancel();
    _interpolationTimer = null;
  }

  void _emitPosition() {
    final pos = currentPosition;
    final seconds = pos.inSeconds;

    // Only emit if second changed (reduces unnecessary updates)
    if (seconds != _lastEmittedSeconds) {
      _lastEmittedSeconds = seconds;
      _positionController.add(pos);
    }
  }

  /// Check if position has reached or exceeded duration (track ended)
  bool get hasReachedEnd {
    if (_duration.inSeconds <= 0) return false;
    return currentPositionSeconds >= _duration.inSeconds;
  }

  void dispose() {
    _stopInterpolationTimer();
    _positionController.close();
  }
}
