import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:konekta_mobile/core/strings/booking_strings.dart';
import 'package:konekta_mobile/features/booking/data/trip_locations.dart';
import 'package:konekta_mobile/features/booking/domain/booking_failure.dart';
import 'package:konekta_mobile/features/booking/domain/booking_models.dart';
import 'package:konekta_mobile/features/booking/domain/booking_state_machine.dart';
import 'package:konekta_mobile/features/booking/state/booking_controller.dart';
import 'package:konekta_mobile/features/booking/state/trip_history_controller.dart';
import 'package:konekta_mobile/features/booking/ui/booking_home_section.dart';
import 'package:konekta_mobile/features/booking/ui/trips_view.dart';

import 'fakes.dart';

void main() {
  late FakeBookingRepository repo;
  late FakeBookingRealtime realtime;
  late BookingController controller;

  setUp(() {
    repo = FakeBookingRepository();
    realtime = FakeBookingRealtime();
    controller = BookingController(repository: repo, realtime: realtime);
  });

  tearDown(() => controller.dispose());

  Future<void> pump(WidgetTester tester, Widget body) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: body)));
    await controller.start();
    await tester.pump();
  }

  Future<void> pumpHome(WidgetTester tester) =>
      pump(tester, BookingHomeSection(controller: controller, locations: const StubTripLocations()));

  // Disposes widgets so timers (plan expiry) don't outlive the test.
  Future<void> unmount(WidgetTester tester) => tester.pumpWidget(const SizedBox());

  group('Home', () {
    testWidgets('asks for consent first, then shows the planner', (tester) async {
      await pumpHome(tester);
      expect(find.text(BookingStrings.consentTitle), findsOneWidget);

      await tester.tap(find.text(BookingStrings.consentAccept));
      await tester.pump();
      await tester.pump(); // planner mounted; its suggestions load next

      expect(repo.consents.single.granted, isTrue);
      expect(find.text(BookingStrings.consentTitle), findsNothing);
      expect(find.text(StubTripLocations.places.first.name), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('plans, then confirms once despite a double tap', (tester) async {
      await repo.recordConsent(granted: true);
      repo.onPlan = () async => [plan(expiresAt: DateTime.now().add(const Duration(minutes: 5)))];
      final created = Completer<Booking>();
      repo.onCreate = (_, __) => created.future;
      await pumpHome(tester);

      await tester.tap(find.text(StubTripLocations.places.first.name));
      await tester.pump();
      expect(find.text(BookingStrings.planTitle), findsOneWidget);
      expect(find.text(BookingStrings.rupiah(5000)), findsOneWidget);

      await tester.tap(find.text(BookingStrings.confirmBooking));
      await tester.pump();
      // Button is disabled (spinner) while the request is in flight.
      expect(find.text(BookingStrings.confirmBooking), findsNothing);
      unawaited(controller.confirm(controller.plans.single));

      created.complete(booking(status: BookingStatus.requested));
      await tester.pump();

      expect(repo.createKeys, hasLength(1));
      expect(find.text(BookingStrings.statusLabel(BookingStatus.requested)), findsOneWidget);
      await unmount(tester);
    });

    testWidgets('no route shows the error without a retry', (tester) async {
      await repo.recordConsent(granted: true);
      repo.onPlan = () async => throw failure(BookingFailureCode.noRoute);
      await pumpHome(tester);

      await tester.tap(find.text(StubTripLocations.places.first.name));
      await tester.pump();

      expect(find.text(BookingStrings.failure(BookingFailureCode.noRoute)), findsOneWidget);
      expect(find.text(BookingStrings.retry), findsNothing);
      await unmount(tester);
    });

    testWidgets('feeder arriving: passenger confirms boarding', (tester) async {
      await repo.recordConsent(granted: true);
      repo.onGetActive = () async => booking(status: BookingStatus.feederArriving, version: 2);
      await pumpHome(tester);

      expect(find.text(BookingStrings.stopVirtual), findsOneWidget);
      await tester.tap(find.text(BookingStrings.boarded));
      await tester.pump();

      expect(repo.boardedCalls, 1);
      expect(find.text(BookingStrings.statusLabel(BookingStatus.boarded)), findsOneWidget);
      expect(find.text(BookingStrings.cancel), findsNothing);
      await unmount(tester);
    });

    testWidgets('cancel asks for confirmation', (tester) async {
      await repo.recordConsent(granted: true);
      repo.onGetActive = () async => booking(status: BookingStatus.confirmed, version: 2);
      await pumpHome(tester);

      await tester.tap(find.text(BookingStrings.cancel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(BookingStrings.cancelDialogKeep));
      await tester.pumpAndSettle();
      expect(repo.cancelCalls, 0);

      await tester.tap(find.text(BookingStrings.cancel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(BookingStrings.cancelDialogConfirm));
      await tester.pumpAndSettle();

      expect(repo.cancelCalls, 1);
      expect(find.text(BookingStrings.statusLabel(BookingStatus.cancelled)), findsOneWidget);
      await tester.tap(find.text(BookingStrings.bookAgain));
      await tester.pump();
      expect(controller.current, isNull);
      await unmount(tester);
    });

    testWidgets('shows offline state', (tester) async {
      await repo.recordConsent(granted: true);
      realtime.isConnected = false;
      await pumpHome(tester);

      expect(find.text(BookingStrings.offline), findsOneWidget);
      realtime.connection.add(true);
      await tester.pump();
      expect(find.text(BookingStrings.offline), findsNothing);
      await unmount(tester);
    });
  });

  group('Trips', () {
    late TripHistoryController history;

    setUp(() => history = TripHistoryController(repository: repo, live: controller));
    tearDown(() => history.dispose());

    testWidgets('lists history and keeps the active trip out of it', (tester) async {
      repo.onGetActive = () async => booking(id: 'active', status: BookingStatus.confirmed, version: 2);
      repo.onList = (_) async => BookingPage(items: [
            booking(id: 'active', status: BookingStatus.confirmed, version: 2),
            booking(id: 'done', status: BookingStatus.completed, version: 5),
          ]);
      await pump(tester, TripsView(booking: controller, history: history));
      await tester.pump();

      expect(find.text(BookingStrings.statusLabel(BookingStatus.confirmed)), findsOneWidget); // active card
      expect(find.text(BookingStrings.statusLabel(BookingStatus.completed)), findsOneWidget); // history chip
      expect(find.text(BookingStrings.loadMore), findsNothing);
      await unmount(tester);
    });

    testWidgets('empty history', (tester) async {
      await pump(tester, TripsView(booking: controller, history: history));
      await tester.pump();

      expect(find.text(BookingStrings.noActiveTrip), findsOneWidget);
      expect(find.text(BookingStrings.historyEmpty), findsOneWidget);
      await unmount(tester);
    });
  });

  group('formatting', () {
    test('rupiah', () {
      expect(BookingStrings.rupiah(0), 'Rp0');
      expect(BookingStrings.rupiah(5000), 'Rp5.000');
      expect(BookingStrings.rupiah(1234567), 'Rp1.234.567');
    });

    test('duration', () {
      expect(BookingStrings.durationFromSeconds(30), '< 1 menit');
      expect(BookingStrings.durationFromSeconds(61), '2 menit');
    });
  });
}
