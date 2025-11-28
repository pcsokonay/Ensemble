import 'package:http/http.dart' as http;
import 'auth_strategy.dart';
import 'no_auth_strategy.dart';
import 'basic_auth_strategy.dart';
import 'authelia_strategy.dart';
import '../debug_logger.dart';

/// Central authentication manager
/// Manages auth strategy selection, auto-detection, and credential lifecycle
class AuthManager {
  final _logger = DebugLogger();

  // Available auth strategies
  final List<AuthStrategy> _strategies = [
    NoAuthStrategy(),
    BasicAuthStrategy(),
    AutheliaStrategy(),
  ];

  AuthStrategy? _currentStrategy;
  AuthCredentials? _currentCredentials;

  /// Get current auth strategy (null if none selected)
  AuthStrategy? get currentStrategy => _currentStrategy;

  /// Get current credentials (null if none stored)
  AuthCredentials? get currentCredentials => _currentCredentials;

  /// Auto-detect authentication requirements for a server
  /// Returns null if server is unreachable or auth method unknown
  Future<AuthStrategy?> detectAuthStrategy(String serverUrl) async {
    _logger.log('🔍 Auto-detecting auth strategy for $serverUrl');

    // Normalize URL
    var baseUrl = serverUrl;
    if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
      baseUrl = 'https://$baseUrl';
    }

    // Try no-auth first (fastest and most common for local deployments)
    _logger.log('Testing no-auth strategy...');
    final canConnect = await _canConnectWithoutAuth(baseUrl);
    _logger.log('No-auth result: $canConnect');

    if (canConnect) {
      _logger.log('✓ Server does not require authentication');
      return _strategies.firstWhere((s) => s.name == 'none');
    }

    // Probe server for auth requirements
    try {
      _logger.log('Probing server for auth headers...');
      final probeUrl = '$baseUrl/api/info';
      _logger.log('Probe URL: $probeUrl');

      final response = await http.get(
        Uri.parse(probeUrl),
      ).timeout(const Duration(seconds: 10));

      _logger.log('Probe status: ${response.statusCode}');

      // Server returned 401 Unauthorized - check WWW-Authenticate header
      if (response.statusCode == 401) {
        final wwwAuth = response.headers['www-authenticate']?.toLowerCase();
        _logger.log('401 with WWW-Authenticate: $wwwAuth');

        // Check for Basic Auth
        if (wwwAuth != null && wwwAuth.contains('basic')) {
          _logger.log('✓ Detected Basic Authentication');
          return _strategies.firstWhere((s) => s.name == 'basic');
        }

        // Check for Bearer token (future: Home Assistant or OAuth)
        if (wwwAuth != null && wwwAuth.contains('bearer')) {
          _logger.log('⚠️ Detected Bearer auth (not yet supported)');
          return null;
        }
      }

      // Check for Authelia-specific endpoints
      _logger.log('Testing for Authelia endpoints...');
      final verifyUrl = '$baseUrl/api/verify';
      _logger.log('Verify URL: $verifyUrl');

      final verifyResponse = await http.get(
        Uri.parse(verifyUrl),
      ).timeout(const Duration(seconds: 10));

      _logger.log('Verify status: ${verifyResponse.statusCode}');

      if (verifyResponse.statusCode == 401) {
        // Authelia typically returns 401 on /api/verify without session
        _logger.log('✓ Detected Authelia authentication');
        return _strategies.firstWhere((s) => s.name == 'authelia');
      }
    } catch (e) {
      _logger.log('✗ Auth detection error: $e');
      return null; // Return null instead of rethrow to show generic error
    }

    _logger.log('⚠️ Could not determine auth method');
    return null;
  }

  /// Test if server is accessible without authentication
  Future<bool> _canConnectWithoutAuth(String serverUrl) async {
    try {
      final testUrl = '$serverUrl/api/info';
      _logger.log('No-auth test URL: $testUrl');

      final response = await http.get(
        Uri.parse(testUrl),
      ).timeout(const Duration(seconds: 10));

      _logger.log('No-auth status: ${response.statusCode}');

      // 200 = no auth required, 401 = auth required
      return response.statusCode == 200;
    } catch (e) {
      _logger.log('No-auth error: $e');
      return false;
    }
  }

  /// Attempt login with specified strategy
  /// Returns true if login successful and credentials stored
  Future<bool> login(
    String serverUrl,
    String username,
    String password,
    AuthStrategy strategy,
  ) async {
    _logger.log('Attempting login with ${strategy.name} strategy');

    final credentials = await strategy.login(serverUrl, username, password);

    if (credentials != null) {
      _currentStrategy = strategy;
      _currentCredentials = credentials;
      _logger.log('✓ Login successful with ${strategy.name}');
      return true;
    }

    _logger.log('✗ Login failed with ${strategy.name}');
    return false;
  }

  /// Validate current credentials are still valid
  Future<bool> validateCurrentCredentials(String serverUrl) async {
    if (_currentStrategy == null || _currentCredentials == null) {
      return false;
    }

    return await _currentStrategy!.validateCredentials(
      serverUrl,
      _currentCredentials!,
    );
  }

  /// Get WebSocket connection headers for current credentials
  Map<String, dynamic> getWebSocketHeaders() {
    if (_currentStrategy == null || _currentCredentials == null) {
      return {};
    }

    return _currentStrategy!.buildWebSocketHeaders(_currentCredentials!);
  }

  /// Get HTTP streaming headers for current credentials
  Map<String, String> getStreamingHeaders() {
    if (_currentStrategy == null || _currentCredentials == null) {
      return {};
    }

    return _currentStrategy!.buildStreamingHeaders(_currentCredentials!);
  }

  /// Serialize current credentials for persistent storage
  Map<String, dynamic>? serializeCredentials() {
    if (_currentStrategy == null || _currentCredentials == null) {
      return null;
    }

    return {
      'strategy': _currentStrategy!.name,
      'data': _currentStrategy!.serializeCredentials(_currentCredentials!),
    };
  }

  /// Deserialize and restore credentials from persistent storage
  void deserializeCredentials(Map<String, dynamic> stored) {
    final strategyName = stored['strategy'] as String?;
    final data = stored['data'] as Map<String, dynamic>?;

    if (strategyName == null || data == null) {
      return;
    }

    // Find matching strategy
    try {
      final strategy = _strategies.firstWhere((s) => s.name == strategyName);
      _currentStrategy = strategy;
      _currentCredentials = strategy.deserializeCredentials(data);
      _logger.log('✓ Restored ${strategy.name} credentials from storage');
    } catch (e) {
      _logger.log('✗ Could not restore credentials: $e');
    }
  }

  /// Clear current authentication state
  void logout() {
    _currentStrategy = null;
    _currentCredentials = null;
    _logger.log('Logged out - cleared auth state');
  }

  /// Get strategy by name (for manual selection)
  AuthStrategy? getStrategyByName(String name) {
    try {
      return _strategies.firstWhere((s) => s.name == name);
    } catch (e) {
      return null;
    }
  }
}
