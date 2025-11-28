import 'dart:convert';
import 'package:http/http.dart' as http;
import 'auth_strategy.dart';
import '../debug_logger.dart';

/// Authelia authentication strategy
/// Used when Music Assistant is behind Authelia reverse proxy authentication
/// Authelia-specific endpoints: /api/firstfactor, /api/verify
class AutheliaStrategy implements AuthStrategy {
  final _logger = DebugLogger();

  @override
  String get name => 'authelia';

  @override
  Future<AuthCredentials?> login(
    String serverUrl,
    String username,
    String password,
  ) async {
    try {
      // Normalize server URL
      var baseUrl = serverUrl;
      if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
        baseUrl = 'https://$baseUrl';
      }

      _logger.log('🔐 Attempting Authelia login to $baseUrl');

      // Parse URL and construct Authelia firstfactor endpoint
      final uri = Uri.parse(baseUrl);
      final authUrl = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: '/api/firstfactor',
      );

      _logger.log('Auth URL: $authUrl');

      // POST to Authelia's firstfactor endpoint
      final response = await http.post(
        authUrl,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'username': username,
          'password': password,
          'keepMeLoggedIn': true,
        }),
      ).timeout(const Duration(seconds: 10));

      _logger.log('Auth response status: ${response.statusCode}');

      // Check for successful authentication
      if (response.statusCode == 200) {
        _logger.log('✓ Authentication successful');

        // Extract session cookie from Set-Cookie header
        final cookies = response.headers['set-cookie'];
        if (cookies != null && cookies.isNotEmpty) {
          _logger.log('✓ Received session cookie');

          final sessionCookie = _extractSessionCookie(cookies);
          if (sessionCookie != null) {
            _logger.log('✓ Extracted session cookie');
            return AuthCredentials('authelia', {
              'session_cookie': sessionCookie,
              'username': username,
            });
          }
        }

        // If 200 but no cookie, something is wrong
        _logger.log('✗ No session cookie in response');
        return null;
      }

      _logger.log('✗ Authentication failed: ${response.statusCode}');
      _logger.log('Response body: ${response.body}');
      return null;
    } catch (e) {
      _logger.log('✗ Login error: $e');
      return null;
    }
  }

  @override
  Future<bool> validateCredentials(
    String serverUrl,
    AuthCredentials credentials,
  ) async {
    final sessionCookie = credentials.data['session_cookie'] as String?;
    if (sessionCookie == null) return false;

    try {
      // Normalize server URL
      var baseUrl = serverUrl;
      if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
        baseUrl = 'https://$baseUrl';
      }

      // Parse URL and construct Authelia verify endpoint
      final uri = Uri.parse(baseUrl);
      final verifyUrl = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.hasPort ? uri.port : null,
        path: '/api/verify',
      );

      final response = await http.get(
        verifyUrl,
        headers: {
          'Cookie': 'authelia_session=$sessionCookie',
        },
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      _logger.log('Auth validation failed: $e');
      return false;
    }
  }

  @override
  Map<String, dynamic> buildWebSocketHeaders(AuthCredentials credentials) {
    final sessionCookie = credentials.data['session_cookie'] as String;
    return {
      'Cookie': 'authelia_session=$sessionCookie',
    };
  }

  @override
  Map<String, String> buildStreamingHeaders(AuthCredentials credentials) {
    final sessionCookie = credentials.data['session_cookie'] as String;
    return {
      'Cookie': 'authelia_session=$sessionCookie',
    };
  }

  @override
  Map<String, dynamic> serializeCredentials(AuthCredentials credentials) {
    return credentials.data;
  }

  @override
  AuthCredentials deserializeCredentials(Map<String, dynamic> data) {
    return AuthCredentials('authelia', data);
  }

  /// Extract authelia_session cookie value from Set-Cookie header
  /// Migrated from auth_service.dart:81-98
  String? _extractSessionCookie(String setCookieHeader) {
    final cookies = setCookieHeader.split(',');

    for (final cookie in cookies) {
      if (cookie.trim().startsWith('authelia_session=')) {
        final parts = cookie.split(';');
        if (parts.isNotEmpty) {
          final value = parts[0].trim();
          if (value.startsWith('authelia_session=')) {
            return value.substring('authelia_session='.length);
          }
        }
      }
    }

    return null;
  }
}
