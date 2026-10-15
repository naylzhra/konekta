import '../../../core/location/user_location_provider.dart';
import 'feeder_api.dart';

/// Sends the on-duty driver's location to the gateway
abstract class FeederLocationReporter {
  Future<DateTime> report(UserLocation location);
  Future<void> goOffline();
}

class RestFeederLocationReporter implements FeederLocationReporter {
  RestFeederLocationReporter({required FeederApi api, required String token})
      : _api = api,
        _token = token;

  final FeederApi _api;
  final String _token;

  @override
  Future<DateTime> report(UserLocation location) => _api.reportPosition(
        _token,
        lat: location.lat,
        lng: location.lng,
        heading: location.headingDeg,
        accuracyM: location.accuracyM,
      );

  @override
  Future<void> goOffline() => _api.goOffline(_token);
}
