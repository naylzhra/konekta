import 'package:flutter/material.dart';

import '../../shared_widgets/konekta_navbar.dart';
import '../../shared_widgets/konekta_tab_scaffold.dart';
import 'tabs/home_tab.dart';
import 'tabs/map_tab.dart';
import 'tabs/profile_tab.dart';
import 'tabs/trips_tab.dart';


class PassengerMain extends StatelessWidget {
  const PassengerMain({super.key, required this.token});

  final String token;

  @override
  Widget build(BuildContext context) {
    return const KonektaTabScaffold(
      items: [
        KonektaNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home, label: 'Home'),
        KonektaNavItem(
          icon: Icons.directions_bus_outlined,
          selectedIcon: Icons.directions_bus,
          label: 'Trips',
        ),
        KonektaNavItem(icon: Icons.map_outlined, selectedIcon: Icons.map, label: 'Map'),
        KonektaNavItem(icon: Icons.person_outline, selectedIcon: Icons.person, label: 'Profile'),
      ],
      tabs: [HomeTab(), TripsTab(), MapTab(), ProfileTab()],
    );
  }
}
