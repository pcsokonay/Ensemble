import 'package:http/http.dart' as http;
import 'auth_strategy.dart';

/// No authentication strategy for open Music Assistant servers
/// Typical scenarios:
/// - Local network deployment (http://192.168.1.100:8095)
/// - Home network without reverse proxy
/// - Development servers
class NoAuthStrategy implements AuthStrategy {
  @override
  String get name => 'none';

  @override
  Future<AuthCredentials?> login(
    String serverUrl,
    String username,
    String password,
  ) async {
    // No authentication required - just test server connectivity
    try {
      final response = await http.get(
        Uri.parse('$serverUrl/api/info'),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        return AuthCredentials('none', {});
      }
    } catch (e) {
      return null;
    }
    return null;
  }

  @override
  Future<bool> validateCredentials(
    String serverUrl,
    AuthCredentials credentials,
  ) async {
    // Always valid for no-auth
    return true;
  }

  @override
  Map<String, dynamic> buildWebSocketHeaders(AuthCredentials credentials) {
    // No auth headers needed
    return {};
  }

  @override
  Map<String, String> buildStreamingHeaders(AuthCredentials credentials) {
    // No auth headers needed
    return {};
  }

  @override
  Map<String, dynamic> serializeCredentials(AuthCredentials credentials) {
    return {};
  }

  @override
  AuthCredentials deserializeCredentials(Map<String, dynamic> data) {
    return AuthCredentials('none', {});
  }
}
