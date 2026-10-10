import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:konekta_mobile/core/api/api_client.dart';
import 'package:konekta_mobile/features/booking/data/api_booking_repository.dart';
import 'package:konekta_mobile/features/booking/domain/booking_failure.dart';
import 'package:konekta_mobile/features/booking/domain/booking_models.dart';
import 'package:konekta_mobile/features/booking/domain/booking_state_machine.dart';

// Shapes as the gateway serializes them (Pydantic model_dump(mode="json")).
const _bookingJson = {
  'id': '6f1c2a6e-0000-4000-8000-000000000001',
  'status': 'CONFIRMED',
  'trip_plan_id': '6f1c2a6e-0000-4000-8000-0000000000aa',
  'seats': 1,
  'pickup_stop': {
    'id': '6f1c2a6e-0000-4000-8000-0000000000bb',
    'type': 'virtual',
    'name': 'Titik Jemput',
    'location': {'lat': -6.9, 'lng': 107.6},
  },
  'dropoff_stop': null,
  'feeder_id': 'feeder-7',
  'fare_estimate_idr': 5000,
  'cancellation_fee_idr': 0,
  'eta_to_pickup_s': 240,
  'cancel_reason': null,
  'version': 3,
  'created_at': '2026-10-10T08:00:00Z',
  'updated_at': '2026-10-10T08:01:00.123456Z',
};

const _planJson = {
  'id': '6f1c2a6e-0000-4000-8000-0000000000aa',
  'origin': {'lat': -6.9, 'lng': 107.6},
  'destination': {'lat': -6.92, 'lng': 107.62},
  'legs': [
    {'mode': 'walk', 'distance_m': 120.0, 'duration_s': 90.0},
    {'mode': 'feeder', 'distance_m': 3000, 'duration_s': 600},
  ],
  'fare_estimate_idr': 5000,
  'eta_minutes': 12,
  'pickup_stop': {
    'id': '6f1c2a6e-0000-4000-8000-0000000000bb',
    'type': 'static',
    'name': 'Halte',
    'location': {'lat': -6.9, 'lng': 107.6},
    'corridor_id': null,
    'valid_until': null,
  },
  'dropoff_stop': null,
  'corridor_id': null,
  'nearest_feeder_eta_s': null,
  'expires_at': '2026-10-10T08:05:00+00:00',
};

typedef _Handler = Future<http.Response> Function(http.Request request);

ApiBookingRepository _repo(_Handler handler) => ApiBookingRepository(
      apiClient: ApiClient(baseUrl: 'http://gateway', httpClient: MockClient(handler)),
      token: 'tok',
    );

http.Response _json(Object? body, int status) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

Matcher _failsWith(BookingFailureCode code) =>
    throwsA(isA<BookingException>().having((e) => e.code, 'code', code));

void main() {
  test('createBooking sends auth + Idempotency-Key and parses the booking', () async {
    late http.Request sent;
    final repo = _repo((request) async {
      sent = request;
      return _json(_bookingJson, 201);
    });

    final booking = await repo.createBooking(tripPlanId: 'plan-1', idempotencyKey: 'key-1', seats: 2);

    expect(sent.method, 'POST');
    expect(sent.url.path, '/bookings');
    expect(sent.headers['Authorization'], 'Bearer tok');
    expect(sent.headers['Idempotency-Key'], 'key-1');
    expect(jsonDecode(sent.body), {'trip_plan_id': 'plan-1', 'seats': 2});
    expect(booking.status, BookingStatus.confirmed);
    expect(booking.version, 3);
    expect(booking.pickupStop!.type, StopType.virtualStop);
    expect(booking.dropoffStop, isNull);
    expect(booking.canCancel, isTrue);
    expect(booking.canBoard, isFalse);
  });

  test('planTrip parses plans', () async {
    final repo = _repo((request) async {
      expect(request.url.path, '/trip-plans');
      return _json({'plans': [_planJson]}, 200);
    });
    final plans = await repo.planTrip(
      origin: const GeoPoint(lat: -6.9, lng: 107.6),
      destination: const GeoPoint(lat: -6.92, lng: 107.62),
    );
    expect(plans.single.legs.map((l) => l.mode), [LegMode.walk, LegMode.feeder]);
    expect(plans.single.pickupStop!.type, StopType.staticStop);
    expect(plans.single.expiresAt, DateTime.utc(2026, 10, 10, 8, 5));
  });

  test('empty plan list is no_route', () async {
    final repo = _repo((_) async => _json({'plans': []}, 200));
    expect(
      repo.planTrip(origin: const GeoPoint(lat: 0, lng: 0), destination: const GeoPoint(lat: 0, lng: 0)),
      _failsWith(BookingFailureCode.noRoute),
    );
  });

  test('GET /bookings/active 204 is null', () async {
    final repo = _repo((_) async => http.Response('', 204));
    expect(await repo.getActiveBooking(), isNull);
  });

  test('listBookings passes cursor and limit', () async {
    late Uri url;
    final repo = _repo((request) async {
      url = request.url;
      return _json({'items': [_bookingJson], 'next_cursor': 'c2'}, 200);
    });
    final page = await repo.listBookings(cursor: 'c1', limit: 5);
    expect(url.queryParameters, {'cursor': 'c1', 'limit': '5'});
    expect(page.items.single.id, _bookingJson['id']);
    expect(page.nextCursor, 'c2');
  });

  test('typed gateway errors map to failure codes', () async {
    final cases = {
      409: 'active_booking_exists',
      410: 'plan_expired',
      403: 'consent_required',
      422: 'no_route',
      503: 'routing_unavailable',
    };
    for (final MapEntry(key: status, value: code) in cases.entries) {
      final repo = _repo((_) async => _json({'detail': {'code': code, 'message': 'x'}}, status));
      await expectLater(
        repo.createBooking(tripPlanId: 'p', idempotencyKey: 'k'),
        throwsA(isA<BookingException>()
            .having((e) => e.code.wire, 'code', code)
            .having((e) => e.statusCode, 'status', status)),
      );
    }
  });

  test('untyped errors map by status', () async {
    expect(
      _repo((_) async => _json({'detail': 'Not authenticated'}, 401)).getActiveBooking(),
      _failsWith(BookingFailureCode.unauthorized),
    );
    expect(
      _repo((_) async => _json({'detail': [{'loc': ['body'], 'msg': 'bad'}]}, 422)).getActiveBooking(),
      _failsWith(BookingFailureCode.invalidRequest),
    );
    expect(
      _repo((_) async => http.Response('<html>bad gateway</html>', 502)).getActiveBooking(),
      _failsWith(BookingFailureCode.server),
    );
  });

  test('network failure is offline (transient)', () async {
    final repo = _repo((_) async => throw http.ClientException('connection refused'));
    await expectLater(repo.getActiveBooking(), _failsWith(BookingFailureCode.offline));
    expect(BookingFailureCode.offline.isTransient, isTrue);
  });

  test('body that breaks the contract is unknown, not a crash', () async {
    final repo = _repo((_) async => _json({'id': 'x', 'status': 'TELEPORTED'}, 200));
    expect(repo.getActiveBooking(), _failsWith(BookingFailureCode.unknown));
  });

  test('ApiClient.send times out as a transport failure', () async {
    final api = ApiClient(
      baseUrl: 'http://gateway',
      httpClient: MockClient((_) => Completer<http.Response>().future),
    );
    expect(
      api.send('GET', '/bookings/active', timeout: const Duration(milliseconds: 10)),
      throwsA(isA<ApiTransportException>().having((e) => e.failure, 'failure', ApiTransportFailure.timeout)),
    );
  });
}
