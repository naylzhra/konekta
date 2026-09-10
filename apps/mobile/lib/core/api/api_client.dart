import 'dart:convert';

import 'package:http/http.dart' as http;

/// Minimal API client stub pointed at the gateway service.
///
/// TODO: move base URL to build-time config / flavors once staging and
/// production gateways exist. 10.0.2.2 is the Android emulator's alias
/// for the host machine's localhost.
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
}
