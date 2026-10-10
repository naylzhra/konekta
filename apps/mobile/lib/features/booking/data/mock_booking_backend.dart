import 'dart:async';
import 'dart:math';

import '../domain/booking_failure.dart';
import '../domain/booking_models.dart';
import '../domain/booking_state_machine.dart';
import 'booking_repository.dart';

/// In-memory stand-in for the gateway's booking API + WS events, for demos
/// and UI work without a backend. Enabled only by
/// `--dart-define=BOOKING_MOCK=true`; never used otherwise.
///
/// Statuses move only through [nextStatus] (the mirrored server table) on
/// timers, as the gateway's matching + BookingSimulator would. Stops and
/// fares are placeholders, not real halte or tariff data.
class MockBookingBackend implements BookingRepository, BookingRealtime {
  MockBookingBackend({
    this.scenario = MockBookingScenario.happyPath,
    this.step = const Duration(seconds: 4),
    this.latency = const Duration(milliseconds: 200),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  static const enabled = bool.fromEnvironment('BOOKING_MOCK');

  static MockBookingScenario scenarioFromEnvironment() => MockBookingScenario.values.firstWhere(
        (s) => s.wire == const String.fromEnvironment('BOOKING_MOCK_SCENARIO'),
        orElse: () => MockBookingScenario.happyPath,
      );

  final MockBookingScenario scenario;

  /// Delay between simulated server-side transitions.
  final Duration step;

  /// Simulated network round trip per call.
  final Duration latency;
  final DateTime Function() _clock;

  final _updates = StreamController<Booking>.broadcast();
  final _plans = <String, TripPlan>{};
  final _bookings = <String, Booking>{};
  final _idempotency = <String, (String planId, int seats, String bookingId)>{};
  final _consents = <Consent>[];
  final _timers = <Timer>[];
  int _nextId = 1;

  @override
  Stream<Booking> get bookingUpdates => _updates.stream;

  @override
  Stream<StopUpdate> get stopUpdates => const Stream.empty();

  @override
  Stream<bool> get connectivity => const Stream.empty();

  @override
  bool get isConnected => true;

  void dispose() {
    for (final timer in _timers) {
      timer.cancel();
    }
    _updates.close();
  }

  @override
  Future<List<TripPlan>> planTrip({required GeoPoint origin, required GeoPoint destination, int seats = 1}) async {
    await _latency();
    _requireConsent();
    final distanceM = _distanceM(origin, destination);
    if (scenario == MockBookingScenario.noRoute || distanceM < 300) {
      throw const BookingException(BookingFailureCode.noRoute, statusCode: 422);
    }
    final now = _clock();
    final pickup = _placeholderStop('Titik Jemput Contoh', StopType.virtualStop, origin, now);
    final dropoff = _placeholderStop('Halte Contoh', StopType.staticStop, destination, now);
    final rideS = distanceM / 6.0; // ~22 km/h
    final plan = TripPlan(
      id: _id('plan'),
      origin: origin,
      destination: destination,
      legs: [
        const TripLeg(mode: LegMode.walk, distanceM: 150, durationS: 120),
        TripLeg(mode: LegMode.feeder, distanceM: distanceM, durationS: rideS),
      ],
      fareEstimateIdr: (2000 + (distanceM / 1000 * 1000).round()) * seats,
      etaMinutes: ((120 + rideS) / 60).ceil(),
      pickupStop: pickup,
      dropoffStop: dropoff,
      corridorId: 'mock',
      nearestFeederEtaS: scenario == MockBookingScenario.noSupply ? null : 240,
      expiresAt: now.add(const Duration(minutes: 5)),
    );
    _plans[plan.id] = plan;
    return [plan];
  }

  @override
  Future<Booking> createBooking({required String tripPlanId, required String idempotencyKey, int seats = 1}) async {
    await _latency();
    _requireConsent();
    final previous = _idempotency[idempotencyKey];
    if (previous != null) {
      if (previous.$1 != tripPlanId || previous.$2 != seats) {
        throw const BookingException(BookingFailureCode.idempotencyKeyReused, statusCode: 409);
      }
      return _bookings[previous.$3]!;
    }
    final plan = _plans[tripPlanId];
    if (plan == null) throw const BookingException(BookingFailureCode.notFound, statusCode: 404);
    if (plan.isExpired(_clock())) throw const BookingException(BookingFailureCode.planExpired, statusCode: 410);
    if (_bookings.values.any((b) => b.isActive)) {
      throw const BookingException(BookingFailureCode.activeBookingExists, statusCode: 409);
    }
    final now = _clock();
    final booking = Booking(
      id: _id('booking'),
      status: BookingStatus.requested,
      tripPlanId: plan.id,
      seats: seats,
      fareEstimateIdr: plan.fareEstimateIdr,
      version: 1,
      createdAt: now,
      updatedAt: now,
    );
    _bookings[booking.id] = booking;
    _idempotency[idempotencyKey] = (tripPlanId, seats, booking.id);
    _runMatching(booking.id, plan);
    return booking;
  }

  @override
  Future<Booking> cancelBooking(String bookingId, {String? reason}) async {
    await _latency();
    final booking = _owned(bookingId);
    if (booking.status == BookingStatus.cancelled) return booking;
    return _apply(bookingId, BookingEvent.cancel, (b) => b._copy(cancelReason: reason));
  }

  @override
  Future<Booking> markBoarded(String bookingId) async {
    await _latency();
    final booking = _owned(bookingId);
    if (booking.status == BookingStatus.boarded) return booking;
    final boarded = _apply(bookingId, BookingEvent.passengerBoarded);
    _later(step * 2, () => _tryApply(bookingId, BookingEvent.driverArrivedDropoff));
    return boarded;
  }

  @override
  Future<Booking?> getActiveBooking() async {
    await _latency();
    for (final booking in _bookings.values) {
      if (booking.isActive) return booking;
    }
    return null;
  }

  @override
  Future<BookingPage> listBookings({String? cursor, int limit = 20}) async {
    await _latency();
    final all = _bookings.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final offset = cursor == null ? 0 : int.tryParse(cursor) ?? 0;
    final end = min(all.length, offset + limit);
    return BookingPage(
      items: offset >= all.length ? const [] : all.sublist(offset, end),
      nextCursor: end < all.length ? '$end' : null,
    );
  }

  @override
  Future<Consent> recordConsent({required bool granted}) async {
    await _latency();
    final consent = Consent(
      purpose: consentPurposeTripLocation,
      policyVersion: consentPolicyVersion,
      granted: granted,
      createdAt: _clock(),
    );
    _consents.add(consent);
    return consent;
  }

  @override
  Future<List<Consent>> listConsents() async {
    await _latency();
    return _consents.reversed.toList();
  }

  void _runMatching(String bookingId, TripPlan plan) {
    _later(step ~/ 4, () => _tryApply(bookingId, BookingEvent.startMatching));
    if (scenario == MockBookingScenario.noSupply) {
      _later(step, () => _tryApply(bookingId, BookingEvent.matchFailed));
      return;
    }
    _later(step, () {
      _tryApply(
        bookingId,
        BookingEvent.matchFound,
        (b) => b._copy(
          pickupStop: _snapshot(plan.pickupStop),
          dropoffStop: _snapshot(plan.dropoffStop),
          feederId: 'mock-feeder-1',
          etaToPickupS: 240,
        ),
      );
    });
    _later(step * 2, () => _tryApply(bookingId, BookingEvent.feederApproaching, (b) => b._copy(etaToPickupS: 60)));
  }

  /// Applies [event] if still valid; scheduled transitions lose to the
  /// passenger (e.g. cancelled while matching), as on the server.
  void _tryApply(String bookingId, BookingEvent event, [Booking Function(Booking)? change]) {
    final booking = _bookings[bookingId];
    if (booking != null && canApply(booking.status, event)) _apply(bookingId, event, change);
  }

  Booking _apply(String bookingId, BookingEvent event, [Booking Function(Booking)? change]) {
    final booking = _owned(bookingId);
    final status = nextStatus(booking.status, event);
    if (status == null) throw const BookingException(BookingFailureCode.invalidTransition, statusCode: 409);
    final changed = change == null ? booking : change(booking);
    final updated = changed._copy(status: status, version: booking.version + 1, updatedAt: _clock());
    _bookings[bookingId] = updated;
    if (!_updates.isClosed) _updates.add(updated);
    return updated;
  }

  Booking _owned(String bookingId) {
    final booking = _bookings[bookingId];
    if (booking == null) throw const BookingException(BookingFailureCode.notFound, statusCode: 404);
    return booking;
  }

  void _requireConsent() {
    final latest = _consents.isEmpty ? null : _consents.last;
    if (latest == null || !latest.granted || latest.policyVersion != consentPolicyVersion) {
      throw const BookingException(BookingFailureCode.consentRequired, statusCode: 403);
    }
  }

  void _later(Duration delay, void Function() action) => _timers.add(Timer(delay, action));

  Future<void> _latency() => Future<void>.delayed(latency);

  String _id(String prefix) => 'mock-$prefix-${_nextId++}';

  Stop _placeholderStop(String name, StopType type, GeoPoint near, DateTime now) => Stop(
        id: _id('stop'),
        type: type,
        name: name,
        location: near,
        corridorId: 'mock',
        validUntil: type == StopType.virtualStop ? now.add(const Duration(minutes: 20)) : null,
      );

  static StopSnapshot? _snapshot(Stop? stop) =>
      stop == null ? null : StopSnapshot(id: stop.id, type: stop.type, name: stop.name, location: stop.location);

  static double _distanceM(GeoPoint a, GeoPoint b) {
    const earthRadiusM = 6371000.0;
    double rad(double deg) => deg * pi / 180;
    final dLat = rad(b.lat - a.lat);
    final dLng = rad(b.lng - a.lng);
    final h = pow(sin(dLat / 2), 2) + cos(rad(a.lat)) * cos(rad(b.lat)) * pow(sin(dLng / 2), 2);
    return 2 * earthRadiusM * asin(sqrt(h));
  }
}

enum MockBookingScenario {
  happyPath('happy'),
  noSupply('no_supply'),
  noRoute('no_route');

  const MockBookingScenario(this.wire);

  final String wire;
}

extension on Booking {
  Booking _copy({
    BookingStatus? status,
    StopSnapshot? pickupStop,
    StopSnapshot? dropoffStop,
    String? feederId,
    int? etaToPickupS,
    String? cancelReason,
    int? version,
    DateTime? updatedAt,
  }) =>
      Booking(
        id: id,
        status: status ?? this.status,
        tripPlanId: tripPlanId,
        seats: seats,
        pickupStop: pickupStop ?? this.pickupStop,
        dropoffStop: dropoffStop ?? this.dropoffStop,
        feederId: feederId ?? this.feederId,
        fareEstimateIdr: fareEstimateIdr,
        cancellationFeeIdr: cancellationFeeIdr,
        etaToPickupS: etaToPickupS ?? this.etaToPickupS,
        cancelReason: cancelReason ?? this.cancelReason,
        version: version ?? this.version,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
