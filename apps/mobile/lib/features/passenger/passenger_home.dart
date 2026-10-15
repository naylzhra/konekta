import 'package:flutter/material.dart';

import '../../core/location/user_location_provider.dart';
import '../../shared_widgets/konekta_navbar.dart';
import '../../shared_widgets/konekta_tab_scaffold.dart';
import '../booking/booking_session.dart';
import '../live_tracking/data/feeder_position_stream.dart';
import '../live_tracking/state/passenger_map_controller.dart';
import 'booking_active_trip.dart';
import 'tabs/home_tab.dart';
import 'tabs/map_tab.dart';
import 'tabs/profile_tab.dart';
import 'tabs/trips_tab.dart';

/// Owns the passenger's session (DESIGN.md §5.5): the shared WsClient's
/// connect/dispose and the objects the tabs read from.
class PassengerMain extends StatefulWidget {
  const PassengerMain({super.key, required this.token});

  final String token;

  @override
  State<PassengerMain> createState() => _PassengerMainState();
}

class _PassengerMainState extends State<PassengerMain> {
  late final BookingSession _session;
  late final BookingDependencies _booking;
  late final WsFeederPositionStream _feederPositions;
  late final BookingActiveTrip _activeTrip;
  late final PassengerMapController _map;

  @override
  void initState() {
    super.initState();
    _session = BookingSession.create(token: widget.token);
    _booking = BookingDependencies.create(_session);
    _feederPositions = WsFeederPositionStream(_session.wsClient);
    _activeTrip = BookingActiveTrip(_booking.booking);
    _map = PassengerMapController(
      trip: _activeTrip,
      positions: _feederPositions,
      location: GeolocatorUserLocationProvider(),
      connection: _session.wsClient.states,
      initialConnection: _session.wsClient.state,
    );
    _session.wsClient.connect();
    _booking.booking.start();
    _map.start();
  }

  @override
  void dispose() {
    _map.dispose();
    _activeTrip.dispose();
    _booking.dispose();
    _feederPositions.dispose();
    _session.wsClient.dispose();
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
      tabs: [const HomeTab(), const TripsTab(), MapTab(controller: _map), const ProfileTab()],
    );
  }
}
