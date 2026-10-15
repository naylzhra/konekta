import 'dart:convert';

import 'package:http/http.dart' as http;

class AuthResult {
  AuthResult({required this.token, required this.role});

  factory AuthResult.fromJson(Map<String, dynamic> json) => AuthResult(
        token: json['token'] as String,
        role: json['role'] as String,
      );

  final String token;
  final String role;
}


/// Roles that have a home screen in the mobile app. Government accounts
/// sign in through the web dashboard instead.
const mobileRoles = {'passenger', 'driver'};

/// Thrown when the credentials are valid but the account's role can't use
/// the mobile app.
const unsupportedRoleMessage = 'Role not supported in mobile app';

class AuthException implements Exception {
  AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}

final _sharedHttpClient = http.Client();
const _requestTimeout = Duration(seconds: 10);

/// TODO: move base URL to build-time config
class ApiClient {
  ApiClient({this.baseUrl = 'http://10.0.2.2:8000', http.Client? httpClient})
      : _http = httpClient ?? _sharedHttpClient;

  final String baseUrl;
  final http.Client _http;

  Future<Map<String, dynamic>> checkHealth() async {
    final response = await _http.get(Uri.parse('$baseUrl/health')).timeout(_requestTimeout);
    if (response.statusCode != 200) {
      throw Exception('Gateway health check failed: ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }


  /// TODO: different form data specific to the roles
  Future<AuthResult> register({
    required String phoneNumber,
    required String password,
    required String role,
  }) async {
    final response = await _http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone_number': phoneNumber,
        'password': password,
        'role': role,
      }),
    ).timeout(_requestTimeout);
    return _parseAuthResponse(response);
  }

  Future<AuthResult> login({
    required String phoneNumber,
    required String password,
  }) async {
    final response = await _http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone_number': phoneNumber,
        'password': password,
      }),
    ).timeout(_requestTimeout);
    final result = _parseAuthResponse(response);
    if (!mobileRoles.contains(result.role)) {
      // Don't leave a live session behind for an account we won't let in.
      try {
        await logout(result.token);
      } catch (_) {}
      throw AuthException(unsupportedRoleMessage);
    }
    return result;
  }

  Future<void> logout(String token) async {
    await _http.post(
      Uri.parse('$baseUrl/auth/logout'),
      headers: {'Authorization': 'Bearer $token'},
    ).timeout(_requestTimeout);
  }

  AuthResult _parseAuthResponse(http.Response response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw AuthException(body['detail']?.toString() ?? 'Request failed (${response.statusCode})');
    }
    return AuthResult.fromJson(body);
  }
}
