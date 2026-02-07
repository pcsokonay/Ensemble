import '../models/player.dart';
import 'debug_logger.dart';

/// Manages volume state for group players where the MA API returns null volume.
///
/// Group players (provider == 'player_group') don't have their own volume_level
/// in the MA API. This manager computes an effective volume from group members
/// and caches recently-set volumes to prevent slider snap-back.
class GroupVolumeManager {
  final _logger = DebugLogger();

  // Cache of last-set volume per group player ID.
  // Prevents slider snap-back between setVolume() and next player_updated event.
  final Map<String, int> _pendingVolumes = {};

  // Timestamps for pending volumes - used to expire stale entries
  final Map<String, DateTime> _pendingTimestamps = {};

  // How long to trust a pending volume before falling back to computed average
  static const Duration _pendingTimeout = Duration(seconds: 5);

  /// Check if a player is a group player (provider == 'player_group')
  bool isGroupPlayer(Player player) {
    return player.provider == 'player_group';
  }

  /// Get the effective volume for a player.
  ///
  /// For non-group players: returns player.volumeLevel (unchanged behavior).
  /// For group players: returns cached pending volume if recent, otherwise
  /// computes average from group members.
  ///
  /// [player] - The player to get volume for.
  /// [allPlayers] - All available players (needed to look up group members).
  ///
  /// Returns volume as int 0-100, or null if no volume can be determined.
  int? getEffectiveVolumeLevel(Player player, List<Player> allPlayers) {
    if (!isGroupPlayer(player)) {
      return player.volumeLevel;
    }

    // Check for a recent pending (just-set) volume
    final pending = _pendingVolumes[player.playerId];
    if (pending != null) {
      final timestamp = _pendingTimestamps[player.playerId];
      if (timestamp != null &&
          DateTime.now().difference(timestamp) < _pendingTimeout) {
        return pending;
      }
      // Expired - remove it
      _pendingVolumes.remove(player.playerId);
      _pendingTimestamps.remove(player.playerId);
    }

    // Compute average from group members
    return _computeGroupVolume(player, allPlayers);
  }

  /// Compute the average volume across all group members.
  /// Returns null if no members have a valid volume.
  int? _computeGroupVolume(Player groupPlayer, List<Player> allPlayers) {
    final memberIds = groupPlayer.groupMembers;
    if (memberIds == null || memberIds.isEmpty) {
      _logger.debug('GroupVolume: No group members for ${groupPlayer.name}',
          context: 'GroupVolumeManager');
      return null;
    }

    int totalVolume = 0;
    int count = 0;

    for (final memberId in memberIds) {
      final member =
          allPlayers.where((p) => p.playerId == memberId).firstOrNull;
      if (member != null && member.volumeLevel != null) {
        totalVolume += member.volumeLevel!;
        count++;
      }
    }

    if (count == 0) {
      _logger.debug(
          'GroupVolume: No members with volume for ${groupPlayer.name}',
          context: 'GroupVolumeManager');
      return null;
    }

    final avg = (totalVolume / count).round();
    return avg;
  }

  /// Record that a volume was just set on a group player.
  /// This prevents the slider from snapping back to 0 before the
  /// MA server processes the volume change on all members.
  void onVolumeSet(String playerId, int volumeLevel) {
    _pendingVolumes[playerId] = volumeLevel;
    _pendingTimestamps[playerId] = DateTime.now();
  }

  /// Clear the pending volume for a player.
  void clearPending(String playerId) {
    _pendingVolumes.remove(playerId);
    _pendingTimestamps.remove(playerId);
  }

  /// Clear all cached state (e.g., on disconnect)
  void clear() {
    _pendingVolumes.clear();
    _pendingTimestamps.clear();
  }
}
