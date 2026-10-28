import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:konekta_mobile/core/api/api_client.dart';
import 'package:konekta_mobile/features/live_tracking/data/feeder_api.dart';
import 'package:konekta_mobile/features/live_tracking/domain/feeder_models.dart';

FeederApi _api(Future<http.Response> Function(http.Request request) handler) =>
    FeederApi(ApiClient(baseUrl: 'http://gateway', httpClient: MockClient(handler)));

http.Response _json(Object body, int status) => http.Response(jsonEncode(body), status);

void main() {
  test('lists corridors with feeder availability, without a token', () async {
    final api = _api((request) async {
      expect(request.url.path, '/corridors');
      expect(request.headers.containsKey('Authorization'), isFalse);
      return _json({
        'items': [
          {
            'id': 'K1',
            'name': 'Koridor 1',
            'feeders': [
              {'id': 'K1-01', 'number': 1, 'capacity': 8, 'available': false},
              {'id': 'K1-02', 'number': 2, 'capacity': 8, 'available': true},
            ],
          },
        ],
      }, 200);
    });

    final [corridor] = await api.listCorridors();
    expect(corridor.name, 'Koridor 1');
    expect(corridor.availableFeeders.map((f) => f.id), ['K1-02']);
  });

  test('route stops carry service info when set', () async {
    final api = _api((request) async => _json({
          'id': 'K1',
          'name': 'Koridor 1',
          'operating_hours': '05.00-21.00',
          'operating_days': null,
          'fare_from_idr': 2000,
          'items': [
            {'position': 1, 'name': 'Halte A', 'lat': -6.9, 'lng': 107.6},
          ],
        }, 200));

    final route = await api.routeStops('K1');
    expect((route.operatingHours, route.operatingDays, route.fareFromIdr), ('05.00-21.00', null, 2000));
    expect(route.stops.single.name, 'Halte A');
  });

  test('arrivals per stop, with the token and direction', () async {
    final api = _api((request) async {
      expect(request.url.path, '/corridors/K1/arrivals');
      expect(request.url.queryParameters, {'direction': 'backward'});
      expect(request.headers['Authorization'], 'Bearer tok');
      return _json({
        'id': 'K1',
        'direction': 'backward',
        'items': [
          {'position': 1, 'name': 'Halte A', 'arrivals': []},
          {
            'position': 2,
            'name': 'Halte B',
            'arrivals': [
              {'feeder_id': 'K1-01', 'eta_s': 95, 'occupancy': 3, 'capacity': 8},
            ],
          },
        ],
      }, 200);
    });

    final stops = await api.arrivals('K1', 'tok', direction: RouteDirection.backward);
    expect(stops.map((s) => s.arrivals.length), [0, 1]);
    expect((stops[1].arrivals.single.feederId, stops[1].arrivals.single.etaS), ('K1-01', 95));
  });

  test('lists live feeders with the token', () async {
    final api = _api((request) async {
      expect(request.url.path, '/feeders/live');
      expect(request.headers['Authorization'], 'Bearer tok');
      return _json({
        'items': [
          {
            'feeder_id': 'K1-01',
            'lat': -6.9,
            'lng': 107.6,
            'heading': null,
            'occupancy': 8,
            'capacity': 8,
            'corridor_id': 'K1',
            'updated_at': '2026-10-15T08:00:00Z',
          },
        ],
      }, 200);
    });

    final [feeder] = await api.liveFeeders('tok');
    expect((feeder.feederId, feeder.corridorId, feeder.capacity, feeder.isFull), ('K1-01', 'K1', 8, true));
  });

  test('reports a position with the driver token and returns the accepted time', () async {
    final api = _api((request) async {
      expect(request.method, 'POST');
      expect(request.url.path, '/feeders/me/position');
      expect(request.headers['Authorization'], 'Bearer tok');
      expect(jsonDecode(request.body), {'lat': -6.9, 'lng': 107.6, 'accuracy_m': 5.0});
      return _json({'feeder_id': 'K1-01', 'updated_at': '2026-10-15T08:00:00Z'}, 200);
    });

    expect(await api.reportPosition('tok', lat: -6.9, lng: 107.6, accuracyM: 5), DateTime.utc(2026, 10, 15, 8));
  });

  test('maps typed gateway errors, 401 and transport failures', () async {
    Future<String> codeFor(Future<http.Response> Function(http.Request) handler) async {
      try {
        await _api(handler).reportPosition('tok', lat: -6.9, lng: 107.6);
      } on FeederApiException catch (e) {
        return e.code;
      }
      fail('expected FeederApiException');
    }

    expect(
      await codeFor((_) async => _json({'detail': {'code': 'outside_service_area', 'message': 'x'}}, 422)),
      FeederApiException.outsideServiceArea,
    );
    expect(await codeFor((_) async => _json({'detail': 'Invalid or expired session'}, 401)), FeederApiException.unauthorized);
    expect(await codeFor((_) async => _json({'detail': 'Insufficient role'}, 403)), FeederApiException.unknown);
    expect(await codeFor((_) async => throw http.ClientException('down')), FeederApiException.offline);
  });
}
