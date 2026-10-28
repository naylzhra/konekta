import 'package:flutter/material.dart';

import '../../../shared_widgets/konekta_tab_scaffold.dart';
import '../../booking/ui/booking_scope.dart';
import '../../booking/ui/trips_view.dart';

class TripsTab extends StatelessWidget {
  const TripsTab({super.key, required this.index});

  /// This tab's position in [PassengerMain].
  final int index;

  @override
  Widget build(BuildContext context) {
    final scope = BookingScope.of(context);
    return TripsView(
      booking: scope.dependencies.booking,
      locations: scope.locations,
      active: (KonektaTabs.maybeOf(context)?.index ?? index) == index,
    );
  }
}
