import 'package:flutter_test/flutter_test.dart';
import 'package:konekta_mobile/features/booking/domain/booking_models.dart';
import 'package:konekta_mobile/features/booking/domain/booking_state_machine.dart';
import 'package:konekta_mobile/features/booking/state/booking_controller.dart';
import 'package:konekta_mobile/features/booking/state/trip_history_controller.dart';

import 'fakes.dart';

void main() {
  test('paginates and dedupes across pages', () async {
    final repo = FakeBookingRepository()
      ..onList = (cursor) async => cursor == null
          ? BookingPage(items: [booking(id: 'a'), booking(id: 'b')], nextCursor: 'c1')
          : BookingPage(items: [booking(id: 'b'), booking(id: 'c')]);
    final history = TripHistoryController(repository: repo);

    await history.refresh();
    expect(history.hasMore, isTrue);
    await history.loadMore();

    expect(history.items.map((b) => b.id), ['a', 'b', 'c']);
    expect(history.hasMore, isFalse);
    expect(repo.listCursors, [null, 'c1']);
    history.dispose();
  });

  test('follows the live booking', () async {
    final tracked = booking(id: 'b1', status: BookingStatus.feederArriving, version: 3);
    final repo = FakeBookingRepository()
      ..onGetActive = (() async => tracked)
      ..onList = (_) async => BookingPage(items: [tracked]);
    final realtime = FakeBookingRealtime();
    final live = BookingController(repository: repo, realtime: realtime);
    final history = TripHistoryController(repository: repo, live: live);
    await live.start();
    await history.refresh();

    realtime.updates.add(booking(id: 'b1', status: BookingStatus.cancelled, version: 4));
    expect(history.items.single.status, BookingStatus.cancelled);

    realtime.updates.add(booking(id: 'b2', status: BookingStatus.requested, version: 1));
    expect(history.items.map((b) => b.id), ['b2', 'b1']);

    history.dispose();
    live.dispose();
  });
}
