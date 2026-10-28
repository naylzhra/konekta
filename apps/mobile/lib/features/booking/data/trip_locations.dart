/// Where booking gets the trip's origin and destination from.
///
/// GPS supplies the initial origin. Named suggestions are real K1 stops;
/// passengers can also choose either endpoint directly on the map.
library;

import '../../../core/api/api_client.dart';
import '../../../core/location/user_location_provider.dart';
import '../../live_tracking/data/feeder_api.dart';
import '../../live_tracking/domain/feeder_models.dart';
import '../domain/booking_models.dart';

class TripPlace {
  const TripPlace({required this.id, required this.name, required this.location});

  final String id;
  final String name;
  final GeoPoint location;
}

abstract class TripLocations {
  /// True when the data is placeholder, so the UI can say so.
  bool get isPlaceholder;

  /// Device location, or null when denied/unavailable.
  Future<GeoPoint?> currentOrigin();

  /// Destinations matching [query] (all suggestions when empty).
  Future<List<TripPlace>> searchDestinations(String query);

  factory TripLocations.fromEnvironment({ApiClient? apiClient}) =>
      const String.fromEnvironment('BOOKING_LOCATIONS') == 'stub'
          ? const StubTripLocations()
          : LiveTripLocations(apiClient: apiClient ?? ApiClient());
}

class LiveTripLocations implements TripLocations {
  LiveTripLocations({required ApiClient apiClient, UserLocationProvider? location})
      : _feederApi = FeederApi(apiClient),
        _location = location ?? GeolocatorUserLocationProvider();

  final FeederApi _feederApi;
  final UserLocationProvider _location;
  Future<List<TripPlace>>? _places;

  @override
  bool get isPlaceholder => false;

  @override
  Future<GeoPoint?> currentOrigin() async {
    if (await _location.requestPermission() != LocationPermissionState.granted) return null;
    final fix = await _location.getCurrent();
    return fix == null ? null : GeoPoint(lat: fix.lat, lng: fix.lng);
  }

  Future<List<TripPlace>> _loadPlaces() async {
    final corridors = await _feederApi.listCorridors();
    final places = <TripPlace>[];
    for (final corridor in corridors.where((c) => !c.isDummy)) {
      for (final direction in RouteDirection.values) {
        final route = await _feederApi.routeStops(corridor.id, direction: direction);
        for (final stop in route.stops) {
          if (stop.lat == null || stop.lng == null) continue;
          places.add(TripPlace(
            id: '${corridor.id}-${direction.wire}-${stop.position}',
            name: '${stop.name} (${corridor.id})',
            location: GeoPoint(lat: stop.lat!, lng: stop.lng!),
          ));
        }
      }
    }
    return places;
  }

  @override
  Future<List<TripPlace>> searchDestinations(String query) async {
    final places = await (_places ??= _loadPlaces());
    final q = query.trim().toLowerCase();
    return [for (final place in places) if (q.isEmpty || place.name.toLowerCase().contains(q)) place];
  }
}

/// Explicit demo option (`BOOKING_LOCATIONS=stub`) for offline UI tests.
class StubTripLocations implements TripLocations {
  const StubTripLocations();

  static const origin = GeoPoint(lat: -6.9175, lng: 107.6191);

  static const places = [
    TripPlace(id: 'stub-1', name: 'Tujuan Contoh A', location: GeoPoint(lat: -6.8915, lng: 107.6107)),
    TripPlace(id: 'stub-2', name: 'Tujuan Contoh B', location: GeoPoint(lat: -6.9339, lng: 107.6044)),
    TripPlace(id: 'stub-3', name: 'Tujuan Contoh C', location: GeoPoint(lat: -6.9025, lng: 107.6186)),
    TripPlace(id: 'stub-4', name: 'Tujuan Contoh D', location: GeoPoint(lat: -6.8800, lng: 107.6350)),
  ];

  @override
  bool get isPlaceholder => true;

  @override
  Future<GeoPoint?> currentOrigin() async => origin;

  @override
  Future<List<TripPlace>> searchDestinations(String query) async {
    final q = query.trim().toLowerCase();
    return [for (final place in places) if (q.isEmpty || place.name.toLowerCase().contains(q)) place];
  }
}
