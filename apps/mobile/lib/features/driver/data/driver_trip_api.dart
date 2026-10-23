import 'package:latlong2/latlong.dart';

import '../../../core/api/api_client.dart';
import '../../../core/navigation/nav_instructions.dart';

enum StopPhase { pickup, dropoff }

/// A stop the driver must serve: passengers waiting there or riding to it.
class DriverTaskStop {
  const DriverTaskStop({
    required this.stopId,
    required this.name,
    required this.isVirtual,
    required this.phase,
    required this.seats,
    this.location,
  });

  factory DriverTaskStop.fromJson(Map<String, dynamic> json) {
    final lat = json['lat'] as num?;
    final lng = json['lng'] as num?;
    return DriverTaskStop(
      stopId: json['stop_id'] as String,
      name: json['name'] as String? ?? 'Halte',
      isVirtual: json['type'] == 'virtual',
      phase: json['phase'] == 'pickup' ? StopPhase.pickup : StopPhase.dropoff,
      seats: (json['seats'] as num?)?.toInt() ?? 0,
      location: lat == null || lng == null
          ? null
          : LatLng(lat.toDouble(), lng.toDouble()),
    );
  }

  final String stopId;
  final String name;
  final bool isVirtual;
  final StopPhase phase;
  final int seats;
  final LatLng? location;
}

/// A stop on the corridor the driver is heading to, with whoever is waiting
/// there or riding to it.
class NavStop {
  const NavStop({
    required this.stopId,
    required this.name,
    required this.isVirtual,
    this.position,
    required this.location,
    this.pickupSeats = 0,
    this.dropoffSeats = 0,
  });

  factory NavStop.fromJson(Map<String, dynamic> json) => NavStop(
        stopId: json['stop_id'] as String,
        name: json['name'] as String? ?? 'Halte',
        isVirtual: json['type'] == 'virtual',
        position: (json['position'] as num?)?.toInt(),
        location: LatLng((json['lat'] as num).toDouble(),
            (json['lng'] as num).toDouble()),
        pickupSeats: (json['pickup_seats'] as num?)?.toInt() ?? 0,
        dropoffSeats: (json['dropoff_seats'] as num?)?.toInt() ?? 0,
      );

  final String stopId;
  final String name;
  final bool isVirtual;

  /// Order on the corridor; null for virtual stops.
  final int? position;
  final LatLng location;
  final int pickupSeats;
  final int dropoffSeats;

  bool get hasPassengers => pickupSeats > 0 || dropoffSeats > 0;
}

class DriverNavigation {
  const DriverNavigation({
    required this.target,
    required this.upcoming,
    required this.distanceM,
    required this.durationS,
    required this.points,
    required this.steps,
  });

  factory DriverNavigation.fromJson(Map<String, dynamic> json) =>
      DriverNavigation(
        target: NavStop.fromJson(json['target'] as Map<String, dynamic>),
        upcoming: [
          for (final u in json['upcoming'] as List<dynamic>)
            NavStop.fromJson(u as Map<String, dynamic>),
        ],
        distanceM: (json['distance_m'] as num).toDouble(),
        durationS: (json['duration_s'] as num).toDouble(),
        points: [
          for (final p in json['points'] as List<dynamic>)
            LatLng(((p as Map<String, dynamic>)['lat'] as num).toDouble(),
                (p['lng'] as num).toDouble()),
        ],
        steps: [
          for (final s in json['steps'] as List<dynamic>)
            NavStep.fromJson(s as Map<String, dynamic>),
        ],
      );

  final NavStop target;

  /// The next few stops after [target], in driving order.
  final List<NavStop> upcoming;
  final double distanceM;
  final double durationS;
  final List<LatLng> points;
  final List<NavStep> steps;
}

class DriverTripException implements Exception {
  const DriverTripException(this.statusCode);

  /// Null when the gateway could not be reached.
  final int? statusCode;
}

class DriverTripApi {
  DriverTripApi(this._api, this._token);

  final ApiClient _api;
  final String _token;

  Future<List<DriverTaskStop>> stops() async {
    final body = await _get('/driver/stops') as Map<String, dynamic>;
    return [
      for (final item in body['items'] as List<dynamic>)
        DriverTaskStop.fromJson(item as Map<String, dynamic>),
    ];
  }

  /// Road route to [stopId], or to the next stop ahead on the corridor when
  /// null. Returns null when the corridor has no stops to navigate to.
  Future<DriverNavigation?> navigation(LatLng from, {String? stopId}) async {
    try {
      final body = await _get('/driver/stops/navigation', query: {
        'lat': '${from.latitude}',
        'lng': '${from.longitude}',
        if (stopId != null) 'stop_id': stopId,
      });
      return DriverNavigation.fromJson(body as Map<String, dynamic>);
    } on DriverTripException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  Future<void> markArrived(String stopId, String feederId) =>
      _post('/driver/stops/$stopId/arrived', {'feeder_id': feederId});

  Future<void> markDeparted(String stopId, String feederId) =>
      _post('/driver/stops/$stopId/departed', {'feeder_id': feederId});

  Future<Object?> _get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<void> _post(String path, Object body) => _send('POST', path, body: body);

  Future<Object?> _send(String method, String path,
      {Map<String, String>? query, Object? body}) async {
    final ApiResponse response;
    try {
      response = await _api.send(method, path,
          token: _token, query: query, body: body);
    } on ApiTransportException {
      throw const DriverTripException(null);
    }
    if (!response.isSuccess) throw DriverTripException(response.statusCode);
    return response.body;
  }
}
