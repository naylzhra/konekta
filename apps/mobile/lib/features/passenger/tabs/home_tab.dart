import 'package:flutter/material.dart';

import '../../../shared_widgets/konekta_tab_scaffold.dart';
import '../../booking/ui/booking_home_section.dart';
import '../../booking/ui/booking_scope.dart';
import '../../live_tracking/state/feeder_fleet_controller.dart';
import '../../live_tracking/state/passenger_map_controller.dart';
import 'home_map_preview.dart';

class HomeTab extends StatelessWidget {
  const HomeTab({super.key, required this.map, required this.fleet});

  final PassengerMapController map;
  final FeederFleetController fleet;

  /// Index of the Map tab in [PassengerMain].
  static const _mapTabIndex = 2;

  @override
  Widget build(BuildContext context) {
    final scope = BookingScope.of(context);
    return BookingHomeSection(
      controller: scope.dependencies.booking,
      locations: scope.locations,
      onOpenMap: () => KonektaTabs.maybeOf(context)?.select(_mapTabIndex),
      mapPreview: HomeMapPreview(controller: map, fleet: fleet),
    );
  }
}
