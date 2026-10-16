import 'package:flutter/material.dart';

import '../../core/location/user_location_provider.dart';
import '../../shared_widgets/konekta_navbar.dart';
import '../../shared_widgets/konekta_tab_scaffold.dart';
import '../booking/ui/booking_scope.dart';
import '../live_tracking/data/feeder_position_stream.dart';
import '../live_tracking/state/passenger_map_controller.dart';
import 'booking_active_trip.dart';
import 'tabs/home_tab.dart';
import 'tabs/map_tab.dart';
import 'tabs/profile_tab.dart';
import 'tabs/trips_tab.dart';

class PassengerMain extends StatelessWidget {
  const PassengerMain({super.key, required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    return BookingScope(token: token, child: const _PassengerTabs());
  }
}

class _PassengerTabs extends StatefulWidget {
  const _PassengerTabs();

  @override
  State<_PassengerTabs> createState() => _PassengerTabsState();
}

class _PassengerTabsState extends State<_PassengerTabs> {
  WsFeederPositionStream? _feederPositions;
  BookingActiveTrip? _activeTrip;
  PassengerMapController? _map;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_map != null) return;
    final scope = BookingScope.of(context);
    final wsClient = scope.session.wsClient;
    final feederPositions = _feederPositions = WsFeederPositionStream(wsClient);
    final activeTrip = _activeTrip = BookingActiveTrip(scope.dependencies.booking);
    _map = PassengerMapController(
      trip: activeTrip,
      positions: feederPositions,
      location: GeolocatorUserLocationProvider(),
      connection: wsClient.states,
      initialConnection: wsClient.state,
    )..start();
  }

  @override
  void dispose() {
    _map?.dispose();
    _activeTrip?.dispose();
    _feederPositions?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KonektaTabScaffold(
      items: const [
        KonektaNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
        KonektaNavItem(
          icon: Icons.directions_bus_outlined,
          selectedIcon: Icons.directions_bus,
          label: 'Trips',
        ),
        KonektaNavItem(icon: Icons.map_outlined, selectedIcon: Icons.map, label: 'Map'),
        KonektaNavItem(icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Profile'),
      ],
      tabs: [const HomeTab(), const TripsTab(), MapTab(controller: _map!), const ProfileTab()],
    );
  }
}
