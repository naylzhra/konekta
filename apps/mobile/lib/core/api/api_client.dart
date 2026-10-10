import 'dart:async';
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


/// Response of [ApiClient.send]: status code plus the decoded JSON body
/// (null for an empty body, e.g. 204).
class ApiResponse {
  const ApiResponse(this.statusCode, this.body);

  final int statusCode;
  final Object? body;

  bool get isSuccess => statusCode >= 200 && statusCode < 300;
}

enum ApiTransportFailure { offline, timeout, badResponse }

/// The request did not produce a usable HTTP response. Whether it reached
/// the server is unknown, so only retry idempotent requests.
class ApiTransportException implements Exception {
  const ApiTransportException(this.failure);

  final ApiTransportFailure failure;

  @override
  String toString() => 'ApiTransportException(${failure.name})';
}


/// TODO: move base URL to build-time config
class ApiClient {
  ApiClient({this.baseUrl = 'http://10.0.2.2:8000', http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final String baseUrl;
  final http.Client _http;

  static const defaultTimeout = Duration(seconds: 15);

  /// Authenticated JSON request for feature modules (booking, ...). Never
  /// throws on HTTP error statuses -- callers map [ApiResponse.statusCode]
  /// and the `{"detail": ...}` body themselves.
  Future<ApiResponse> send(
    String method,
    String path, {
    String? token,
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
    Duration timeout = defaultTimeout,
  }) async {
    final request = http.Request(method, Uri.parse('$baseUrl$path').replace(queryParameters: query))
      ..headers['Accept'] = 'application/json';
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (headers != null) request.headers.addAll(headers);
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    final http.Response response;
    try {
      response = await http.Response.fromStream(await _http.send(request).timeout(timeout)).timeout(timeout);
    } on TimeoutException {
      throw const ApiTransportException(ApiTransportFailure.timeout);
    } on http.ClientException {
      throw const ApiTransportException(ApiTransportFailure.offline);
    }

    if (response.body.isEmpty) return ApiResponse(response.statusCode, null);
    try {
      return ApiResponse(response.statusCode, jsonDecode(response.body));
    } on FormatException {
      // e.g. a proxy's HTML error page
      if (response.statusCode >= 500) return ApiResponse(response.statusCode, null);
      throw const ApiTransportException(ApiTransportFailure.badResponse);
    }
  }

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
