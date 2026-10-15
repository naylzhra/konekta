/// Typed booking failures. Server codes mirror the gateway's ErrorCode
/// (services/gateway/app/bookings/models.py); the rest are client-side.
/// UI maps [BookingFailureCode] to Bahasa Indonesia text; [debugMessage] is
/// for logs only and never contains coordinates or user ids.
library;

enum BookingFailureCode {
  // server (`{"detail": {"code", "message"}}`)
  invalidTransition('invalid_transition'),
  activeBookingExists('active_booking_exists'),
  idempotencyKeyReused('idempotency_key_reused'),
  idempotencyKeyRequired('idempotency_key_required'),
  planExpired('plan_expired'),
  notFound('not_found'),
  consentRequired('consent_required'),
  noRoute('no_route'),
  routingUnavailable('routing_unavailable'),
  concurrentUpdate('concurrent_update'),
  invalidCursor('invalid_cursor'),
  // client / transport
  unauthorized('unauthorized'),
  offline('offline'),
  timeout('timeout'),
  invalidRequest('invalid_request'),
  server('server'),
  unknown('unknown');

  const BookingFailureCode(this.wire);

  final String wire;

  static BookingFailureCode fromWire(String? value) =>
      values.firstWhere((c) => c.wire == value, orElse: () => BookingFailureCode.unknown);

  /// Safe to retry the same request (with the same Idempotency-Key, if any):
  /// the request may never have reached the server, or the server was
  /// briefly unable to answer.
  bool get isTransient => this == offline || this == timeout || this == server || this == routingUnavailable;
}

class BookingException implements Exception {
  const BookingException(this.code, {this.statusCode, this.debugMessage});

  final BookingFailureCode code;
  final int? statusCode;
  final String? debugMessage;

  @override
  String toString() => 'BookingException(${code.wire}, status: $statusCode)';
}
