import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/location/user_location_provider.dart';
import '../../../core/strings/live_tracking_strings.dart';
import '../../../core/theme/konekta_theme.dart';
import '../../live_tracking/state/passenger_map_controller.dart';
import '../../live_tracking/ui/map_markers.dart';
import '../../live_tracking/ui/service_area_map.dart';

/// Live position of the passenger's assigned feeder, their pickup stop and
/// (if they allow it) their own location.
class MapTab extends StatefulWidget {
  const MapTab({super.key, required this.controller});

  final PassengerMapController controller;

  @override
  State<MapTab> createState() => _MapTabState();
}

class _MapTabState extends State<MapTab> {
  final _mapController = MapController();
  late final AppLifecycleListener _lifecycle;
  bool _mapReady = false;

  // Auto-framing happens once per feeder (and once for the passenger's first
  // fix) so it never fights the user panning the map.
  String? _framedFeederId;
  bool _framedMe = false;

  PassengerMapController get _map => widget.controller;

  @override
  void initState() {
    super.initState();
    _map.addListener(_autoFrame);
    // Permission may have changed in system settings.
    _lifecycle = AppLifecycleListener(onResume: _map.refreshPermission);
  }

  @override
  void dispose() {
    _map.removeListener(_autoFrame);
    _lifecycle.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onMapReady() {
    _mapReady = true;
    _autoFrame();
  }

  void _autoFrame() {
    if (!_mapReady) return;
    final feeder = _map.feeder;
    if (feeder != null && feeder.feederId != _framedFeederId) {
      _framedFeederId = feeder.feederId;
      _framedMe = true;
      _fit(_tripPoints());
      return;
    }
    final me = _map.myLocation;
    if (!_framedMe && me != null && _map.trip == null) {
      _framedMe = true;
      _mapController.move(LatLng(me.lat, me.lng), _mapController.camera.zoom);
    }
  }

  List<LatLng> _tripPoints() {
    final feeder = _map.feeder;
    final trip = _map.trip;
    return [
      if (feeder != null) LatLng(feeder.lat, feeder.lng),
      if (trip?.pickup != null && !trip!.onBoard) trip.pickup!,
    ];
  }

  void _recenter() {
    final me = _map.myLocation;
    final points = [..._tripPoints(), if (me != null) LatLng(me.lat, me.lng)];
    _fit(points);
  }

  void _fit(List<LatLng> points) {
    if (!_mapReady || points.isEmpty) return;
    if (points.length == 1) {
      _mapController.move(points.single, 16);
      return;
    }
    _mapController.fitCamera(
      CameraFit.coordinates(
        coordinates: points,
        padding: const EdgeInsets.fromLTRB(64, 96, 64, 220),
        maxZoom: 17,
      ),
    );
  }

  Future<void> _enableMyLocation() async {
    switch (_map.permission) {
      case LocationPermissionState.deniedForever:
        await Geolocator.openAppSettings();
      case LocationPermissionState.serviceDisabled:
        await Geolocator.openLocationSettings();
      default:
        if (!await _showRationale()) return;
        await _map.enableMyLocation();
    }
  }

  Future<bool> _showRationale() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(LiveTrackingStrings.passengerRationaleTitle),
        content: const Text(LiveTrackingStrings.passengerRationaleBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(LiveTrackingStrings.rationaleCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(LiveTrackingStrings.rationaleContinue),
          ),
        ],
      ),
    );
    return accepted ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _map,
      builder: (context, _) {
        final permission = _map.permission;
        return Stack(
          children: [
            ServiceAreaMap(controller: _mapController, onMapReady: _onMapReady, markers: _markers()),
            Positioned(
              top: AppSpacing.sm,
              left: AppSpacing.containerMargin,
              right: AppSpacing.containerMargin,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_map.isReconnecting) const _Banner(text: LiveTrackingStrings.reconnecting),
                  if (permission != null && permission != LocationPermissionState.granted)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: ActionChip(
                          avatar: const Icon(Icons.my_location, size: 18),
                          label: Text(
                            permission == LocationPermissionState.serviceDisabled
                                ? LiveTrackingStrings.turnOnGps
                                : LiveTrackingStrings.showMyLocation,
                          ),
                          onPressed: _enableMyLocation,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Positioned(
              left: AppSpacing.containerMargin,
              right: AppSpacing.containerMargin,
              bottom: AppSpacing.md,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  FloatingActionButton.small(
                    heroTag: null,
                    tooltip: LiveTrackingStrings.recenter,
                    onPressed: _recenter,
                    child: const Icon(Icons.center_focus_strong),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _TripCard(map: _map),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<Marker> _markers() {
    final feeder = _map.feeder;
    final trip = _map.trip;
    final me = _map.myLocation;
    return [
      if (trip?.pickup != null && !trip!.onBoard)
        Marker(
          point: trip.pickup!,
          width: PickupStopMarker.size,
          height: PickupStopMarker.size,
          alignment: Alignment.topCenter,
          child: const PickupStopMarker(),
        ),
      if (me != null)
        Marker(
          point: LatLng(me.lat, me.lng),
          width: UserLocationMarker.size,
          height: UserLocationMarker.size,
          child: const UserLocationMarker(),
        ),
      if (feeder != null)
        Marker(
          point: LatLng(feeder.lat, feeder.lng),
          width: FeederMarker.size,
          height: FeederMarker.size,
          child: FeederMarker(stale: _map.status == FeederTrackingStatus.stale),
        ),
    ];
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.map});

  final PassengerMapController map;

  @override
  Widget build(BuildContext context) {
    final trip = map.trip;
    final feeder = map.feeder;
    final (title, lines, isWarning) = switch (map.status) {
      FeederTrackingStatus.none => (
          LiveTrackingStrings.noActiveTrip,
          [LiveTrackingStrings.noActiveTripHint],
          false,
        ),
      FeederTrackingStatus.searching => (LiveTrackingStrings.searchingFeeder, _pickupLine(trip), false),
      FeederTrackingStatus.waiting => (
          LiveTrackingStrings.feederTitle(trip!.feederId!),
          [LiveTrackingStrings.waitingFeederPosition, ..._pickupLine(trip)],
          false,
        ),
      FeederTrackingStatus.live => (
          LiveTrackingStrings.feederTitle(trip!.feederId!),
          [
            if (trip.onBoard) LiveTrackingStrings.onBoard,
            if (map.feederToPickupM != null) LiveTrackingStrings.toPickup(_distance(map.feederToPickupM!)),
            ..._pickupLine(trip),
            '${LiveTrackingStrings.occupancy(feeder!.occupancy)} · '
                '${LiveTrackingStrings.updatedAt(_clock(feeder.updatedAt.toLocal()))}',
          ],
          false,
        ),
      FeederTrackingStatus.stale => (
          LiveTrackingStrings.feederTitle(trip!.feederId!),
          [
            LiveTrackingStrings.feederStale,
            if (feeder != null) LiveTrackingStrings.feederStaleSince(_clock(feeder.updatedAt.toLocal())),
          ],
          true,
        ),
    };
    return Material(
      color: AppColors.surfaceContainerLowest,
      elevation: 3,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: AppTextStyles.headlineMd),
            for (final line in lines) ...[
              const SizedBox(height: AppSpacing.base),
              Text(
                line,
                style: isWarning ? AppTextStyles.bodySm.copyWith(color: AppColors.error) : AppTextStyles.bodySm,
              ),
            ],
          ],
        ),
      ),
    );
  }

  static List<String> _pickupLine(ActiveTrip? trip) {
    final name = trip?.pickupName;
    if (name == null || trip!.onBoard) return const [];
    return [LiveTrackingStrings.pickupAt(name)];
  }

  static String _distance(double meters) {
    if (meters < 1000) return '± ${meters.round()} m';
    return '± ${(meters / 1000).toStringAsFixed(1).replaceAll('.', ',')} km';
  }

  static String _clock(DateTime t) =>
      [t.hour, t.minute, t.second].map((v) => v.toString().padLeft(2, '0')).join(':');
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.inverseSurface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        child: Text(text, style: AppTextStyles.bodySm.copyWith(color: AppColors.inverseOnSurface)),
      ),
    );
  }
}
