/// Booking data interfaces. Real implementations talk to the gateway
/// (ApiBookingRepository over ApiClient, WsBookingRealtime over WsClient);
/// MockBookingBackend implements both for demos without a backend
/// (`--dart-define=BOOKING_MOCK=true`).
library;

import '../domain/booking_models.dart';

/// All methods throw BookingException on failure.
abstract class BookingRepository {
  /// `POST /trip-plans`. Empty list is never returned: no route is a
  /// BookingFailureCode.noRoute failure.
  Future<List<TripPlan>> planTrip({required GeoPoint origin, required GeoPoint destination, int seats = 1});

  /// `POST /bookings`. Retrying with the same [idempotencyKey] and body
  /// returns the same booking instead of creating a second one.
  Future<Booking> createBooking({required String tripPlanId, required String idempotencyKey, int seats = 1});

  /// Idempotent by state: repeating returns the current booking.
  Future<Booking> cancelBooking(String bookingId, {String? reason});

  /// Idempotent by state: repeating returns the current booking.
  Future<Booking> markBoarded(String bookingId);

  /// `GET /bookings/active`; null when the user has no active booking.
  Future<Booking?> getActiveBooking();

  /// `GET /bookings`, newest first.
  Future<BookingPage> listBookings({String? cursor, int limit = 20});

  Future<Consent> recordConsent({required bool granted});

  Future<List<Consent>> listConsents();
}

/// Server push for bookings, over the shared WS hub.
abstract class BookingRealtime {
  /// `booking.updated` snapshots for the current user, unfiltered: callers
  /// drop stale ones by `version`.
  Stream<Booking> get bookingUpdates;

  Stream<StopUpdate> get stopUpdates;

  /// true when connected, false while disconnected/reconnecting. Each
  /// `true` means events may have been missed: resync.
  Stream<bool> get connectivity;

  bool get isConnected;
}
