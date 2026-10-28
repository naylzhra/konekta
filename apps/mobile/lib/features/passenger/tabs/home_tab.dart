import 'package:flutter/material.dart';

import '../../../shared_widgets/konekta_tab_scaffold.dart';
import '../../booking/domain/booking_state_machine.dart';
import '../../booking/state/booking_controller.dart';
import '../../booking/ui/booking_home_section.dart';
import '../../booking/ui/booking_scope.dart';
import '../../live_tracking/state/feeder_fleet_controller.dart';
import '../../live_tracking/state/passenger_map_controller.dart';
import 'home_map_preview.dart';

class HomeTab extends StatefulWidget {
  const HomeTab({super.key, required this.map, required this.fleet});

  final PassengerMapController map;
  final FeederFleetController fleet;

  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  /// Index of the Map tab in [PassengerMain].
  static const _mapTabIndex = 2;

  BookingController? _booking;

  /// Booking whose match has already sent the passenger to the map, so
  /// coming back to Home later doesn't bounce them away again.
  String? _openedMapFor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final booking = BookingScope.of(context).dependencies.booking;
    if (booking == _booking) return;
    _booking?.removeListener(_openMapOnMatch);
    _booking = booking..addListener(_openMapOnMatch);
    // A booking already matched when Home opens was handled before.
    _openedMapFor = booking.current?.id;
  }

  @override
  void dispose() {
    _booking?.removeListener(_openMapOnMatch);
    super.dispose();
  }

  void _openMapOnMatch() {
    final current = _booking?.current;
    if (!mounted || current == null || current.id == _openedMapFor) return;
    if (current.status == BookingStatus.confirmed ||
        current.status == BookingStatus.feederArriving) {
      _openedMapFor = current.id;
      KonektaTabs.maybeOf(context)?.select(_mapTabIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = BookingScope.of(context);
    return BookingHomeSection(
      controller: scope.dependencies.booking,
      locations: scope.locations,
      onOpenMap: () => KonektaTabs.maybeOf(context)?.select(_mapTabIndex),
      mapPreview: HomeMapPreview(controller: widget.map, fleet: widget.fleet),
    );
  }
}
