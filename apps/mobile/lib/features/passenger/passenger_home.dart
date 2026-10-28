import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../core/location/user_location_provider.dart';
import '../../core/strings/account_strings.dart';
import '../../shared_widgets/konekta_navbar.dart';
import '../../shared_widgets/konekta_tab_scaffold.dart';
import '../booking/ui/booking_scope.dart';
import '../booking/data/journey_api.dart';
import '../live_tracking/data/feeder_api.dart';
import '../live_tracking/data/feeder_position_stream.dart';
import '../live_tracking/domain/feeder_models.dart';
import '../live_tracking/state/feeder_fleet_controller.dart';
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

/// Both directions of a corridor as one line: the forward route ends where
/// the return route starts (and vice versa), so they join into a loop.
Future<List<LatLng>> Function(String) _bothDirections(FeederApi api) =>
    (corridorId) async {
      final forward = await api.routePath(corridorId);
      try {
        return [...forward, ...await api.routePath(corridorId, direction: RouteDirection.backward)];
      } on FeederApiException {
        return forward;
      }
    };

class _PassengerTabs extends StatefulWidget {
  const _PassengerTabs();

  @override
  State<_PassengerTabs> createState() => _PassengerTabsState();
}

class _PassengerTabsState extends State<_PassengerTabs> {
  WsFeederPositionStream? _feederPositions;
  BookingActiveTrip? _activeTrip;
  PassengerMapController? _map;
  FeederFleetController? _fleet;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_map != null) return;
    final scope = BookingScope.of(context);
    final wsClient = scope.session.wsClient;
    final feederPositions = _feederPositions = WsFeederPositionStream(wsClient);
    final activeTrip =
        _activeTrip = BookingActiveTrip(scope.dependencies.booking);
    _map = PassengerMapController(
      trip: activeTrip,
      positions: feederPositions,
      location: GeolocatorUserLocationProvider(),
      connection: wsClient.states,
      initialConnection: wsClient.state,
    )..start();
    final feederApi = FeederApi(scope.session.apiClient);
    final token = scope.session.token;
    _fleet = FeederFleetController(
      loadCorridors: feederApi.listCorridors,
      loadLive: () => feederApi.liveFeeders(token),
      positions: feederPositions,
      connection: wsClient.states,
    )..start();
  }

  @override
  void dispose() {
    _fleet?.dispose();
    _map?.dispose();
    _activeTrip?.dispose();
    _feederPositions?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KonektaTabScaffold(
      items: const [
        KonektaNavItem(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home,
            label: 'Beranda'),
        KonektaNavItem(
          icon: Icons.directions_bus_outlined,
          selectedIcon: Icons.directions_bus,
          label: 'Perjalanan',
        ),
        KonektaNavItem(
            icon: Icons.map_outlined, selectedIcon: Icons.map, label: 'Peta'),
        KonektaNavItem(
            icon: Icons.person_outline,
            selectedIcon: Icons.person,
            label: AccountStrings.profile),
      ],
      tabs: [
        HomeTab(map: _map!, fleet: _fleet!),
        const TripsTab(),
        MapTab(
          controller: _map!,
          fleet: _fleet!,
          booking: BookingScope.of(context).dependencies.booking,
          loadJourney: JourneyApi(BookingScope.of(context).session.apiClient,
                  BookingScope.of(context).session.token)
              .load,
          loadRoutePath: _bothDirections(FeederApi(BookingScope.of(context).session.apiClient)),
        ),
        const ProfileTab(),
      ],
    );
  }
}
