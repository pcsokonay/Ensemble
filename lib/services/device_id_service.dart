import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'debug_logger.dart';

/// Service to generate unique per-installation player IDs
/// Uses random UUID to ensure each installation has a unique ID
/// This prevents the critical bug where multiple devices of the same model
/// would share the same player ID and trigger playback on all devices
class DeviceIdService {
  static const String _keyLocalPlayerId = 'local_player_id';
  static const String _legacyKeyDevicePlayerId = 'device_player_id';
  static const String _legacyKeyBuiltinPlayerId = 'builtin_player_id';
  static final _logger = DebugLogger();
  static const _uuid = Uuid();

  /// Get or generate a unique player ID for this installation
  /// ID is generated once and persisted across app restarts
  /// Format: ensemble_<uuid>
  static Future<String> getOrCreateDevicePlayerId() async {
    final prefs = await SharedPreferences.getInstance();

    // Check for new UUID-based ID
    final existingId = prefs.getString(_keyLocalPlayerId);
    if (existingId != null && existingId.startsWith('ensemble_')) {
      _logger.log('Using existing installation UUID: $existingId');
      return existingId;
    }

    // Check for legacy IDs and migrate
    final legacyDeviceId = prefs.getString(_legacyKeyDevicePlayerId);
    final legacyBuiltinId = prefs.getString(_legacyKeyBuiltinPlayerId);

    if (legacyDeviceId != null || legacyBuiltinId != null) {
      _logger.log('Migrating from legacy ID (device: $legacyDeviceId, builtin: $legacyBuiltinId)');
      // Don't try to clean up old player from server - just generate new ID
    }

    // Generate new UUID-based ID
    final uuid = _uuid.v4();
    final playerId = 'ensemble_$uuid';

    // Store it permanently
    await prefs.setString(_keyLocalPlayerId, playerId);

    // Update builtin_player_id for compatibility with existing code
    await prefs.setString(_legacyKeyBuiltinPlayerId, playerId);

    _logger.log('Generated new installation UUID: $playerId');

    return playerId;
  }

  /// Check if we're using a legacy hardware-based ID (for migration purposes)
  static Future<bool> isUsingLegacyId() async {
    final prefs = await SharedPreferences.getInstance();
    final newId = prefs.getString(_keyLocalPlayerId);

    // If we don't have the new UUID-based ID, we're on legacy
    if (newId == null || !newId.startsWith('ensemble_')) {
      return true;
    }

    return false;
  }

  /// Migrate from legacy hardware-based ID to UUID-based ID
  /// Returns the new UUID-based ID
  static Future<String> migrateToDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final legacyId = prefs.getString(_legacyKeyBuiltinPlayerId) ??
                     prefs.getString(_legacyKeyDevicePlayerId);

    _logger.log('Migrating from legacy ID: $legacyId');

    // Generate new UUID-based ID
    final newId = await getOrCreateDevicePlayerId();

    _logger.log('Migrated to UUID-based ID: $newId');

    return newId;
  }
}
