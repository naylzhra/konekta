import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/location/user_location_provider.dart';
import '../../../core/strings/live_tracking_strings.dart';
import '../../../core/theme/konekta_theme.dart';
import '../../live_tracking/domain/feeder_models.dart';
import '../../live_tracking/state/feeder_fleet_controller.dart';
import '../../live_tracking/state/passenger_map_controller.dart';
import '../../live_tracking/ui/map_markers.dart';
import '../../live_tracking/ui/service_area_map.dart';
import '../../live_tracking/ui/route_stops_page.dart';

/// Every on-duty feeder (searchable by route), the passenger's booked feeder
/// highlighted, their pickup stop and (if they allow it) their own location.
class MapTab extends StatefulWidget {
  const MapTab({super.key, required this.controller, required this.fleet, required this.loadRoutePath});

  final PassengerMapController controller;
  final FeederFleetController fleet;
  final Future<List<LatLng>> Function(String corridorId) loadRoutePath;

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

  /// Fleet feeder whose info card is open.
  String? _selectedFeederId;
  final Map<String, List<LatLng>> _routePaths = {};
  final Set<String> _loadingPaths = {};
  final Set<String> _failedPaths = {};
  bool _routeLoadFailed = false;

  PassengerMapController get _map => widget.controller;
  FeederFleetController get _fleet => widget.fleet;

