import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:konekta_mobile/features/booking/domain/booking_failure.dart';
import 'package:konekta_mobile/features/booking/domain/booking_models.dart';
import 'package:konekta_mobile/features/booking/domain/booking_state_machine.dart';
import 'package:konekta_mobile/features/booking/state/booking_controller.dart';

import 'fakes.dart';

void main() {
  late FakeBookingRepository repo;
  late FakeBookingRealtime realtime;
  late BookingController controller;
  var keys = 0;

  setUp(() {
    repo = FakeBookingRepository();
    realtime = FakeBookingRealtime();
    keys = 0;
    controller = BookingController(
      repository: repo,
      realtime: realtime,
      newIdempotencyKey: () => 'key-${++keys}',
    );
  });

  tearDown(() => controller.dispose());

  group('start', () {
    test('loads the active booking and consent', () async {
      repo.onGetActive = () async => booking(version: 2);
      await repo.recordConsent(granted: true);
      await controller.start();
      expect(controller.current!.version, 2);
      expect(controller.hasActiveBooking, isTrue);
      expect(controller.consent, ConsentState.granted);
    });

    test('consent for an older policy version is required again', () async {
      repo.consents.add(Consent(
        purpose: consentPurposeTripLocation,
        policyVersion: 'old',
        granted: true,
        createdAt: DateTime.utc(2025),
      ));
      await controller.start();
      expect(controller.consent, ConsentState.required);
    });
  });

  group('booking.updated', () {
    setUp(() async {
      repo.onGetActive = () async => booking(version: 2);
      await controller.start();
    });

    test('applies newer, drops duplicate and out-of-order versions', () {
      var notified = 0;
      controller.addListener(() => notified++);

      realtime.updates.add(booking(status: BookingStatus.feederArriving, version: 3));
      expect(controller.current!.status, BookingStatus.feederArriving);
      expect(notified, 1);

      realtime.updates.add(booking(status: BookingStatus.feederArriving, version: 3)); // duplicate
      realtime.updates.add(booking(status: BookingStatus.confirmed, version: 2)); // late
      expect(controller.current!.version, 3);
      expect(notified, 1);
    });

    test('ignores late events for an older booking', () {
      realtime.updates.add(booking(id: 'old', status: BookingStatus.completed, version: 7));
      expect(controller.current!.id, 'b1');
    });

    test('a different active booking triggers resync instead of being applied', () async {
      final callsBefore = repo.getActiveCalls;
      realtime.updates.add(booking(id: 'other', status: BookingStatus.matching, version: 1));
      expect(controller.current!.id, 'b1');
      await pumpEventQueue();
      expect(repo.getActiveCalls, callsBefore + 1);
    });

    test('terminal update is kept until dismissed, then late events stay dropped', () {
      realtime.updates.add(booking(status: BookingStatus.noShow, version: 4));
      expect(controller.current!.status, BookingStatus.noShow);
      expect(controller.hasActiveBooking, isFalse);
      expect(controller.canCancel, isFalse);

      controller.dismissFinished();
      expect(controller.current, isNull);

      realtime.updates.add(booking(status: BookingStatus.feederArriving, version: 3));
      expect(controller.current, isNull);
    });

    test('stop.updated for the pickup stop is exposed', () {
      realtime.stops.add(const StopUpdate(stopId: 'elsewhere', location: GeoPoint(lat: 0, lng: 0)));
      expect(controller.pickupStopUpdate, isNull);
      realtime.stops.add(const StopUpdate(stopId: 'stop-1', location: GeoPoint(lat: -6.91, lng: 107.6)));
      expect(controller.pickupStopUpdate!.stopId, 'stop-1');
    });
  });

  group('reconnect', () {
    test('resyncs and picks up a booking that ended while offline', () async {
      repo.onGetActive = () async => booking(version: 2);
      await controller.start();

      realtime.isConnected = false;
      realtime.connection.add(false);
      expect(controller.isOnline, isFalse);

      repo.onGetActive = () async => null;
      repo.onList = (_) async => BookingPage(items: [booking(status: BookingStatus.completed, version: 6)]);
      realtime.connection.add(true);
      await pumpEventQueue();

      expect(controller.isOnline, isTrue);
      expect(controller.current!.status, BookingStatus.completed);
    });

    test('resync never rolls back to an older version', () async {
      repo.onGetActive = () async => booking(version: 2);
      await controller.start();
      realtime.updates.add(booking(status: BookingStatus.feederArriving, version: 3));

      // GET /bookings/active raced with the WS event and returned the old row
      realtime.connection.add(true);
      await pumpEventQueue();
      expect(controller.current!.version, 3);
    });

    test('concurrent resyncs share one request', () async {
      final gate = Completer<Booking?>();
      repo.onGetActive = () => gate.future;
      final a = controller.resync();
      final b = controller.resync();
      gate.complete(null);
      await Future.wait([a, b]);
      expect(repo.getActiveCalls, 1);
    });

    test('offline resync keeps the last known booking', () async {
      repo.onGetActive = () async => booking(version: 2);
      await controller.start();
      repo.onGetActive = () async => throw failure(BookingFailureCode.offline);
      await controller.resync();
      expect(controller.current!.version, 2);
      expect(controller.syncError!.code, BookingFailureCode.offline);
    });
  });

  group('confirm', () {
    test('double tap sends one request', () async {
      final gate = Completer<Booking>();
      repo.onCreate = (_, __) => gate.future;
      final first = controller.confirm(plan());
      final second = controller.confirm(plan());
      expect(controller.isConfirming, isTrue);
      gate.complete(booking(status: BookingStatus.requested));
      expect(identical(first, second), isTrue);
      await first;
      expect(repo.createKeys, ['key-1']);
      expect(controller.isConfirming, isFalse);
      expect(controller.current!.status, BookingStatus.requested);
    });

    test('retry after timeout reuses the Idempotency-Key', () async {
      repo.onCreate = (_, __) async => throw failure(BookingFailureCode.timeout);
      expect(await controller.confirm(plan()), isNull);
      expect(controller.actionError!.code, BookingFailureCode.timeout);

      repo.onCreate = (_, __) async => booking(status: BookingStatus.requested);
      expect(await controller.confirm(plan()), isNotNull);
      expect(repo.createKeys, ['key-1', 'key-1']);
    });

    test('new key after a definitive failure or for another plan', () async {
      repo.onCreate = (_, __) async => throw failure(BookingFailureCode.timeout);
      await controller.confirm(plan(id: 'p1'));
      await controller.confirm(plan(id: 'p2'));
      repo.onCreate = (_, __) async => throw failure(BookingFailureCode.consentRequired);
      await controller.confirm(plan(id: 'p2'));
      await controller.confirm(plan(id: 'p2'));
      expect(repo.createKeys, ['key-1', 'key-2', 'key-2', 'key-3']);
      expect(controller.consent, ConsentState.required);
    });

    test('plan_expired clears plans for a re-plan', () async {
      await controller.planTrip(origin: plan().origin, destination: plan().destination);
      expect(controller.planning, PlanningStatus.ready);
      repo.onCreate = (_, __) async => throw failure(BookingFailureCode.planExpired);
      await controller.confirm(controller.plans.single);
      expect(controller.plans, isEmpty);
      expect(controller.planError!.code, BookingFailureCode.planExpired);
    });

    test('not sent while a booking is active', () async {
      repo.onGetActive = () async => booking(version: 1);
      await controller.start();
      expect(await controller.confirm(plan()), isNull);
      expect(repo.createKeys, isEmpty);
      expect(controller.actionError!.code, BookingFailureCode.activeBookingExists);
    });

    test('active_booking_exists from the server resyncs', () async {
      repo.onCreate = (_, __) async => throw failure(BookingFailureCode.activeBookingExists);
      repo.onGetActive = () async => booking(id: 'elsewhere', version: 1);
      await controller.confirm(plan());
      await pumpEventQueue();
      expect(controller.current!.id, 'elsewhere');
    });
  });

  group('cancel / boarded', () {
    test('mirrored validator blocks actions the server would reject', () async {
      repo.onGetActive = () async => booking(status: BookingStatus.boarded, version: 5);
      await controller.start();
      expect(controller.canCancel, isFalse);
      expect(controller.canBoard, isFalse);
      await controller.cancel();
      await controller.markBoarded();
      expect(repo.cancelCalls + repo.boardedCalls, 0);
    });

    test('boarded only from FEEDER_ARRIVING; result comes from the server', () async {
      repo.onGetActive = () async => booking(status: BookingStatus.feederArriving, version: 4);
      await controller.start();
      expect(controller.canBoard, isTrue);
      await controller.markBoarded();
      expect(controller.current!.status, BookingStatus.boarded);
    });

    test('invalid_transition (server moved on) resyncs to server state', () async {
      repo.onGetActive = () async => booking(status: BookingStatus.feederArriving, version: 4);
      await controller.start();
      repo.onCancel = (_) async => throw failure(BookingFailureCode.invalidTransition);
      repo.onGetActive = () async => null;
      repo.onList = (_) async => BookingPage(items: [booking(status: BookingStatus.noShow, version: 5)]);

      await controller.cancel();
      await pumpEventQueue();
      expect(controller.actionError!.code, BookingFailureCode.invalidTransition);
      expect(controller.current!.status, BookingStatus.noShow);
    });
  });

  group('planTrip', () {
    test('consent_required flips consent state', () async {
      repo.onPlan = () async => throw failure(BookingFailureCode.consentRequired);
      await controller.planTrip(origin: plan().origin, destination: plan().destination);
      expect(controller.planning, PlanningStatus.failed);
      expect(controller.consent, ConsentState.required);
    });

    test('a newer search wins over a slower older one', () async {
      final slow = Completer<List<TripPlan>>();
      repo.onPlan = () => slow.future;
      final first = controller.planTrip(origin: plan().origin, destination: plan().destination);
      repo.onPlan = () async => [plan(id: 'new')];
      await controller.planTrip(origin: plan().origin, destination: plan().destination);
      slow.complete([plan(id: 'old')]);
      await first;
      expect(controller.plans.single.id, 'new');
    });
  });
}
