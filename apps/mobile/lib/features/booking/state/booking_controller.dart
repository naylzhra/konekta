import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../data/booking_repository.dart';
import '../domain/booking_failure.dart';
import '../domain/booking_models.dart';

enum PlanningStatus { idle, loading, ready, failed }

enum ConsentState { unknown, granted, required }

/// Passenger booking state for Home and Trips (DESIGN.md §1, §5.1, §7).
///
/// The UI never sets a booking status: it calls an action, and the only
/// way [current] changes is a server snapshot (REST response, WS
/// `booking.updated`, or resync) going through [_accept], which drops
/// anything not newer than what was already seen for that booking.
class BookingController extends ChangeNotifier {
  BookingController({
    required BookingRepository repository,
    required BookingRealtime realtime,
    String Function()? newIdempotencyKey,
  })  : _repository = repository,
        _realtime = realtime,
        _newIdempotencyKey = newIdempotencyKey ?? _randomKey;

  final BookingRepository _repository;
  final BookingRealtime _realtime;
  final String Function() _newIdempotencyKey;

  final _subscriptions = <StreamSubscription<Object?>>[];
  final _seenVersions = <String, int>{};
  bool _disposed = false;

  Booking? _current;
  bool _online = false;
  bool _syncing = false;
  BookingException? _syncError;
  Future<void>? _resyncInFlight;

  ConsentState _consent = ConsentState.unknown;

  PlanningStatus _planning = PlanningStatus.idle;
  List<TripPlan> _plans = const [];
  BookingException? _planError;
  int _planRequest = 0;

  Future<Booking?>? _confirmInFlight;
  ({String planId, int seats, String key})? _pendingConfirm;
  bool _cancelling = false;
  bool _boarding = false;
  BookingException? _actionError;

  StopUpdate? _pickupStopUpdate;

  /// The booking being tracked: the active one, or one that just ended
  /// (kept so the UI can show COMPLETED / FAILED / NO_SHOW etc. until
  /// [dismissFinished]).
  Booking? get current => _current;
  bool get hasActiveBooking => _current?.isActive ?? false;

  // Mirrored validator (domain/booking_state_machine.dart) + in-flight guards.
  bool get canCancel => (_current?.canCancel ?? false) && !_cancelling && !_boarding;
  bool get canBoard => (_current?.canBoard ?? false) && !_cancelling && !_boarding;

  /// Realtime channel connected; false means offline/reconnecting.
  bool get isOnline => _online;
  bool get isSyncing => _syncing;
  BookingException? get syncError => _syncError;

  ConsentState get consent => _consent;

  PlanningStatus get planning => _planning;
  List<TripPlan> get plans => _plans;
  BookingException? get planError => _planError;

  bool get isConfirming => _confirmInFlight != null;
  bool get isCancelling => _cancelling;
  bool get isBoarding => _boarding;
  BookingException? get actionError => _actionError;

  /// Latest `stop.updated` for the current booking's pickup stop, i.e. the
  /// virtual stop moved after confirmation (the snapshot keeps the old one).
  StopUpdate? get pickupStopUpdate {
    final update = _pickupStopUpdate;
    final stopId = _current?.pickupStop?.id;
    return update != null && update.stopId == stopId ? update : null;
  }

  /// Subscribes to realtime events and loads current state. Call once.
  Future<void> start() async {
    _online = _realtime.isConnected;
    _subscriptions
      ..add(_realtime.bookingUpdates.listen(_onRemoteUpdate))
      ..add(_realtime.stopUpdates.listen(_onStopUpdate))
      ..add(_realtime.connectivity.listen(_onConnectivity));
    await Future.wait([resync(), checkConsent()]);
  }

  /// `GET /bookings/active` and reconcile. Concurrent calls share one request.
  Future<void> resync() => _resyncInFlight ??= _resync().whenComplete(() => _resyncInFlight = null);

  Future<void> _resync() async {
    _syncing = true;
    _notify();
    try {
      final active = await _repository.getActiveBooking();
      if (active != null) {
        _accept(active);
      } else if (_current != null && _current!.isActive) {
        // It ended while we weren't listening; fetch its final state.
        await _reconcileEnded(_current!.id);
      }
      _syncError = null;
    } on BookingException catch (e) {
      _syncError = e; // keep showing the last known state
    } finally {
      _syncing = false;
      _notify();
    }
  }

  Future<void> _reconcileEnded(String bookingId) async {
    final page = await _repository.listBookings(limit: 10);
    for (final booking in page.items) {
      if (booking.id == bookingId) {
        _accept(booking);
        return;
      }
    }
    // Gone from history too (e.g. retention deletion): stop tracking it.
    if (_current?.id == bookingId) _current = null;
  }

  Future<void> checkConsent() async {
    try {
      final consents = await _repository.listConsents();
      final latest = consents.where((c) => c.purpose == consentPurposeTripLocation).fold<Consent?>(
            null,
            (best, c) => best == null || c.createdAt.isAfter(best.createdAt) ? c : best,
          );
      _consent = latest != null && latest.granted && latest.policyVersion == consentPolicyVersion
          ? ConsentState.granted
          : ConsentState.required;
    } on BookingException {
      // stays unknown; the gateway still enforces consent on plan/booking
    }
    _notify();
  }

  Future<void> setConsent({required bool granted}) async {
    try {
      await _repository.recordConsent(granted: granted);
      _consent = granted ? ConsentState.granted : ConsentState.required;
      _actionError = null;
    } on BookingException catch (e) {
      _actionError = e;
    }
    _notify();
  }

