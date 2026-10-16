import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../live_tracking/state/feeder_fleet_controller.dart';
import '../../live_tracking/state/passenger_map_controller.dart';
import '../../live_tracking/ui/service_area_map.dart';
import 'map_tab.dart';

/// Non-interactive version of the Map tab's map for the Home hero, fleet
/// included. Follows the booked feeder, else the pickup stop, else the
/// passenger's location.
class HomeMapPreview extends StatefulWidget {
  const HomeMapPreview({super.key, required this.controller, required this.fleet});

  final PassengerMapController controller;
  final FeederFleetController fleet;

  @override
  State<HomeMapPreview> createState() => _HomeMapPreviewState();
}

class _HomeMapPreviewState extends State<HomeMapPreview> {
  final _mapController = MapController();
  bool _mapReady = false;
  LatLng? _centered;

  PassengerMapController get _map => widget.controller;

  @override
  void initState() {
    super.initState();
    _map.addListener(_follow);
  }

  @override
  void dispose() {
    _map.removeListener(_follow);
    _mapController.dispose();
    super.dispose();
  }

  void _onMapReady() {
    _mapReady = true;
    _follow();
  }

  LatLng? _focus() {
    final feeder = _map.feeder;
    if (feeder != null) return LatLng(feeder.lat, feeder.lng);
    final trip = _map.trip;
    if (trip?.pickup != null && !trip!.onBoard) return trip.pickup;
    final me = _map.myLocation;
    return me == null ? null : LatLng(me.lat, me.lng);
  }

  void _follow() {
    final focus = _focus();
    if (!_mapReady || focus == null || focus == _centered) return;
    _centered = focus;
    _mapController.move(focus, _mapController.camera.zoom);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([_map, widget.fleet]),
      builder: (context, _) => ServiceAreaMap(
        controller: _mapController,
        onMapReady: _onMapReady,
        initialCenter: _focus(),
        markers: passengerMapMarkers(_map, fleet: widget.fleet),
        interactive: false,
      ),
    );
  }
}
