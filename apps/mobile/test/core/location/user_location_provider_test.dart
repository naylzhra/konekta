import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:konekta_mobile/core/location/user_location_provider.dart';

class _FakeGeolocator extends GeolocatorPlatform {
  bool serviceEnabled = true;
  LocationPermission permission = LocationPermission.denied;
  LocationPermission afterRequest = LocationPermission.whileInUse;
  int requests = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    requests++;
    return permission = afterRequest;
  }
}

void main() {
  late _FakeGeolocator platform;

  setUp(() => platform = _FakeGeolocator());

  test('maps permission and service states', () async {
    final provider = GeolocatorUserLocationProvider(platform: platform);
    expect(await provider.permissionState(), LocationPermissionState.denied);

    platform.permission = LocationPermission.always;
    expect(await provider.permissionState(), LocationPermissionState.granted);

    platform.permission = LocationPermission.deniedForever;
    expect(await provider.permissionState(), LocationPermissionState.deniedForever);

    platform.serviceEnabled = false;
    expect(await provider.permissionState(), LocationPermissionState.serviceDisabled);
  });

  test('shows the rationale before the OS prompt; declining skips the prompt', () async {
    var rationaleShown = 0;
    var accept = false;
    final provider = GeolocatorUserLocationProvider(platform: platform)
      ..rationale = () async {
        rationaleShown++;
        return accept;
      };

    expect(await provider.requestPermission(), LocationPermissionState.denied);
    expect((rationaleShown, platform.requests), (1, 0));

    accept = true;
    expect(await provider.requestPermission(), LocationPermissionState.granted);
    expect((rationaleShown, platform.requests), (2, 1));

    // Already granted: no rationale, no prompt.
    expect(await provider.requestPermission(), LocationPermissionState.granted);
    expect((rationaleShown, platform.requests), (2, 1));
  });

  test('getCurrent is null without permission', () async {
    final provider = GeolocatorUserLocationProvider(platform: platform);
    expect(await provider.getCurrent(), isNull);
  });
}
