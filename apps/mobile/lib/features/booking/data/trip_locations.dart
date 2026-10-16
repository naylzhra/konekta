/// Where booking gets the trip's origin and destination from.
///
/// Origin will come from live tracking's `UserLocationProvider` (DESIGN.md
/// §5.3), which owns the permission prompt; booking never requests location
/// itself. There is no geocoding/place search yet, so destinations come
/// from a placeholder list. Both are behind this interface so the real
/// implementations replace [StubTripLocations] without touching the UI.
library;

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

  /// `--dart-define=BOOKING_LOCATIONS=stub` is the default and, for now,
  /// the only implementation; the real one gets its own value here.
  factory TripLocations.fromEnvironment() => const StubTripLocations();
}

/// NOT real places: fixed points inside the gateway stub's Bandung service
/// area (services/gateway/app/bookings/clients.py) so plans succeed in
/// demos. Replace with UserLocationProvider + a place search.
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
