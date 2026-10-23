import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:konekta_mobile/core/api/api_client.dart';
import 'package:konekta_mobile/core/location/user_location_provider.dart';
import 'package:konekta_mobile/features/live_tracking/data/feeder_api.dart';
import 'package:konekta_mobile/features/live_tracking/data/feeder_location_reporter.dart';
import 'package:konekta_mobile/features/live_tracking/domain/feeder_models.dart';
import 'package:konekta_mobile/features/live_tracking/state/driver_duty_controller.dart';

class _FakeLocation implements UserLocationProvider {
  LocationPermissionState permission = LocationPermissionState.granted;
  final fixes = StreamController<UserLocation>.broadcast();

  @override
  Future<LocationPermissionState> permissionState() async => permission;

  @override
  Future<LocationPermissionState> requestPermission() async => permission;

  @override
  Future<UserLocation?> getCurrent() async => null;

  @override
  Stream<UserLocation> stream() => fixes.stream;
}

class _FakeReporter implements FeederLocationReporter {
  final reported = <UserLocation>[];
  final directions = <RouteDirection?>[];
  int offlineCalls = 0;
  FeederApiException? nextError;

  @override
  Future<DateTime> report(UserLocation location, {RouteDirection? direction}) async {
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
    reported.add(location);
    directions.add(direction);
    return DateTime.utc(2026, 10, 15, 8);
  }

  @override
  Future<void> goOffline() async => offlineCalls++;
}

const _myFeeder = {'id': 'K1-01', 'number': 1, 'capacity': 8, 'corridor_id': 'K1', 'corridor_name': 'Koridor 1'};

FeederApi _api({int status = 200, Object body = _myFeeder}) => FeederApi(
      ApiClient(
        baseUrl: 'http://gateway',
        httpClient: MockClient((_) async => http.Response(jsonEncode(body), status)),
      ),
    );

UserLocation _fix({double lat = -6.9175, double lng = 107.6191}) =>
    UserLocation(lat: lat, lng: lng, accuracyM: 5, at: DateTime.utc(2026, 10, 15, 8));

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 10));

void main() {
  late _FakeLocation location;
  late _FakeReporter reporter;
  late DateTime now;

  DriverDutyController controller({FeederApi? api}) => DriverDutyController(
        api: api ?? _api(),
        token: 'tok',
        location: location,
        reporter: reporter,
        clock: () => now,
      );

  setUp(() {
    location = _FakeLocation();
    reporter = _FakeReporter();
    now = DateTime.utc(2026, 10, 15, 8);
  });

  test('loads the assigned feeder, or noFeeder when the account has none', () async {
    final duty = controller();
    await duty.load();
    expect(duty.status, DutyStatus.offDuty);
    expect(duty.feeder?.id, 'K1-01');

    final unassigned = controller(
      api: _api(status: 404, body: {'detail': {'code': 'no_feeder_assigned', 'message': 'x'}}),
    );
    await unassigned.load();
    expect(unassigned.status, DutyStatus.noFeeder);
  });

  test('denied permission keeps the driver off duty with the reason', () async {
    final duty = controller();
    await duty.load();
    location.permission = LocationPermissionState.deniedForever;

    await duty.startDuty();
    expect(duty.status, DutyStatus.offDuty);
    expect(duty.issue, DutyIssue.permissionDeniedForever);
  });

  test('reports the chosen direction and switches it right away', () async {
    final duty = controller();
    await duty.load();
    await duty.startDuty(direction: RouteDirection.backward);

    location.fixes.add(_fix());
    await _settle();
    duty.switchDirection();
    now = now.add(const Duration(seconds: 1)); // within the interval: a turn is sent anyway
    location.fixes.add(_fix(lat: -6.9176));
    await _settle();

    expect(reporter.directions, [RouteDirection.backward, RouteDirection.forward]);
    expect(duty.direction, RouteDirection.forward);
  });

  test('on duty: reports fixes, throttled by minReportInterval', () async {
    final duty = controller();
    await duty.load();
    await duty.startDuty();
    expect(duty.status, DutyStatus.onDuty);

    location.fixes.add(_fix());
    await _settle();
    now = now.add(const Duration(seconds: 1));
    location.fixes.add(_fix(lat: -6.9176)); // too soon
    await _settle();
    now = now.add(const Duration(seconds: 4));
    location.fixes.add(_fix(lat: -6.9177));
    await _settle();

    expect(reporter.reported.map((f) => f.lat), [-6.9175, -6.9177]);
    expect(duty.lastSentAt, DateTime.utc(2026, 10, 15, 8));
    expect(duty.lastLocation?.lat, -6.9177);
  });

  test('fixes outside the service area are not sent', () async {
    final duty = controller();
    await duty.load();
    await duty.startDuty();

    location.fixes.add(_fix(lat: -6.2, lng: 106.8)); // Jakarta
    await _settle();
    expect(reporter.reported, isEmpty);
    expect(duty.issue, DutyIssue.outsideServiceArea);
  });

  test('send failures surface as issues and the next fix retries', () async {
    final duty = controller();
    await duty.load();
    await duty.startDuty();

    reporter.nextError = const FeederApiException(FeederApiException.offline);
    location.fixes.add(_fix());
    await _settle();
    expect(duty.issue, DutyIssue.sendFailed);

    now = now.add(const Duration(seconds: 5));
    location.fixes.add(_fix());
    await _settle();
    expect(duty.issue, DutyIssue.none);
    expect(reporter.reported, hasLength(1));
  });

  test('expired session stops duty', () async {
    final duty = controller();
    await duty.load();
    await duty.startDuty();

    reporter.nextError = const FeederApiException(FeederApiException.unauthorized);
    location.fixes.add(_fix());
    await _settle();
    expect(duty.status, DutyStatus.offDuty);
    expect(duty.issue, DutyIssue.sessionExpired);
  });

  test('stopping duty stops reporting and takes the feeder offline', () async {
    final duty = controller();
    await duty.load();
    await duty.startDuty();
    await duty.stopDuty();

    expect(duty.status, DutyStatus.offDuty);
    expect(reporter.offlineCalls, 1);
    location.fixes.add(_fix());
    await _settle();
    expect(reporter.reported, isEmpty);
  });
}
