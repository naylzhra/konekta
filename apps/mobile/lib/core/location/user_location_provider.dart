import 'dart:async';
import 'package:geolocator/geolocator.dart';


abstract class UserLocationProvider {
  Future<LocationPermissionState> permissionState();
  Future<LocationPermissionState> requestPermission();
  Future<UserLocation?> getCurrent();
  Stream<UserLocation> stream();
}

enum LocationPermissionState { granted, denied, deniedForever, serviceDisabled }

class UserLocation {
  const UserLocation({required this.lat, required this.lng, this.accuracyM, this.headingDeg, required this.at});

  final double lat;
  final double lng;
  final double? accuracyM;

  /// Direction of travel, 0-360 clockwise from north; null when unknown.
  final double? headingDeg;
  final DateTime at;
}

typedef LocationRationale = Future<bool> Function();

class GeolocatorUserLocationProvider implements UserLocationProvider {
  GeolocatorUserLocationProvider({
    this.rationale,
    LocationSettings? settings,
    GeolocatorPlatform? platform,
  })  : _settings = settings ?? const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 10),
        _platform = platform ?? GeolocatorPlatform.instance;

  LocationRationale? rationale;

  final LocationSettings _settings;
  final GeolocatorPlatform _platform;

  @override
  Future<LocationPermissionState> permissionState() async {
    if (!await _platform.isLocationServiceEnabled()) return LocationPermissionState.serviceDisabled;
    return _map(await _platform.checkPermission());
  }

  @override
  Future<LocationPermissionState> requestPermission() async {
    final current = await permissionState();
    if (current != LocationPermissionState.denied) return current;
    final rationale = this.rationale;
    if (rationale != null && !await rationale()) return LocationPermissionState.denied;
    return _map(await _platform.requestPermission());
  }

  @override
  Future<UserLocation?> getCurrent() async {
    if (await permissionState() != LocationPermissionState.granted) return null;
    try {
      return _toLocation(await _platform.getCurrentPosition(locationSettings: _settings));
    } on Exception {
      return null;
    }
  }

  @override
  Stream<UserLocation> stream() => _platform.getPositionStream(locationSettings: _settings).map(_toLocation);

  static LocationPermissionState _map(LocationPermission permission) => switch (permission) {
        LocationPermission.always || LocationPermission.whileInUse => LocationPermissionState.granted,
        LocationPermission.deniedForever => LocationPermissionState.deniedForever,
        LocationPermission.denied || LocationPermission.unableToDetermine => LocationPermissionState.denied,
      };

  static UserLocation _toLocation(Position position) => UserLocation(
        lat: position.latitude,
        lng: position.longitude,
        accuracyM: position.accuracy,
        headingDeg: position.heading > 0 && position.heading < 360 ? position.heading : null,
        at: position.timestamp,
      );
}
