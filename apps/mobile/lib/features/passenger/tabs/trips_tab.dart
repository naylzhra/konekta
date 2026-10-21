import 'package:flutter/material.dart';

import '../../booking/ui/booking_scope.dart';
import '../../booking/ui/trips_view.dart';

class TripsTab extends StatelessWidget {
  const TripsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final dependencies = BookingScope.of(context).dependencies;
    return TripsView(booking: dependencies.booking, history: dependencies.history);
  }
}
