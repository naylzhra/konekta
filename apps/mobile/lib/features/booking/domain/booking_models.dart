/// Booking domain models, mirroring the gateway's Pydantic models
/// (services/gateway/app/bookings/models.py, DESIGN.md §2, §6).
/// Money is integer rupiah (`*Idr`). Ids are opaque strings.
library;

import 'booking_state_machine.dart';

class GeoPoint {
  const GeoPoint({required this.lat, required this.lng});

  factory GeoPoint.fromJson(Map<String, dynamic> json) => GeoPoint(
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
      );

  final double lat;
  final double lng;

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  // Deliberately no toString with coordinates: never log raw location.
}

enum StopType {
  staticStop('static'),
  virtualStop('virtual');

  const StopType(this.wire);

  final String wire;

  static StopType fromWire(String value) =>
      values.firstWhere((t) => t.wire == value, orElse: () => throw FormatException('Unknown stop type: $value'));
}

class Stop {
  const Stop({
    required this.id,
    required this.type,
    required this.name,
    required this.location,
    this.corridorId,
    this.validUntil,
  });

  factory Stop.fromJson(Map<String, dynamic> json) => Stop(
        id: json['id'] as String,
        type: StopType.fromWire(json['type'] as String),
        name: json['name'] as String,
        location: GeoPoint.fromJson(json['location'] as Map<String, dynamic>),
        corridorId: json['corridor_id'] as String?,
        validUntil: _parseDate(json['valid_until']),
      );

  final String id;
  final StopType type;
  final String name;
  final GeoPoint location;
  final String? corridorId;
  final DateTime? validUntil;
}

/// Stop as it was when the booking was confirmed; never rewritten.
class StopSnapshot {
  const StopSnapshot({this.id, required this.type, required this.name, required this.location});

  factory StopSnapshot.fromJson(Map<String, dynamic> json) => StopSnapshot(
        id: json['id'] as String?,
        type: StopType.fromWire(json['type'] as String),
        name: json['name'] as String,
        location: GeoPoint.fromJson(json['location'] as Map<String, dynamic>),
      );

  /// Null once the stop row itself has been deleted server-side.
  final String? id;
  final StopType type;
  final String name;
  final GeoPoint location;
}

enum LegMode {
  walk('walk'),
  feeder('feeder');

  const LegMode(this.wire);

  final String wire;

  static LegMode fromWire(String value) =>
      values.firstWhere((m) => m.wire == value, orElse: () => throw FormatException('Unknown leg mode: $value'));
}

class TripLeg {
  const TripLeg({required this.mode, required this.distanceM, required this.durationS});

  factory TripLeg.fromJson(Map<String, dynamic> json) => TripLeg(
        mode: LegMode.fromWire(json['mode'] as String),
        distanceM: (json['distance_m'] as num).toDouble(),
        durationS: (json['duration_s'] as num).toDouble(),
      );

  final LegMode mode;
  final double distanceM;
  final double durationS;
}

class TripPlan {
  const TripPlan({
    required this.id,
    required this.origin,
    required this.destination,
    required this.legs,
    required this.fareEstimateIdr,
    required this.etaMinutes,
    required this.expiresAt,
    this.pickupStop,
    this.dropoffStop,
    this.corridorId,
    this.nearestFeederEtaS,
  });

  factory TripPlan.fromJson(Map<String, dynamic> json) => TripPlan(
        id: json['id'] as String,
        origin: GeoPoint.fromJson(json['origin'] as Map<String, dynamic>),
        destination: GeoPoint.fromJson(json['destination'] as Map<String, dynamic>),
        legs: [
          for (final leg in json['legs'] as List<dynamic>) TripLeg.fromJson(leg as Map<String, dynamic>),
        ],
        fareEstimateIdr: json['fare_estimate_idr'] as int,
        etaMinutes: json['eta_minutes'] as int,
        pickupStop: _parseOptional(json['pickup_stop'], Stop.fromJson),
        dropoffStop: _parseOptional(json['dropoff_stop'], Stop.fromJson),
        corridorId: json['corridor_id'] as String?,
        nearestFeederEtaS: json['nearest_feeder_eta_s'] as int?,
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );

