/// Authentication credentials container
class AuthCredentials {
  final String strategyName;
  final Map<String, dynamic> data;

  AuthCredentials(this.strategyName, this.data);
}

/// Abstract authentication strategy interface
/// Implementations handle different auth methods (none, basic, Authelia, HA, etc.)
abstract class AuthStrategy {
  /// Strategy name identifier (e.g., 'none', 'basic', 'authelia')
  String get name;

  /// Attempt login and return auth credentials/token
  /// Returns null if login fails
  Future<AuthCredentials?> login(
    String serverUrl,
    String username,
    String password,
  );

  /// Test if current credentials are still valid
  Future<bool> validateCredentials(
    String serverUrl,
    AuthCredentials credentials,
  );

  /// Build headers for WebSocket connection
  /// Example: {'Authorization': 'Basic xyz'} or {'Cookie': 'session=abc'}
  Map<String, dynamic> buildWebSocketHeaders(AuthCredentials credentials);

  /// Build headers for HTTP streaming requests
  /// Example: {'Authorization': 'Basic xyz'}
  Map<String, String> buildStreamingHeaders(AuthCredentials credentials);

  /// Serialize credentials for persistent storage
  Map<String, dynamic> serializeCredentials(AuthCredentials credentials);

  /// Deserialize credentials from persistent storage
  AuthCredentials deserializeCredentials(Map<String, dynamic> data);
}
