import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/location/user_location_provider.dart';
import '../../../core/websocket/ws_client.dart';
import '../data/feeder_position_stream.dart';
import '../domain/feeder_models.dart';

class ActiveTrip {
  const ActiveTrip({this.feederId, this.pickup, this.pickupName, this.onBoard = false});

  final String? feederId;
  final LatLng? pickup;
  final String? pickupName;
  final bool onBoard;

  @override
  bool operator ==(Object other) =>
      other is ActiveTrip &&
      other.feederId == feederId &&
      other.pickup == pickup &&
      other.pickupName == pickupName &&
      other.onBoard == onBoard;

  @override
  int get hashCode => Object.hash(feederId, pickup, pickupName, onBoard);
}

enum FeederTrackingStatus {
  /// No active trip.
  none,

  /// Active trip, no feeder assigned yet.
  searching,

  /// Subscribed, no position received yet.
  waiting,
  live,

  /// No position for [PassengerMapController.staleAfter]: the feeder is
  /// probably offline (its gateway entry expires after the same 30 s).
  stale,
}

class PassengerMapController extends ChangeNotifier {
  PassengerMapController({
    required ValueListenable<ActiveTrip?> trip,
    required FeederPositionStream positions,
    required UserLocationProvider location,
    Stream<WsConnectionState>? connection,
    WsConnectionState initialConnection = WsConnectionState.connected,
    DateTime Function()? clock,
    Duration staleCheckInterval = const Duration(seconds: 5),
  })  : _trip = trip,
        _positions = positions,
        _location = location,
        _connection = connection,
        _connectionState = initialConnection,
        _clock = clock ?? DateTime.now,
        _staleCheckInterval = staleCheckInterval;

  /// Same as the gateway's position TTL.
  static const staleAfter = Duration(seconds: 30);

  final ValueListenable<ActiveTrip?> _trip;
  final FeederPositionStream _positions;
  final UserLocationProvider _location;
  final Stream<WsConnectionState>? _connection;
  final DateTime Function() _clock;
  final Duration _staleCheckInterval;

  StreamSubscription<FeederPosition>? _feederSubscription;
  StreamSubscription<UserLocation>? _locationSubscription;
  StreamSubscription<WsConnectionState>? _connectionSubscription;
  Timer? _staleTimer;
  bool _disposed = false;

  String? _subscribedFeederId;
  FeederPosition? _feeder;
  DateTime? _lastHeardAt;
  bool _stale = false;

  LocationPermissionState? _permission;
  UserLocation? _myLocation;

  WsConnectionState _connectionState;

  ActiveTrip? get trip => _trip.value;
  FeederPosition? get feeder => _feeder;
  LocationPermissionState? get permission => _permission;
  UserLocation? get myLocation => _myLocation;
  bool get isReconnecting => _connectionState != WsConnectionState.connected;

  FeederTrackingStatus get status {
    final trip = _trip.value;
    if (trip == null) return FeederTrackingStatus.none;
    if (trip.feederId == null) return FeederTrackingStatus.searching;
    if (_stale) return FeederTrackingStatus.stale;
    return _feeder == null ? FeederTrackingStatus.waiting : FeederTrackingStatus.live;
  }

  /// Meters from the feeder to the pickup stop, while both are known and
  /// the passenger isn't on board yet.
  double? get feederToPickupM {
    final feeder = _feeder;
    final trip = _trip.value;
    final pickup = trip?.pickup;
    if (feeder == null || pickup == null || trip!.onBoard) return null;
    return const Distance().as(LengthUnit.Meter, LatLng(feeder.lat, feeder.lng), pickup);
  }

  /// Starts following the trip. Shows the passenger's own location only if
  /// permission was already granted; never prompts (see [enableMyLocation]).
  Future<void> start() async {
    _trip.addListener(_syncFeeder);
    _connectionSubscription = _connection?.listen((state) {
      _connectionState = state;
      _notify();
    });
    _syncFeeder();
    _permission = await _location.permissionState();
    if (_disposed) return;
    if (_permission == LocationPermissionState.granted) _followMyLocation();
    _notify();
  }

  /// Asks for location permission (with the provider's rationale) and
  /// starts showing the passenger's position. Location stays on the device.
  Future<void> enableMyLocation() async {
    _permission = await _location.requestPermission();
    if (_disposed) return;
    if (_permission == LocationPermissionState.granted) _followMyLocation();
    _notify();
  }

  /// Re-reads permission, e.g. after returning from system settings.
  Future<void> refreshPermission() async {
    _permission = await _location.permissionState();
    if (_disposed) return;
    if (_permission == LocationPermissionState.granted) {
      _followMyLocation();
    } else {
      _stopMyLocation();
    }
    _notify();
  }

  void _followMyLocation() {
    if (_locationSubscription != null) return;
    _location.getCurrent().then((fix) {
      if (fix == null || _disposed || _myLocation != null) return;
      _myLocation = fix;
      _notify();
    });
    _locationSubscription = _location.stream().listen(
      (fix) {
        _myLocation = fix;
        _notify();
      },
      // Permission revoked or GPS switched off mid-stream.
      onError: (Object _) => refreshPermission(),
    );
  }

  void _stopMyLocation() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
    _myLocation = null;
  }

  void _syncFeeder() {
    final feederId = _trip.value?.feederId;
    if (feederId != _subscribedFeederId) {
      _feederSubscription?.cancel();
      _feederSubscription = null;
      _staleTimer?.cancel();
      _staleTimer = null;
      _feeder = null;
      _stale = false;
      _subscribedFeederId = feederId;
      if (feederId != null) {
        _lastHeardAt = _clock();
        _feederSubscription = _positions.subscribe(feederId).listen(_onFeederPosition);
        _staleTimer = Timer.periodic(_staleCheckInterval, (_) => _checkStale());
      }
    }
    _notify();
  }

  void _onFeederPosition(FeederPosition position) {
    _feeder = position;
    _lastHeardAt = _clock();
    _stale = false;
    _notify();
  }

  void _checkStale() {
    final heard = _lastHeardAt;
    final stale = heard != null && _clock().difference(heard) >= staleAfter;
    if (stale == _stale) return;
    _stale = stale;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _trip.removeListener(_syncFeeder);
    _feederSubscription?.cancel();
    _locationSubscription?.cancel();
    _connectionSubscription?.cancel();
    _staleTimer?.cancel();
    super.dispose();
  }
}