  final String id;
  final GeoPoint origin;
  final GeoPoint destination;
  final List<TripLeg> legs;
  final int fareEstimateIdr;
  final int etaMinutes;
  final Stop? pickupStop;
  final Stop? dropoffStop;
  final String? corridorId;
  final int? nearestFeederEtaS;
  final DateTime expiresAt;

  bool isExpired(DateTime now) => !now.isBefore(expiresAt);
}

class Booking {
  const Booking({
    required this.id,
    required this.status,
    required this.seats,
    required this.fareEstimateIdr,
    required this.version,
    required this.createdAt,
    required this.updatedAt,
    this.tripPlanId,
    this.pickupStop,
    this.dropoffStop,
    this.feederId,
    this.cancellationFeeIdr = 0,
    this.etaToPickupS,
    this.cancelReason,
  });

  factory Booking.fromJson(Map<String, dynamic> json) => Booking(
        id: json['id'] as String,
        status: BookingStatus.fromWire(json['status'] as String),
        tripPlanId: json['trip_plan_id'] as String?,
        seats: json['seats'] as int,
        pickupStop: _parseOptional(json['pickup_stop'], StopSnapshot.fromJson),
        dropoffStop: _parseOptional(json['dropoff_stop'], StopSnapshot.fromJson),
        feederId: json['feeder_id'] as String?,
        fareEstimateIdr: json['fare_estimate_idr'] as int,
        cancellationFeeIdr: (json['cancellation_fee_idr'] as int?) ?? 0,
        etaToPickupS: json['eta_to_pickup_s'] as int?,
        cancelReason: json['cancel_reason'] as String?,
        version: json['version'] as int,
        createdAt: DateTime.parse(json['created_at'] as String),
        updatedAt: DateTime.parse(json['updated_at'] as String),
      );

  final String id;
  final BookingStatus status;
  final String? tripPlanId;
  final int seats;
  final StopSnapshot? pickupStop;
  final StopSnapshot? dropoffStop;
  final String? feederId;
  final int fareEstimateIdr;
  final int cancellationFeeIdr;
  final int? etaToPickupS;
  final String? cancelReason;

  /// Bumped by the server on every transition; used to drop stale events.
  final int version;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isActive => status.isActive;
  bool get canCancel => canApply(status, BookingEvent.cancel);
  bool get canBoard => canApply(status, BookingEvent.passengerBoarded);
}

class BookingPage {
  const BookingPage({required this.items, this.nextCursor});

  factory BookingPage.fromJson(Map<String, dynamic> json) => BookingPage(
        items: [
          for (final item in json['items'] as List<dynamic>) Booking.fromJson(item as Map<String, dynamic>),
        ],
        nextCursor: json['next_cursor'] as String?,
      );

  final List<Booking> items;
  final String? nextCursor;
}

/// `stop.updated` payload: a virtual stop moved or got a new validity window.
class StopUpdate {
  const StopUpdate({required this.stopId, required this.location, this.validUntil});

  factory StopUpdate.fromJson(Map<String, dynamic> json) => StopUpdate(
        stopId: json['stop_id'] as String,
        location: GeoPoint.fromJson(json['location'] as Map<String, dynamic>),
        validUntil: _parseDate(json['valid_until']),
      );

  final String stopId;
  final GeoPoint location;
  final DateTime? validUntil;
}

const String consentPurposeTripLocation = 'trip_location';

/// Must match the gateway's CONSENT_POLICY_VERSION
/// (services/gateway/app/bookings/config.py). On mismatch the gateway
/// answers 403 consent_required and the app asks for consent again.
const String consentPolicyVersion = String.fromEnvironment('CONSENT_POLICY_VERSION', defaultValue: '2026-10');

class Consent {
  const Consent({required this.purpose, required this.policyVersion, required this.granted, required this.createdAt});

  factory Consent.fromJson(Map<String, dynamic> json) => Consent(
        purpose: json['purpose'] as String,
        policyVersion: json['policy_version'] as String,
        granted: json['granted'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final String purpose;
  final String policyVersion;
  final bool granted;
  final DateTime createdAt;
}

DateTime? _parseDate(Object? value) => value == null ? null : DateTime.parse(value as String);

T? _parseOptional<T>(Object? value, T Function(Map<String, dynamic>) parse) =>
    value == null ? null : parse(value as Map<String, dynamic>);
