import '../../../core/api/api_client.dart';
import '../domain/booking_failure.dart';
import '../domain/booking_models.dart';
import 'booking_repository.dart';

/// BookingRepository over the gateway REST API (DESIGN.md §6).
class ApiBookingRepository implements BookingRepository {
  ApiBookingRepository({required ApiClient apiClient, required String token})
      : _api = apiClient,
        _token = token;

  final ApiClient _api;
  final String _token;

  @override
  Future<List<TripPlan>> planTrip({required GeoPoint origin, required GeoPoint destination, int seats = 1}) async {
    final plans = await _request(
      'POST',
      '/trip-plans',
      body: {'origin': origin.toJson(), 'destination': destination.toJson(), 'seats': seats},
      parse: (body) => [
        for (final plan in _map(body)['plans'] as List<dynamic>) TripPlan.fromJson(plan as Map<String, dynamic>),
      ],
    );
    if (plans.isEmpty) throw const BookingException(BookingFailureCode.noRoute);
    return plans;
  }

  @override
  Future<Booking> createBooking({required String tripPlanId, required String idempotencyKey, int seats = 1}) =>
      _request(
        'POST',
        '/bookings',
        body: {'trip_plan_id': tripPlanId, 'seats': seats},
        headers: {'Idempotency-Key': idempotencyKey},
        parse: _booking,
      );

  @override
  Future<Booking> cancelBooking(String bookingId, {String? reason}) => _request(
        'POST',
        '/bookings/${Uri.encodeComponent(bookingId)}/cancel',
        body: {if (reason != null) 'reason': reason},
        parse: _booking,
      );

  @override
  Future<Booking> markBoarded(String bookingId) =>
      _request('POST', '/bookings/${Uri.encodeComponent(bookingId)}/boarded', parse: _booking);

  @override
  Future<Booking?> getActiveBooking() =>
      _request('GET', '/bookings/active', parse: (body) => body == null ? null : _booking(body));

  @override
  Future<BookingPage> listBookings({String? cursor, int limit = 20}) => _request(
        'GET',
        '/bookings',
        query: {if (cursor != null) 'cursor': cursor, 'limit': '$limit'},
        parse: (body) => BookingPage.fromJson(_map(body)),
      );

  @override
  Future<Consent> recordConsent({required bool granted}) => _request(
        'POST',
        '/consents',
        body: {'purpose': consentPurposeTripLocation, 'policy_version': consentPolicyVersion, 'granted': granted},
        parse: (body) => Consent.fromJson(_map(body)),
      );

  @override
  Future<List<Consent>> listConsents() => _request(
        'GET',
        '/consents',
        parse: (body) => [
          for (final item in _map(body)['items'] as List<dynamic>) Consent.fromJson(item as Map<String, dynamic>),
        ],
      );

  static Map<String, dynamic> _map(Object? body) => body as Map<String, dynamic>;

  static Booking _booking(Object? body) => Booking.fromJson(_map(body));

  /// Parses a 2xx body with [parse]; every failure, including a body that
  /// doesn't match the contract, becomes a BookingException.
  Future<T> _request<T>(
    String method,
    String path, {
    required T Function(Object? body) parse,
    Object? body,
    Map<String, String>? query,
    Map<String, String>? headers,
  }) async {
    final ApiResponse response;
    try {
      response = await _api.send(method, path, token: _token, body: body, query: query, headers: headers);
    } on ApiTransportException catch (e) {
      throw BookingException(switch (e.failure) {
        ApiTransportFailure.offline => BookingFailureCode.offline,
        ApiTransportFailure.timeout => BookingFailureCode.timeout,
        ApiTransportFailure.badResponse => BookingFailureCode.unknown,
      });
    }
    if (!response.isSuccess) throw _failureFor(response);
    try {
      return parse(response.body);
    } on Object catch (e) {
      // TypeError from a cast or FormatException from an unknown enum value
      throw BookingException(BookingFailureCode.unknown, statusCode: response.statusCode, debugMessage: e.runtimeType.toString());
    }
  }

  static BookingException _failureFor(ApiResponse response) {
    final status = response.statusCode;
    final detail = response.body is Map<String, dynamic> ? (response.body as Map<String, dynamic>)['detail'] : null;
    if (detail is Map<String, dynamic> && detail['code'] is String) {
      return BookingException(
        BookingFailureCode.fromWire(detail['code'] as String),
        statusCode: status,
        debugMessage: detail['message'] as String?,
      );
    }
    final code = switch (status) {
      401 => BookingFailureCode.unauthorized,
      // auth's role/suspension checks answer 403 with a plain-string detail
      403 => BookingFailureCode.unauthorized,
      404 => BookingFailureCode.notFound,
      422 || 400 => BookingFailureCode.invalidRequest,
      >= 500 => BookingFailureCode.server,
      _ => BookingFailureCode.unknown,
    };
    return BookingException(code, statusCode: status);
  }
}
