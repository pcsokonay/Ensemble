/// Extension methods for formatting Duration values.
///
/// Provides consistent duration formatting across the codebase,
/// replacing duplicate _formatDuration() implementations.
extension DurationFormatter on Duration {
  /// Format duration as "H:MM:SS" or "M:SS" depending on length.
  ///
  /// Examples:
  /// - 45 seconds -> "0:45"
  /// - 3 minutes, 45 seconds -> "3:45"
  /// - 1 hour, 3 minutes, 45 seconds -> "1:03:45"
  String toFormattedString() {
    final hours = inHours;
    final minutes = inMinutes % 60;
    final seconds = inSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  /// Format duration as "M:SS" (no hours, minutes not padded).
  ///
  /// Use this for shorter content like songs where hours are unlikely.
  String toMinutesSeconds() {
    final totalSeconds = inSeconds;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Format an integer number of seconds as "H:MM:SS" or "M:SS".
///
/// This is a standalone function for cases where you have raw seconds
/// rather than a Duration object.
String formatDurationSeconds(int seconds) {
  return Duration(seconds: seconds).toFormattedString();
}

/// Format a nullable Duration, returning empty string if null.
String formatDurationOrEmpty(Duration? duration) {
  if (duration == null) return '';
  return duration.toMinutesSeconds();
}
