library;

/// Which way a corridor is travelled (ROUTES.md): forward runs the route list
/// from stop 1, backward is the return route with its own stops.
enum RouteDirection {
  forward('forward'),
  backward('backward');

  const RouteDirection(this.wire);

  final String wire;

  RouteDirection get reversed =>
      this == forward ? backward : forward;

  static RouteDirection? fromWire(String? wire) => switch (wire) {
        'forward' => forward,
        'backward' => backward,
        _ => null,
      };
}

class FeederOption {
  const FeederOption(
      {required this.id,
      required this.number,
      required this.capacity,
      required this.available});

  factory FeederOption.fromJson(Map<String, dynamic> json) => FeederOption(
        id: json['id'] as String,
        number: json['number'] as int,
        capacity: json['capacity'] as int,
        available: json['available'] as bool,
      );

  final String id;
  final int number;
  final int capacity;

  /// False once another driver registered with this feeder.
  final bool available;
}

class CorridorOption {
  const CorridorOption(
      {required this.id, required this.name, required this.feeders, this.isDummy = false, this.routeCode});

  factory CorridorOption.fromJson(Map<String, dynamic> json) => CorridorOption(
        id: json['id'] as String,
        name: json['name'] as String,
        isDummy: json['is_dummy'] as bool? ?? false,
        routeCode: json['route_code'] as String?,
        feeders: [
          for (final feeder in json['feeders'] as List<dynamic>)
            FeederOption.fromJson(feeder as Map<String, dynamic>),
        ],
      );

  final String id;
  final String name;
  final bool isDummy;
  final List<FeederOption> feeders;

  /// Corridors sharing a code are one route to passengers (e.g. FD-1).
  final String? routeCode;

  List<FeederOption> get availableFeeders =>
      feeders.where((f) => f.available).toList();
}

/// A route as passengers see it: the corridors sharing a route code (or a
/// lone corridor without one), listed once under that code.
class TransitRoute {
  const TransitRoute({required this.id, required this.corridors});

  /// The route code, else the lone corridor's id.
  final String id;
  final List<CorridorOption> corridors;

  /// The corridor whose line and stops stand for the route: the first one
  /// with real geometry.
  CorridorOption get primary => corridors.firstWhere((c) => !c.isDummy, orElse: () => corridors.first);
  String get name => primary.name;
  bool get isDummy => corridors.every((c) => c.isDummy);
  Set<String> get corridorIds => {for (final corridor in corridors) corridor.id};
}

class CorridorRouteStop {
  const CorridorRouteStop({required this.position, required this.name, this.lat, this.lng});

  factory CorridorRouteStop.fromJson(Map<String, dynamic> json) =>
      CorridorRouteStop(
        position: json['position'] as int,
        name: json['name'] as String,
        lat: (json['lat'] as num?)?.toDouble(),
        lng: (json['lng'] as num?)?.toDouble(),
      );

  final int position;
  final String name;
  final double? lat;
  final double? lng;
}

class CorridorRoute {
  const CorridorRoute({
    required this.id,
    required this.name,
    required this.stops,
    this.isDummy = false,
    this.operatingHours,
    this.operatingDays,
    this.fareFromIdr,
  });

  factory CorridorRoute.fromJson(Map<String, dynamic> json) => CorridorRoute(
        id: json['id'] as String,
        name: json['name'] as String,
        isDummy: json['is_dummy'] as bool? ?? false,
        operatingHours: json['operating_hours'] as String?,
        operatingDays: json['operating_days'] as String?,
        fareFromIdr: json['fare_from_idr'] as int?,
        stops: [
          for (final item in json['items'] as List<dynamic>)
            CorridorRouteStop.fromJson(item as Map<String, dynamic>),
        ],
      );

  final String id;
  final String name;
  final bool isDummy;
  final List<CorridorRouteStop> stops;

  /// Service info for the route page; null until set on the server.
  final String? operatingHours;
  final String? operatingDays;
  final int? fareFromIdr;
}

/// A feeder due at a route stop (`GET /corridors/{id}/arrivals`).
class StopArrival {
  const StopArrival({required this.feederId, required this.etaS, required this.occupancy, required this.capacity});

  factory StopArrival.fromJson(Map<String, dynamic> json) => StopArrival(
        feederId: json['feeder_id'] as String,
        etaS: json['eta_s'] as int,
        occupancy: json['occupancy'] as int,
        capacity: json['capacity'] as int,
      );

  final String feederId;

  /// Server estimate from the distance left along the route.
  final int etaS;
  final int occupancy;
  final int capacity;
}

/// Feeders due at one route stop, soonest first.
class StopArrivals {
  const StopArrivals({required this.position, required this.name, required this.arrivals});

  factory StopArrivals.fromJson(Map<String, dynamic> json) => StopArrivals(
        position: json['position'] as int,
        name: json['name'] as String,
        arrivals: [
          for (final item in json['arrivals'] as List<dynamic>)
            StopArrival.fromJson(item as Map<String, dynamic>),
        ],
      );

  final int position;
  final String name;
  final List<StopArrival> arrivals;
}

class AssignedFeeder {
  const AssignedFeeder({
    required this.id,
    required this.number,
    required this.capacity,
    required this.corridorId,
    required this.corridorName,
  });

  factory AssignedFeeder.fromJson(Map<String, dynamic> json) => AssignedFeeder(
        id: json['id'] as String,
        number: json['number'] as int,
        capacity: json['capacity'] as int,
        corridorId: json['corridor_id'] as String,
        corridorName: json['corridor_name'] as String,
      );

  final String id;
  final int number;
  final int capacity;
  final String corridorId;
  final String corridorName;
}

class FeederPosition {
  const FeederPosition({
    required this.feederId,
    required this.lat,
    required this.lng,
    this.heading,
    required this.occupancy,
    this.capacity,
    this.corridorId,
    required this.updatedAt,
  });

  factory FeederPosition.fromJson(Map<String, dynamic> json) => FeederPosition(
        feederId: json['feeder_id'] as String,
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        heading: (json['heading'] as num?)?.toDouble(),
        occupancy: json['occupancy'] as int,
        capacity: json['capacity'] as int?,
        corridorId: json['corridor_id'] as String?,
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  final String feederId;
  final double lat;
  final double lng;
  final double? heading;
  final int occupancy;

  /// Null from gateways older than the corridor feed.
  final int? capacity;
  final String? corridorId;
  final DateTime updatedAt;

  bool get isFull => capacity != null && occupancy >= capacity!;
}
