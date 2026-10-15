import 'dart:async';

import 'package:konekta_mobile/features/booking/data/booking_repository.dart';
import 'package:konekta_mobile/features/booking/domain/booking_failure.dart';
import 'package:konekta_mobile/features/booking/domain/booking_models.dart';
import 'package:konekta_mobile/features/booking/domain/booking_state_machine.dart';

final _t0 = DateTime.utc(2026, 10, 10, 8);

Booking booking({
  String id = 'b1',
  BookingStatus status = BookingStatus.confirmed,
  int version = 1,
}) =>
    Booking(
      id: id,
      status: status,
      seats: 1,
      fareEstimateIdr: 5000,
      version: version,
      createdAt: _t0,
      updatedAt: _t0.add(Duration(seconds: version)),
      pickupStop: const StopSnapshot(
        id: 'stop-1',
        type: StopType.virtualStop,
        name: 'Titik Jemput',
        location: GeoPoint(lat: -6.9, lng: 107.6),
      ),
    );

TripPlan plan({String id = 'plan-1', DateTime? expiresAt}) => TripPlan(
      id: id,
      origin: const GeoPoint(lat: -6.90, lng: 107.60),
      destination: const GeoPoint(lat: -6.92, lng: 107.62),
      legs: const [TripLeg(mode: LegMode.feeder, distanceM: 3000, durationS: 600)],
      fareEstimateIdr: 5000,
      etaMinutes: 12,
      expiresAt: expiresAt ?? _t0.add(const Duration(minutes: 5)),
    );

/// Scriptable repository: set the `on*` handlers per test; records calls.
class FakeBookingRepository implements BookingRepository {
  Future<Booking?> Function() onGetActive = () async => null;
  Future<BookingPage> Function(String? cursor) onList = (_) async => const BookingPage(items: []);
  Future<Booking> Function(String planId, String key) onCreate =
      (_, __) async => booking(status: BookingStatus.requested);
  Future<Booking> Function(String id) onCancel = (id) async => booking(id: id, status: BookingStatus.cancelled, version: 9);
  Future<Booking> Function(String id) onBoarded = (id) async => booking(id: id, status: BookingStatus.boarded, version: 9);
  Future<List<TripPlan>> Function() onPlan = () async => [plan()];
  List<Consent> consents = [];

  int getActiveCalls = 0;
  int cancelCalls = 0;
  int boardedCalls = 0;
  final createKeys = <String>[];
  final listCursors = <String?>[];

  @override
  Future<Booking?> getActiveBooking() {
    getActiveCalls++;
    return onGetActive();
  }

  @override
  Future<BookingPage> listBookings({String? cursor, int limit = 20}) {
    listCursors.add(cursor);
    return onList(cursor);
  }

  @override
  Future<Booking> createBooking({required String tripPlanId, required String idempotencyKey, int seats = 1}) {
    createKeys.add(idempotencyKey);
    return onCreate(tripPlanId, idempotencyKey);
  }

  @override
  Future<Booking> cancelBooking(String bookingId, {String? reason}) {
    cancelCalls++;
    return onCancel(bookingId);
  }

  @override
  Future<Booking> markBoarded(String bookingId) {
    boardedCalls++;
    return onBoarded(bookingId);
  }

  @override
  Future<List<TripPlan>> planTrip({required GeoPoint origin, required GeoPoint destination, int seats = 1}) =>
      onPlan();

  @override
  Future<Consent> recordConsent({required bool granted}) async {
    final consent = Consent(
      purpose: consentPurposeTripLocation,
      policyVersion: consentPolicyVersion,
      granted: granted,
      createdAt: DateTime.now(),
    );
    consents.add(consent);
    return consent;
  }

  @override
  Future<List<Consent>> listConsents() async => consents;
}

class FakeBookingRealtime implements BookingRealtime {
  final updates = StreamController<Booking>.broadcast(sync: true);
  final stops = StreamController<StopUpdate>.broadcast(sync: true);
  final connection = StreamController<bool>.broadcast(sync: true);

  @override
  bool isConnected = true;

  @override
  Stream<Booking> get bookingUpdates => updates.stream;

  @override
  Stream<StopUpdate> get stopUpdates => stops.stream;

  @override
  Stream<bool> get connectivity => connection.stream;
}

BookingException failure(BookingFailureCode code) => BookingException(code);