  Future<void> planTrip({required GeoPoint origin, required GeoPoint destination, int seats = 1}) async {
    final request = ++_planRequest;
    _planning = PlanningStatus.loading;
    _plans = const [];
    _planError = null;
    _notify();
    try {
      final plans = await _repository.planTrip(origin: origin, destination: destination, seats: seats);
      if (request != _planRequest) return; // superseded by a newer search
      _plans = plans;
      _planning = PlanningStatus.ready;
    } on BookingException catch (e) {
      if (request != _planRequest) return;
      _planError = e;
      _planning = PlanningStatus.failed;
      if (e.code == BookingFailureCode.consentRequired) _consent = ConsentState.required;
    }
    _notify();
  }

  void clearPlans() {
    _planRequest++;
    _planning = PlanningStatus.idle;
    _plans = const [];
    _planError = null;
    _notify();
  }

  /// Books [plan]. A second tap while a request is in flight returns the
  /// same Future. A retry after a transient failure (offline/timeout)
  /// reuses the Idempotency-Key, so the server returns the booking it may
  /// already have created instead of creating another.
  Future<Booking?> confirm(TripPlan plan, {int seats = 1}) {
    final inFlight = _confirmInFlight;
    if (inFlight != null) return inFlight;
    final future = _confirm(plan, seats).whenComplete(() {
      _confirmInFlight = null;
      _notify();
    });
    _confirmInFlight = future;
    _notify();
    return future;
  }

  Future<Booking?> _confirm(TripPlan plan, int seats) async {
    _actionError = null;
    if (hasActiveBooking) {
      _actionError = const BookingException(BookingFailureCode.activeBookingExists);
      return null;
    }
    final pending = _pendingConfirm;
    final key = pending != null && pending.planId == plan.id && pending.seats == seats
        ? pending.key
        : _newIdempotencyKey();
    _pendingConfirm = (planId: plan.id, seats: seats, key: key);
    try {
      final booking = await _repository.createBooking(tripPlanId: plan.id, idempotencyKey: key, seats: seats);
      _accept(booking);
      clearPlans();
      return booking;
    } on BookingException catch (e) {
      if (!e.code.isTransient) _pendingConfirm = null;
      switch (e.code) {
        case BookingFailureCode.planExpired:
          _expirePlans();
        case BookingFailureCode.consentRequired:
          _consent = ConsentState.required;
          _actionError = e;
        case BookingFailureCode.activeBookingExists:
          _actionError = e;
          unawaited(resync());
        default:
          _actionError = e;
      }
      return null;
    }
  }

  void _expirePlans() {
    _pendingConfirm = null;
    _plans = const [];
    _planning = PlanningStatus.failed;
    _planError = const BookingException(BookingFailureCode.planExpired);
    _actionError = _planError;
  }

  Future<void> cancel({String? reason}) async {
    final booking = _current;
    if (booking == null || !canCancel) return;
    _cancelling = true;
    _actionError = null;
    _notify();
    try {
      _accept(await _repository.cancelBooking(booking.id, reason: reason));
    } on BookingException catch (e) {
      _onActionFailed(e);
    } finally {
      _cancelling = false;
      _notify();
    }
  }

  Future<void> markBoarded() async {
    final booking = _current;
    if (booking == null || !canBoard) return;
    _boarding = true;
    _actionError = null;
    _notify();
    try {
      _accept(await _repository.markBoarded(booking.id));
    } on BookingException catch (e) {
      _onActionFailed(e);
    } finally {
      _boarding = false;
      _notify();
    }
  }

  void _onActionFailed(BookingException e) {
    _actionError = e;
    // Our view of the booking is stale (e.g. the driver already departed):
    // the server state wins.
    if (e.code == BookingFailureCode.invalidTransition ||
        e.code == BookingFailureCode.concurrentUpdate ||
        e.code == BookingFailureCode.notFound) {
      unawaited(resync());
    }
  }

  /// Stop showing a booking that has ended.
  void dismissFinished() {
    if (_current == null || _current!.isActive) return;
    _current = null;
    _pickupStopUpdate = null;
    _notify();
  }

  void clearActionError() {
    if (_actionError == null) return;
    _actionError = null;
    _notify();
  }

  void _onRemoteUpdate(Booking incoming) {
    final current = _current;
    if (current != null && current.id != incoming.id) {
      // At most one active booking per user. Late events for an older
      // booking are ignored; a different *active* booking means our view
      // is stale (e.g. booked from another device): ask the server.
      if (incoming.isActive && current.isActive) {
        unawaited(resync());
        return;
      }
      if (current.isActive || !incoming.isActive) return;
    }
    if (current == null && !incoming.isActive) {
      // An ended booking we weren't tracking; history picks it up.
      _recordVersion(incoming);
      return;
    }
    if (_accept(incoming)) _notify();
  }

  void _onStopUpdate(StopUpdate update) {
    if (update.stopId != _current?.pickupStop?.id) return;
    _pickupStopUpdate = update;
    _notify();
  }

  void _onConnectivity(bool online) {
    _online = online;
    _notify();
    if (online) unawaited(resync()); // events sent while offline are lost
  }

  /// Applies a server snapshot unless its `version` is not newer than one
  /// already seen for that booking: drops duplicate and out-of-order events
  /// (DESIGN.md §5.1), including late ones for a booking no longer shown.
  bool _accept(Booking incoming) {
    final seen = _seenVersions[incoming.id];
    if (seen != null && incoming.version <= seen) return false;
    _recordVersion(incoming);
    if (_current?.id != incoming.id) _pickupStopUpdate = null;
    _current = incoming;
    if (incoming.isActive) _pendingConfirm = null;
    return true;
  }

  void _recordVersion(Booking booking) {
    final seen = _seenVersions[booking.id];
    if (seen == null || booking.version > seen) _seenVersions[booking.id] = booking.version;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  static String _randomKey() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }
}
