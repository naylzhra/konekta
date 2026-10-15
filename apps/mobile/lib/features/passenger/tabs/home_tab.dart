import 'package:flutter/material.dart';

import '../../booking/ui/booking_home_section.dart';
import '../../booking/ui/booking_scope.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key});

  @override
  Widget build(BuildContext context) {
    final scope = BookingScope.of(context);
    return BookingHomeSection(controller: scope.dependencies.booking, locations: scope.locations);
  }
}
