import 'package:flutter/material.dart';

import '../../../shared_widgets/konekta_tab_scaffold.dart';
import '../../booking/ui/booking_home_section.dart';
import '../../booking/ui/booking_scope.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  /// Index of the Map tab in [PassengerMain].
  static const _mapTabIndex = 2;

  @override
  Widget build(BuildContext context) {
    final scope = BookingScope.of(context);
    return BookingHomeSection(
      controller: scope.dependencies.booking,
      locations: scope.locations,
      onOpenMap: () => KonektaTabs.maybeOf(context)?.select(_mapTabIndex),
    );
  }
}
