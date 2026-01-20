import 'dart:async';
import 'package:flutter/foundation.dart';
import '../services/music_assistant_api.dart';
import '../services/settings_service.dart';
import '../services/debug_logger.dart';
import '../services/error_handler.dart';
import '../services/auth/auth_manager.dart';

/// Callback types for connection events
typedef OnConnected = Future<void> Function();
typedef OnAuthenticated = Future<void> Function();
typedef OnDisconnected = void Function();

/// Provider for connection state management.
///
/// Extracted from MusicAssistantProvider to handle:
/// - WebSocket connection lifecycle
/// - Authentication flow (MA token, credentials)
/// - Reconnection logic
/// - Connection state broadcasting
///
/// Note: This is a partial extraction. Full integration requires updating
/// all consumers to use this provider directly.
class ConnectionProvider with ChangeNotifier {
  final DebugLogger _logger = DebugLogger();
  final AuthManager _authManager = AuthManager();

  MusicAssistantAPI? _api;
  String? _serverUrl;
  String? _error;
  MAConnectionState _connectionState = MAConnectionState.disconnected;

  StreamSubscription? _connectionStateSubscription;

  // Callbacks for connection events - set by the facade provider
  OnConnected? onConnected;
  OnAuthenticated? onAuthenticated;
  OnDisconnected? onDisconnected;

  // User settings captured during authentication
  List<String> _providerFilter = [];
  List<String> _playerFilter = [];

  // ============================================================================
  // GETTERS
  // ============================================================================

  MusicAssistantAPI? get api => _api;
  AuthManager get authManager => _authManager;
  String? get serverUrl => _serverUrl;
  String? get error => _error;
  MAConnectionState get connectionState => _connectionState;

  bool get isConnected =>
      _connectionState == MAConnectionState.connected ||
      _connectionState == MAConnectionState.authenticated;

  List<String> get providerFilter => _providerFilter;
  List<String> get playerFilter => _playerFilter;

  // ============================================================================
  // CONNECTION
  // ============================================================================

  /// Connect to the Music Assistant server
  Future<void> connect(String serverUrl) async {
    try {
      _error = null;
      _serverUrl = serverUrl;
      await SettingsService.setServerUrl(serverUrl);

      // Dispose the old API to stop any pending reconnects
      _api?.dispose();

      _api = MusicAssistantAPI(serverUrl, _authManager);

      _connectionStateSubscription?.cancel();
      _connectionStateSubscription = _api!.connectionState.listen(
        (state) async {
          _connectionState = state;
          notifyListeners();

          if (state == MAConnectionState.connected) {
            _logger.log('🔗 WebSocket connected to MA server');

            if (_api!.authRequired && !_api!.isAuthenticated) {
              _logger.log('🔐 MA auth required, attempting authentication...');
              final authenticated = await _handleAuthentication();
              if (!authenticated) {
                _error = 'Authentication required. Please log in again.';
                notifyListeners();
                return;
              }
              return;
            }

            // No auth required, trigger callback
            await onConnected?.call();
          } else if (state == MAConnectionState.authenticated) {
            _logger.log('✅ MA authentication successful');
            await onAuthenticated?.call();
          } else if (state == MAConnectionState.disconnected) {
            _logger.log('📡 Disconnected - keeping cached data for instant resume');
            onDisconnected?.call();
          }
        },
        onError: (error) {
          _logger.log('Connection state stream error: $error');
          _connectionState = MAConnectionState.error;
          notifyListeners();
        },
      );

      await _api!.connect();
      notifyListeners();
    } catch (e) {
      final errorInfo = ErrorHandler.handleError(e, context: 'Connect to server');
      _error = errorInfo.userMessage;
      _connectionState = MAConnectionState.error;
      _logger.log('Connection error: ${errorInfo.technicalMessage}');
      notifyListeners();
      rethrow;
    }
  }

  Future<bool> _handleAuthentication() async {
    if (_api == null) return false;

    try {
      final storedToken = await SettingsService.getMaAuthToken();
      if (storedToken != null) {
        _logger.log('🔐 Trying stored MA token...');
        final success = await _api!.authenticateWithToken(storedToken);
        if (success) {
          _logger.log('✅ MA authentication with stored token successful');
          await _fetchUserSettings();
          return true;
        }
        _logger.log('⚠️ Stored MA token invalid, clearing...');
        await SettingsService.clearMaAuthToken();
      }

      final username = await SettingsService.getUsername();
      final password = await SettingsService.getPassword();

      if (username != null &&
          password != null &&
          username.isNotEmpty &&
          password.isNotEmpty) {
        _logger.log('🔐 Trying stored credentials...');
        final accessToken = await _api!.loginWithCredentials(username, password);

        if (accessToken != null) {
          _logger.log('✅ MA login with stored credentials successful');

          final longLivedToken = await _api!.createLongLivedToken();
          if (longLivedToken != null) {
            await SettingsService.setMaAuthToken(longLivedToken);
            _logger.log('✅ Saved new long-lived MA token');
          } else {
            await SettingsService.setMaAuthToken(accessToken);
          }

          await _fetchUserSettings();
          return true;
        }
      }

      _logger.log('❌ MA authentication failed - no valid token or credentials');
      return false;
    } catch (e) {
      _logger.log('❌ MA authentication error: $e');
      return false;
    }
  }

  Future<void> _fetchUserSettings() async {
    if (_api == null) return;

    try {
      final userInfo = await _api!.getCurrentUserInfo();
      if (userInfo == null) return;

      // Set profile name
      final displayName = userInfo['display_name'] as String?;
      final username = userInfo['username'] as String?;
      final profileName =
          (displayName != null && displayName.isNotEmpty) ? displayName : username;

      if (profileName != null && profileName.isNotEmpty) {
        await SettingsService.setOwnerName(profileName);
        _logger.log('✅ Set owner name from MA profile: $profileName');
      }

      // Capture provider filter
      final providerFilterRaw = userInfo['provider_filter'];
      if (providerFilterRaw is List) {
        _providerFilter = providerFilterRaw.cast<String>().toList();
        if (_providerFilter.isNotEmpty) {
          _logger.log(
              '🔒 Provider filter active: ${_providerFilter.length} providers allowed');
        }
      } else {
        _providerFilter = [];
      }

      // Capture player filter
      final playerFilterRaw = userInfo['player_filter'];
      if (playerFilterRaw is List) {
        _playerFilter = playerFilterRaw.cast<String>().toList();
        if (_playerFilter.isNotEmpty) {
          _logger.log(
              '🔒 Player filter active: ${_playerFilter.length} players allowed');
        }
      } else {
        _playerFilter = [];
      }
    } catch (e) {
      _logger.log('⚠️ Could not fetch user settings (non-fatal): $e');
    }
  }

  /// Disconnect from the server
  Future<void> disconnect() async {
    _connectionStateSubscription?.cancel();
    await _api?.disconnect();
    _connectionState = MAConnectionState.disconnected;
    notifyListeners();
  }

  /// Check connection and reconnect if needed
  Future<void> checkAndReconnect() async {
    if (_serverUrl != null && !isConnected) {
      _logger.log('🔄 Attempting reconnection...');
      await connect(_serverUrl!);
    }
  }

  @override
  void dispose() {
    _connectionStateSubscription?.cancel();
    _api?.dispose();
    super.dispose();
  }
}