  @override
  void initState() {
    super.initState();
    _map.addListener(_autoFrame);
    _fleet.addListener(_loadAvailableRoutes);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAvailableRoutes());
    // Permission may have changed in system settings.
    _lifecycle = AppLifecycleListener(onResume: _map.refreshPermission);
  }

  @override
  void dispose() {
    _map.removeListener(_autoFrame);
    _fleet.removeListener(_loadAvailableRoutes);
    _lifecycle.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onMapReady() {
    _mapReady = true;
    _autoFrame();
    if (_map.trip == null && _routePaths.isNotEmpty) {
      _fit(_routePaths.values.expand((points) => points).toList());
    }
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
    _fit(points.isNotEmpty ? points : _routePaths.values.expand((route) => route).toList());
  }

  void _selectRoute(String? corridorId) {
    _fleet.filterByCorridor(corridorId);
    setState(() => _selectedFeederId = null);
    if (corridorId != null) {
      final points = _routePaths[corridorId];
      if (points != null && points.isNotEmpty) _fit(points);
    }
  }

  void _loadAvailableRoutes() {
    for (final corridor in _fleet.corridors) {
      if (!corridor.isDummy && !_routePaths.containsKey(corridor.id) &&
          !_failedPaths.contains(corridor.id) && _loadingPaths.add(corridor.id)) {
        _loadRoute(corridor.id);
      }
    }
  }

  Future<void> _loadRoute(String corridorId) async {
    try {
      final points = await widget.loadRoutePath(corridorId);
      if (!mounted) return;
      setState(() => _routePaths[corridorId] = points);
      if (points.isNotEmpty && (_fleet.corridorFilter == corridorId ||
          _map.trip?.corridorId == corridorId || (_map.trip == null && _routePaths.length == 1))) {
        _fit(points);
      }
    } on Object {
      _failedPaths.add(corridorId);
      if (mounted) setState(() => _routeLoadFailed = true);
    } finally {
      _loadingPaths.remove(corridorId);
    }
  }

  void _retryRoutes() {
    _failedPaths.clear();
    setState(() => _routeLoadFailed = false);
    _loadAvailableRoutes();
  }

  List<Polyline> _routeLines() {
    final selected = _fleet.corridorFilter;
    final booked = _map.trip?.corridorId;
    final ids = _routePaths.keys.toList()
      ..sort((a, b) => (a == booked ? 1 : a == selected ? 0 : -1)
          .compareTo(b == booked ? 1 : b == selected ? 0 : -1));
    return [
      for (final id in ids)
        if (_routePaths[id]!.length > 1)
          Polyline(
            points: _routePaths[id]!,
            color: id == booked ? const Color(0xFF087F5B) : id == selected ? const Color(0xFF1769AA) : const Color(0x991769AA),
            strokeWidth: id == booked ? 8 : id == selected ? 6 : 4,
          ),
    ];
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
        padding: const EdgeInsets.fromLTRB(64, 160, 64, 220),
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
      listenable: Listenable.merge([_map, _fleet]),
      builder: (context, _) {
        final permission = _map.permission;
        final selected = _selectedFleetFeeder();
        return Stack(
          children: [
            ServiceAreaMap(
              controller: _mapController,
              routePolylines: _routeLines(),
              onMapReady: _onMapReady,
              onTap: () => setState(() => _selectedFeederId = null),
              markers: passengerMapMarkers(
                _map,
                fleet: _fleet,
                selectedFeederId: _selectedFeederId,
                onTapFeeder: (id) => setState(() => _selectedFeederId = id),
              ),
            ),
            Positioned(
              top: AppSpacing.sm,
              left: AppSpacing.containerMargin,
              right: AppSpacing.containerMargin,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RouteSearch(fleet: _fleet, onSelect: _selectRoute),
                  if (_fleet.corridorFilter != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: ActionChip(
                        avatar:
                            const Icon(Icons.format_list_numbered, size: 18),
                        label: const Text('Daftar halte rute'),
                        onPressed: () =>
                            Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) => RouteStopsPage(
                              corridorId: _fleet.corridorFilter!),
                        )),
                      ),
                    ),
                  if (_fleet.selectedCorridor?.isDummy == true) ...[
                    const SizedBox(height: AppSpacing.xs),
                    const _Banner(text: 'Koridor ini belum memiliki koordinat jalan. Rute K1 tetap ditampilkan.'),
                  ],
                  if (_map.isReconnecting) ...[
                    const SizedBox(height: AppSpacing.xs),
                    const _Banner(text: LiveTrackingStrings.reconnecting),
                  ] else if (_fleet.loadFailed) ...[
                    const SizedBox(height: AppSpacing.xs),
                    GestureDetector(
                      onTap: _fleet.load,
                      child: const _Banner(
                          text: LiveTrackingStrings.fleetLoadFailed),
                    ),
                  ] else if (_routeLoadFailed && _routePaths.isEmpty) ...[
                    const SizedBox(height: AppSpacing.xs),
                    GestureDetector(
                      onTap: _retryRoutes,
                      child: const _Banner(text: 'Garis rute gagal dimuat. Ketuk untuk mencoba lagi.'),
                    ),
                  ],
                  if (permission != null &&
                      permission != LocationPermissionState.granted)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.only(top: AppSpacing.xs),
                        child: ActionChip(
                          avatar: const Icon(Icons.my_location, size: 18),
                          label: Text(
                            permission ==
                                    LocationPermissionState.serviceDisabled
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
                  if (selected != null)
                    _FleetFeederCard(feeder: selected, fleet: _fleet)
                  else
                    _TripCard(map: _map, onDuty: _fleet.onDutyCount),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// The tapped feeder while it's still on duty (and not the booked one,
  /// which the trip card already describes).
  FeederPosition? _selectedFleetFeeder() {
    final id = _selectedFeederId;
    if (id == null || id == _map.trip?.feederId) return null;
    for (final feeder in _fleet.feeders) {
      if (feeder.feederId == id) return feeder;
    }
    return null;
  }
}

/// Pickup stop, the passenger's location, the fleet and their booked feeder
/// (drawn last, so on top, in its own colour); shared by the Map tab and the
/// Home preview.
List<Marker> passengerMapMarkers(
  PassengerMapController map, {
  FeederFleetController? fleet,
  String? selectedFeederId,
  void Function(String feederId)? onTapFeeder,
}) {
  final booked = map.feeder;
  final trip = map.trip;
  final me = map.myLocation;
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
    if (fleet != null)
      for (final feeder in fleet.feeders)
        if (feeder.feederId != trip?.feederId)
          Marker(
            point: LatLng(feeder.lat, feeder.lng),
            width: FleetFeederMarker.size,
            height: FleetFeederMarker.size,
            child: GestureDetector(
              onTap: onTapFeeder == null
                  ? null
                  : () => onTapFeeder(feeder.feederId),
              child: FleetFeederMarker(
                  full: feeder.isFull,
                  selected: feeder.feederId == selectedFeederId),
            ),
          ),
    if (booked != null)
      Marker(
        point: LatLng(booked.lat, booked.lng),
        width: FeederMarker.size,
        height: FeederMarker.size,
        child: FeederMarker(stale: map.status == FeederTrackingStatus.stale),
      ),
  ];
}

/// Search field filtering the fleet by route (corridor).
class _RouteSearch extends StatefulWidget {
  const _RouteSearch({required this.fleet, required this.onSelect});

  final FeederFleetController fleet;
  final void Function(String? corridorId) onSelect;

  @override
  State<_RouteSearch> createState() => _RouteSearchState();
}

class _RouteSearchState extends State<_RouteSearch> {
  final _text = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _text.text = widget.fleet.selectedCorridor?.name ?? '';
    _focus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _select(String? corridorId) {
    _text.text = widget.fleet.corridor(corridorId)?.name ?? '';
    _focus.unfocus();
    widget.onSelect(corridorId);
  }

  @override
  Widget build(BuildContext context) {
    final fleet = widget.fleet;
    final filtered = fleet.corridorFilter != null;
    // While editing, the text is a query; once a route is picked, show all
    // routes again on focus so switching is one tap.
    final query = filtered && _text.text == fleet.selectedCorridor?.name
        ? ''
        : _text.text;
    final results = fleet.searchRoutes(query);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: AppColors.surfaceContainerLowest,
          elevation: 3,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: TextField(
            controller: _text,
            focusNode: _focus,
            onChanged: (_) => setState(() {}),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) {
              if (results.length == 1) _select(results.single.id);
            },
            decoration: InputDecoration(
              hintText: LiveTrackingStrings.searchRouteHint,
              prefixIcon: const Icon(Icons.search, color: AppColors.primary),
              suffixIcon: filtered || _text.text.isNotEmpty
                  ? IconButton(
                      tooltip: LiveTrackingStrings.clearRoute,
                      icon: const Icon(Icons.close),
                      onPressed: () => _select(null),
                    )
                  : null,
              filled: false,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              contentPadding:
                  const EdgeInsets.symmetric(vertical: AppSpacing.md),
            ),
          ),
        ),
        if (_focus.hasFocus)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.base),
            child: Material(
              color: AppColors.surfaceContainerLowest,
              elevation: 3,
              borderRadius: BorderRadius.circular(AppRadius.md),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 240),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    if (query.isEmpty)
                      ListTile(
                        leading: const Icon(Icons.layers_outlined),
                        title: const Text(LiveTrackingStrings.allRoutes),
                        subtitle: Text(LiveTrackingStrings.routeFeeders(
                            fleet.onDutyCount)),
                        selected: !filtered,
                        onTap: () => _select(null),
                      ),
                    for (final corridor in results)
                      ListTile(
                        leading: const Icon(Icons.route_outlined),
                        title: Text(corridor.isDummy ? '${corridor.name} (dummy)' : corridor.name),
                        subtitle: Text(LiveTrackingStrings.routeFeeders(
                            fleet.onDutyOn(corridor.id))),
                        selected: corridor.id == fleet.corridorFilter,
                        onTap: () => _select(corridor.id),
                      ),
                    if (results.isEmpty)
                      const ListTile(
                          title: Text(LiveTrackingStrings.noRouteFound)),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Details of a fleet feeder tapped on the map.
class _FleetFeederCard extends StatelessWidget {
  const _FleetFeederCard({required this.feeder, required this.fleet});

  final FeederPosition feeder;
  final FeederFleetController fleet;

  @override
  Widget build(BuildContext context) {
    final option = fleet.feederOption(feeder.feederId);
    final corridor = fleet.corridor(fleet.corridorIdOf(feeder));
    final capacity = feeder.capacity ?? option?.capacity;
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
            Row(
              children: [
                Expanded(
                  child: Text(
                    LiveTrackingStrings.fleetFeederTitle(
                        option?.number, feeder.feederId),
                    style: AppTextStyles.headlineMd,
                  ),
                ),
                if (feeder.isFull)
                  Text(LiveTrackingStrings.full,
                      style: AppTextStyles.labelMd
                          .copyWith(color: AppColors.error)),
              ],
            ),
            if (corridor != null) ...[
              const SizedBox(height: AppSpacing.base),
              Text(corridor.isDummy ? '${corridor.name} (dummy)' : corridor.name,
                  style: AppTextStyles.bodySm),
            ],
            const SizedBox(height: AppSpacing.base),
            Text(
              capacity == null
                  ? LiveTrackingStrings.occupancy(feeder.occupancy)
                  : LiveTrackingStrings.seats(feeder.occupancy, capacity),
              style: AppTextStyles.bodySm,
            ),
            const SizedBox(height: AppSpacing.base),
            const Text(LiveTrackingStrings.bookFromHome,
                style: AppTextStyles.bodySm),
          ],
        ),
      ),
    );
  }
}

