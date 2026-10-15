import 'package:flutter_test/flutter_test.dart';
import 'package:konekta_mobile/features/booking/data/mock_booking_backend.dart';
import 'package:konekta_mobile/features/booking/domain/booking_failure.dart';
import 'package:konekta_mobile/features/booking/domain/booking_models.dart';
import 'package:konekta_mobile/features/booking/domain/booking_state_machine.dart';

const _origin = GeoPoint(lat: -6.9147, lng: 107.6098);
const _destination = GeoPoint(lat: -6.9025, lng: 107.6187);

Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late MockBookingBackend backend;

  MockBookingBackend create(MockBookingScenario scenario) =>
      backend = MockBookingBackend(scenario: scenario, step: const Duration(milliseconds: 40), latency: Duration.zero);

  tearDown(() => backend.dispose());

  test('requires consent like the gateway', () async {
    create(MockBookingScenario.happyPath);
    expect(
      backend.planTrip(origin: _origin, destination: _destination),
      throwsA(isA<BookingException>().having((e) => e.code, 'code', BookingFailureCode.consentRequired)),
    );
  });

  test('happy path walks the server transition table', () async {
    create(MockBookingScenario.happyPath);
    final seen = <BookingStatus>[];
    backend.bookingUpdates.listen((b) => seen.add(b.status));
    await backend.recordConsent(granted: true);

    final plan = (await backend.planTrip(origin: _origin, destination: _destination)).single;
    final created = await backend.createBooking(tripPlanId: plan.id, idempotencyKey: 'k1');
    final replayed = await backend.createBooking(tripPlanId: plan.id, idempotencyKey: 'k1');
    expect(replayed.id, created.id);
    expect(backend.createBooking(tripPlanId: 'other', idempotencyKey: 'k1'), throwsA(isA<BookingException>()));

    await _wait(120);
    final arriving = (await backend.getActiveBooking())!;
    expect(arriving.status, BookingStatus.feederArriving);
    expect(arriving.pickupStop!.type, StopType.virtualStop);

    await backend.markBoarded(arriving.id);
    await _wait(150);
    expect(await backend.getActiveBooking(), isNull);
    expect(seen, [
      BookingStatus.matching,
      BookingStatus.confirmed,
      BookingStatus.feederArriving,
      BookingStatus.boarded,
      BookingStatus.completed,
    ]);
    final history = await backend.listBookings();
    expect(history.items.single.version, 6);
  });

  test('no supply ends in FAILED', () async {
    create(MockBookingScenario.noSupply);
    await backend.recordConsent(granted: true);
    final plan = (await backend.planTrip(origin: _origin, destination: _destination)).single;
    final created = await backend.createBooking(tripPlanId: plan.id, idempotencyKey: 'k1');
    await _wait(120);
    expect((await backend.listBookings()).items.single.status, BookingStatus.failed);
    expect(created.status, BookingStatus.requested);
  });

  test('cancel during matching wins over scheduled transitions', () async {
    create(MockBookingScenario.happyPath);
    await backend.recordConsent(granted: true);
    final plan = (await backend.planTrip(origin: _origin, destination: _destination)).single;
    final created = await backend.createBooking(tripPlanId: plan.id, idempotencyKey: 'k1');
    final cancelled = await backend.cancelBooking(created.id);
    await _wait(120);
    expect(cancelled.status, BookingStatus.cancelled);
    expect((await backend.listBookings()).items.single.status, BookingStatus.cancelled);
  });
}
