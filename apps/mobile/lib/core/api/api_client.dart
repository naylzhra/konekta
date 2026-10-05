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


class AuthException implements Exception {
  AuthException(this.message);

  final String message;

  @override
  String toString() => message;
}


/// TODO: move base URL to build-time config
class ApiClient {
  ApiClient({this.baseUrl = 'http://10.0.2.2:8000'});

  final String baseUrl;

  Future<Map<String, dynamic>> checkHealth() async {
    final response = await http.get(Uri.parse('$baseUrl/health'));
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
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone_number': phoneNumber,
        'password': password,
        'role': role,
      }),
    );
    return _parseAuthResponse(response);
  }

  Future<AuthResult> login({
    required String phoneNumber,
    required String password,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'phone_number': phoneNumber,
        'password': password,
      }),
    );
    return _parseAuthResponse(response);
  }

  AuthResult _parseAuthResponse(http.Response response) {
    final body = jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw AuthException(body['detail']?.toString() ?? 'Request failed (${response.statusCode})');
    }
    return AuthResult.fromJson(body);
  }
}