class _TripCard extends StatelessWidget {
  const _TripCard({required this.map, required this.onDuty});

  final PassengerMapController map;

  /// On-duty feeders in the fleet.
  final int onDuty;

  @override
  Widget build(BuildContext context) {
    final trip = map.trip;
    final feeder = map.feeder;
    final (title, lines, isWarning) = switch (map.status) {
      FeederTrackingStatus.none => (
          LiveTrackingStrings.noActiveTrip,
          [
            LiveTrackingStrings.noActiveTripHint,
            if (onDuty > 0) LiveTrackingStrings.feedersOnDuty(onDuty)
          ],
          false,
        ),
      FeederTrackingStatus.searching => (
          LiveTrackingStrings.searchingFeeder,
          _pickupLine(trip),
          false
        ),
      FeederTrackingStatus.waiting => (
          LiveTrackingStrings.feederTitle(trip!.feederId!),
          [LiveTrackingStrings.waitingFeederPosition, ..._pickupLine(trip)],
          false,
        ),
      FeederTrackingStatus.live => (
          LiveTrackingStrings.feederTitle(trip!.feederId!),
          [
            if (trip.onBoard) LiveTrackingStrings.onBoard,
            if (map.feederToPickupM != null)
              LiveTrackingStrings.toPickup(_distance(map.feederToPickupM!)),
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
            if (feeder != null)
              LiveTrackingStrings.feederStaleSince(
                  _clock(feeder.updatedAt.toLocal())),
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
                style: isWarning
                    ? AppTextStyles.bodySm.copyWith(color: AppColors.error)
                    : AppTextStyles.bodySm,
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

  static String _clock(DateTime t) => [t.hour, t.minute, t.second]
      .map((v) => v.toString().padLeft(2, '0'))
      .join(':');
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
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.xs),
        child: Text(text,
            style: AppTextStyles.bodySm
                .copyWith(color: AppColors.inverseOnSurface)),
      ),
    );
  }
}
