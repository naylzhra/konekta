import 'package:latlong2/latlong.dart';

import '../../../core/api/api_client.dart';
import '../domain/feeder_models.dart';

class FeederApiException implements Exception {
  const FeederApiException(this.code, {this.statusCode});

  static const offline = 'offline';
  static const unauthorized = 'unauthorized';
  static const noFeederAssigned = 'no_feeder_assigned';
  static const outsideServiceArea = 'outside_service_area';
  static const inaccuratePosition = 'inaccurate_position';
  static const tooFrequent = 'too_frequent';
  static const unknown = 'unknown';

  final String code;
  final int? statusCode;

  @override
  String toString() => 'FeederApiException($code)';
}

class FeederApi {
  FeederApi(this._api);

  final ApiClient _api;

  Future<List<CorridorOption>> listCorridors() async {
    final body = await _request('GET', '/corridors');
    return [
      for (final item
          in (body as Map<String, dynamic>)['items'] as List<dynamic>)
        CorridorOption.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<CorridorRoute> routeStops(String corridorId,
          {RouteDirection direction = RouteDirection.forward}) async =>
      CorridorRoute.fromJson(await _request('GET', '/corridors/$corridorId/stops',
          query: {'direction': direction.wire}) as Map<String, dynamic>);

  Future<List<LatLng>> routePath(String corridorId,
      {RouteDirection direction = RouteDirection.forward}) async {
    final body = await _request('GET', '/corridors/$corridorId/path',
        query: {'direction': direction.wire}) as Map<String, dynamic>;
    return [
      for (final point in body['points'] as List<dynamic>)
        LatLng(
          ((point as Map<String, dynamic>)['lat'] as num).toDouble(),
          (point['lng'] as num).toDouble(),
        ),
    ];
  }

  /// Every feeder currently on duty; live updates follow on `corridor:<id>`.
  Future<List<FeederPosition>> liveFeeders(String token) async {
    final body = await _request('GET', '/feeders/live', token: token);
    return [
      for (final item
          in (body as Map<String, dynamic>)['items'] as List<dynamic>)
        FeederPosition.fromJson(item as Map<String, dynamic>),
    ];
  }

  Future<AssignedFeeder> myFeeder(String token) async =>
      AssignedFeeder.fromJson(await _request('GET', '/feeders/me', token: token)
          as Map<String, dynamic>);

  Future<DateTime> reportPosition(
    String token, {
    required double lat,
    required double lng,
    double? heading,
    double? accuracyM,
    RouteDirection? direction,
  }) async {
    final body = await _request(
      'POST',
      '/feeders/me/position',
      token: token,
      body: {
        'lat': lat,
        'lng': lng,
        if (heading != null) 'heading': heading,
        if (accuracyM != null) 'accuracy_m': accuracyM,
        if (direction != null) 'direction': direction.wire,
      },
      timeout: const Duration(seconds: 5),
    );
    return DateTime.parse(
        (body as Map<String, dynamic>)['updated_at'] as String);
  }

  Future<void> goOffline(String token) =>
      _request('POST', '/feeders/me/offline', token: token);

  Future<Object?> _request(
    String method,
    String path, {
    String? token,
    Object? body,
    Map<String, String>? query,
    Duration timeout = ApiClient.defaultTimeout,
  }) async {
    final ApiResponse response;
    try {
      response = await _api.send(method, path,
          token: token, body: body, query: query, timeout: timeout);
    } on ApiTransportException {
      throw const FeederApiException(FeederApiException.offline);
    }
    if (response.isSuccess) return response.body;
    if (response.statusCode == 401) {
      throw FeederApiException(FeederApiException.unauthorized,
          statusCode: response.statusCode);
    }
    final detail = response.body is Map<String, dynamic>
        ? (response.body as Map<String, dynamic>)['detail']
        : null;
    final code = detail is Map<String, dynamic> ? detail['code'] : null;
    throw FeederApiException(code is String ? code : FeederApiException.unknown,
        statusCode: response.statusCode);
  }
}
