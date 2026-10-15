import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/location/user_location_provider.dart';
import '../data/feeder_api.dart';
import '../data/feeder_location_reporter.dart';
import '../domain/feeder_models.dart';
import '../domain/service_area.dart';

enum DutyStatus { loading, loadFailed, noFeeder, offDuty, starting, onDuty }

enum DutyIssue {
  none,
  permissionDenied,
  permissionDeniedForever,
  locationServiceDisabled,
  outsideServiceArea,
  weakGps,
  sendFailed,
  sessionExpired,
}

class DriverDutyController extends ChangeNotifier {
  DriverDutyController({
    required FeederApi api,
    required String token,
    required UserLocationProvider location,
    FeederLocationReporter? reporter,
    this.minReportInterval = const Duration(seconds: 4),
    DateTime Function()? clock,
  })  : _api = api,
        _token = token,
        _location = location,
        _reporter = reporter ?? RestFeederLocationReporter(api: api, token: token),
        _clock = clock ?? DateTime.now;

  final FeederApi _api;
  final String _token;
  final UserLocationProvider _location;
  final FeederLocationReporter _reporter;
  final DateTime Function() _clock;

  /// Fixes arriving sooner than this after the last attempt are not sent.
  final Duration minReportInterval;

  DutyStatus _status = DutyStatus.loading;
  DutyIssue _issue = DutyIssue.none;
  AssignedFeeder? _feeder;
  UserLocation? _lastLocation;
  DateTime? _lastSentAt;
  DateTime? _lastAttemptAt;
  bool _sending = false;
  bool _disposed = false;
  StreamSubscription<UserLocation>? _fixes;

  DutyStatus get status => _status;
  DutyIssue get issue => _issue;
  AssignedFeeder? get feeder => _feeder;
  UserLocation? get lastLocation => _lastLocation;
  DateTime? get lastSentAt => _lastSentAt;
  bool get isOnDuty => _status == DutyStatus.onDuty;

  Future<void> load() async {
    _set(status: DutyStatus.loading, issue: DutyIssue.none);
    try {
      _feeder = await _api.myFeeder(_token);
      _set(status: DutyStatus.offDuty);
    } on FeederApiException catch (e) {
      switch (e.code) {
        case FeederApiException.noFeederAssigned:
          _set(status: DutyStatus.noFeeder);
        case FeederApiException.unauthorized:
          _set(status: DutyStatus.loadFailed, issue: DutyIssue.sessionExpired);
        default:
          _set(status: DutyStatus.loadFailed, issue: DutyIssue.sendFailed);
      }
    }
  }

  Future<void> startDuty() async {
    if (_status != DutyStatus.offDuty) return;
    _set(status: DutyStatus.starting, issue: DutyIssue.none);

    final permission = await _location.requestPermission();
    if (_disposed) return;
    if (permission != LocationPermissionState.granted) {
      _set(status: DutyStatus.offDuty, issue: _permissionIssue(permission));
      return;
    }

    _lastSentAt = null;
    _lastAttemptAt = null;
    _fixes = _location.stream().listen(_onFix, onError: _onFixError);
    _set(status: DutyStatus.onDuty);
  }

  Future<void> stopDuty({DutyIssue issue = DutyIssue.none}) async {
    if (_status != DutyStatus.onDuty) return;
    await _fixes?.cancel();
    _fixes = null;
    _set(status: DutyStatus.offDuty, issue: issue);
    try {
      await _reporter.goOffline();
    } on FeederApiException {
      // Best effort: the gateway drops the feeder after its position TTL anyway.
    }
  }

  void _onFix(UserLocation fix) {
    _lastLocation = fix;
    final now = _clock();
    final due = _lastAttemptAt == null || now.difference(_lastAttemptAt!) >= minReportInterval;
    if (!ServiceArea.contains(fix.lat, fix.lng)) {
      _set(issue: DutyIssue.outsideServiceArea);
      return;
    }
    if (_sending || !due) {
      _notify(); // map still follows the driver
      return;
    }
    _lastAttemptAt = now;
    unawaited(_send(fix));
  }

  Future<void> _send(UserLocation fix) async {
    _sending = true;
    _notify();
    try {
      _lastSentAt = await _reporter.report(fix);
      _set(issue: DutyIssue.none);
    } on FeederApiException catch (e) {
      switch (e.code) {
        case FeederApiException.tooFrequent:
          break; // the next fix goes through
        case FeederApiException.inaccuratePosition:
          _set(issue: DutyIssue.weakGps);
        case FeederApiException.outsideServiceArea:
          _set(issue: DutyIssue.outsideServiceArea);
        case FeederApiException.unauthorized:
          await stopDuty(issue: DutyIssue.sessionExpired);
        case FeederApiException.noFeederAssigned:
          await stopDuty();
          _feeder = null;
          _set(status: DutyStatus.noFeeder);
        default:
          _set(issue: DutyIssue.sendFailed); // retried with the next fix
      }
    } finally {
      _sending = false;
      _notify();
    }
  }

  void _onFixError(Object error) {
    unawaited(stopDuty(issue: DutyIssue.locationServiceDisabled));
  }

  static DutyIssue _permissionIssue(LocationPermissionState state) => switch (state) {
        LocationPermissionState.deniedForever => DutyIssue.permissionDeniedForever,
        LocationPermissionState.serviceDisabled => DutyIssue.locationServiceDisabled,
        _ => DutyIssue.permissionDenied,
      };

  void _set({DutyStatus? status, DutyIssue? issue}) {
    if (status != null) _status = status;
    if (issue != null) _issue = issue;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_fixes != null) {
      unawaited(_fixes!.cancel());
      _fixes = null;
      unawaited(_reporter.goOffline().catchError((Object _) {}));
    }
    super.dispose();
  }
}
