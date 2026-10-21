import '../../core/api/api_client.dart';
import '../../core/websocket/ws_client.dart';
import 'data/api_booking_repository.dart';
import 'data/booking_repository.dart';
import 'data/mock_booking_backend.dart';
import 'data/ws_booking_realtime.dart';
import 'state/booking_controller.dart';
import 'state/trip_history_controller.dart';

/// What the passenger shell hands to booking's Home/Trips widgets
/// (DESIGN.md §5.5): the auth token plus the app-wide ApiClient and the
/// single WsClient. Whoever creates the session owns the WsClient's
/// connect/dispose.
class BookingSession {
  BookingSession({required this.token, required this.apiClient, required this.wsClient});

  /// Builds the shared clients for [token]. Until the passenger shell lands
  /// on `main` (DESIGN.md §5.5), booking creates the session itself.
  factory BookingSession.create({required String token, ApiClient? apiClient}) {
    final api = apiClient ?? ApiClient();
    return BookingSession(
      token: token,
      apiClient: api,
      wsClient: WsClient(
        url: WsClient.gatewayUrl(httpBaseUrl: api.baseUrl, clientId: WsClient.newClientId(), token: token),
      ),
    );
  }

  final String token;
  final ApiClient apiClient;
  final WsClient wsClient;
}

/// Booking's data + state objects for one session. Uses the in-memory
/// MockBookingBackend only with `--dart-define=BOOKING_MOCK=true`.
class BookingDependencies {
  BookingDependencies._(this.repository, this.realtime, this._mock)
      : booking = BookingController(repository: repository, realtime: realtime) {
    history = TripHistoryController(repository: repository, live: booking);
  }

  factory BookingDependencies.create(BookingSession session, {bool useMock = MockBookingBackend.enabled}) {
    if (useMock) {
      final mock = MockBookingBackend(scenario: MockBookingBackend.scenarioFromEnvironment());
      return BookingDependencies._(mock, mock, mock);
    }
    return BookingDependencies._(
      ApiBookingRepository(apiClient: session.apiClient, token: session.token),
      WsBookingRealtime(session.wsClient),
      null,
    );
  }

  final BookingRepository repository;
  final BookingRealtime realtime;
  final BookingController booking;
  late final TripHistoryController history;
  final MockBookingBackend? _mock;

  bool get isMock => _mock != null;

  void dispose() {
    history.dispose();
    booking.dispose();
    _mock?.dispose();
  }
}
