import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/location/user_location_provider.dart';
import '../../../core/navigation/nav_instructions.dart';
import '../../../core/strings/live_tracking_strings.dart';
import '../../../core/theme/konekta_theme.dart';
import '../../booking/domain/booking_models.dart';
import '../../booking/domain/booking_state_machine.dart';
import '../../booking/domain/journey_models.dart';
import '../../booking/state/booking_controller.dart';
import '../../live_tracking/domain/feeder_models.dart';
import '../../live_tracking/state/feeder_fleet_controller.dart';
import '../../live_tracking/state/passenger_map_controller.dart';
import '../../live_tracking/ui/map_markers.dart';
import '../../live_tracking/ui/service_area_map.dart';
import '../../live_tracking/ui/route_detail_page.dart';
import '../../../shared_widgets/nav_banner.dart';

/// Every on-duty feeder, the passenger's booked feeder highlighted, their
/// pickup stop and (if they allow it) their own location. A bottom sheet
/// lists the routes: tap one for its detail page, or watch several at once.
class MapTab extends StatefulWidget {
  const MapTab({super.key, required this.controller, required this.fleet, required this.loadRoutePath,
    required this.loadRouteStops, required this.loadArrivals, this.booking, this.loadJourney});

  final PassengerMapController controller;
  final FeederFleetController fleet;
  final Future<List<LatLng>> Function(String corridorId) loadRoutePath;
  final Future<CorridorRoute> Function(String corridorId, RouteDirection direction) loadRouteStops;
  final Future<List<StopArrivals>> Function(String corridorId, RouteDirection direction) loadArrivals;
  final BookingController? booking;
  final Future<Journey> Function(String bookingId, GeoPoint? location)? loadJourney;

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
  Journey? _journey;
  String? _journeyKey;
  LatLng? _lastJourneyLocation;
  DateTime? _lastJourneyAt;
  int _journeyRequest = 0;

  /// While a journey is active the camera follows the passenger, heading-up,
  /// until they pan the map themselves.
  bool _following = true;
  static const _navZoom = 17.5;

  // Route sheet: share of the tab's height, tracked so the recenter button
  // and camera framing stay clear of it.
  static const _sheetInitial = 0.45;
  static const _sheetMin = 0.15;
  static const _sheetMax = 0.9;
  final _sheetExtent = ValueNotifier<double>(_sheetInitial);
  double _bodyHeight = 0;

  /// "Pantau beberapa" mode: the list shows checkboxes and a watch button.
  bool _multi = false;

  /// Route ids ticked in that mode.
  Set<String> _picked = {};
  final _routeQuery = TextEditingController();

  PassengerMapController get _map => widget.controller;
  FeederFleetController get _fleet => widget.fleet;

  @override
  void initState() {
    super.initState();
    _map.addListener(_autoFrame);
    widget.booking?.addListener(_maybeLoadJourney);
    _fleet.addListener(_loadAvailableRoutes);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAvailableRoutes();
      _maybeLoadJourney();
    });
    // Permission may have changed in system settings.
    _lifecycle = AppLifecycleListener(onResume: _map.refreshPermission);
  }

  @override
  void dispose() {
    _map.removeListener(_autoFrame);
    widget.booking?.removeListener(_maybeLoadJourney);
    _fleet.removeListener(_loadAvailableRoutes);
    _lifecycle.dispose();
    _mapController.dispose();
    _sheetExtent.dispose();
    _routeQuery.dispose();
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
    _maybeLoadJourney();
    if (!_mapReady) return;
    if (_followMe()) return;
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

  /// Keeps the camera on the passenger during an active journey; false when
  /// not following, so the caller frames the trip instead.
  bool _followMe() {
    final me = _map.myLocation;
    if (_journey == null || !_following || me == null) return false;
    final heading = me.headingDeg;
    _mapController.moveAndRotate(
        LatLng(me.lat, me.lng), _navZoom, heading == null ? 0 : -heading);
    return true;
  }

  List<LatLng> _tripPoints() {
    final feeder = _map.feeder;
    final trip = _map.trip;
    return [
      if (feeder != null) LatLng(feeder.lat, feeder.lng),
      if (trip?.pickup != null && !trip!.onBoard) trip.pickup!,
      if (_journey != null)
        ..._journey!.current.points.map((point) => LatLng(point.lat, point.lng)),
    ];
  }

  void _maybeLoadJourney() {
    final booking = widget.booking?.current;
    final load = widget.loadJourney;
    if (!mounted || booking == null || load == null ||
        (!booking.isActive && booking.status != BookingStatus.completed)) {
      if (_journey != null) {
        setState(() => _journey = null);
        if (_mapReady) _mapController.rotate(0);
      }
      return;
    }
    final stopUpdate = widget.booking?.pickupStopUpdate;
    final key = '${booking.id}:${booking.status.wire}:${stopUpdate?.location.lat}:${stopUpdate?.location.lng}';
    final me = _map.myLocation;
    final here = me == null ? null : LatLng(me.lat, me.lng);
    final now = DateTime.now();
    final moved = here != null && _lastJourneyLocation != null &&
        const Distance().as(LengthUnit.Meter, here, _lastJourneyLocation!) >= 50;
    final elapsed = _lastJourneyAt == null || now.difference(_lastJourneyAt!) >= const Duration(seconds: 20);
    if (key == _journeyKey && !(moved && elapsed)) return;
    _journeyKey = key;
    _lastJourneyLocation = here;
    _lastJourneyAt = now;
    final request = ++_journeyRequest;
    load(booking.id, me == null ? null : GeoPoint(lat: me.lat, lng: me.lng)).then((journey) {
      if (!mounted || request != _journeyRequest) return;
      final first = _journey == null;
      setState(() {
        _journey = journey;
        if (first) _following = true;
      });
      if (_mapReady && !_followMe()) _fit(_tripPoints());
    }).catchError((Object _) {
      if (!mounted || request != _journeyRequest) return;
    });
  }

  void _recenter() {
    if (_journey != null) {
      setState(() => _following = true);
      if (_followMe()) return;
    }
    final me = _map.myLocation;
    final points = [..._tripPoints(), if (me != null) LatLng(me.lat, me.lng)];
    _fit(points.isNotEmpty ? points : _routePaths.values.expand((route) => route).toList());
  }

  /// Narrows the map to [corridorIds] (all routes when empty) and frames them.
  void _watchRoutes(Set<String> corridorIds) {
    _fleet.filterByCorridors(corridorIds);
    setState(() {
      _selectedFeederId = null;
      _multi = false;
    });
    final points = [for (final id in corridorIds) ...?_routePaths[id]];
    _fit(points.isNotEmpty ? points : _routePaths.values.expand((route) => route).toList());
  }

  /// Corridors of the routes with these ids.
  Set<String> _corridorsOf(Iterable<String> routeIds) => {
        for (final route in _fleet.routes)
          if (routeIds.contains(route.id)) ...route.corridorIds,
      };

  /// Ids of the routes the map is narrowed to.
  Set<String> _watchedRoutes() => {
        for (final route in _fleet.routes)
          if (route.corridorIds.any(_fleet.corridorFilters.contains)) route.id,
      };

  Future<void> _openRoute(TransitRoute route) async {
    final follow = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => RouteDetailPage(
        route: route,
        loadStops: (direction) => widget.loadRouteStops(route.primary.id, direction),
        loadArrivals: (direction) => widget.loadArrivals(route.primary.id, direction),
        feederNumber: (feederId) => _fleet.feederOption(feederId)?.number,
        following: setEquals(_fleet.corridorFilters, route.corridorIds),
      ),
    ));
    if (follow == true && mounted) _watchRoutes(route.corridorIds);
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
      if (points.isNotEmpty && (_fleet.corridorFilters.contains(corridorId) ||
          _map.trip?.corridorId == corridorId || (_map.trip == null && _routePaths.length == 1))) {
        _fit(points);
      }
    } on Object {
      _failedPaths.add(corridorId);
    } finally {
      _loadingPaths.remove(corridorId);
    }
  }

  /// Every route, or only the watched ones (plus the booked one) while the
  /// map is narrowed.
  List<Polyline> _routeLines() {
    final watched = _fleet.corridorFilters;
    final booked = _map.trip?.corridorId;
    int rank(String id) => id == booked ? 1 : watched.contains(id) ? 0 : -1;
    final ids = [
      for (final id in _routePaths.keys)
        if (watched.isEmpty || watched.contains(id) || id == booked) id,
    ]..sort((a, b) => rank(a).compareTo(rank(b)));
    return [
      for (final id in ids)
        if (_routePaths[id]!.length > 1)
          Polyline(
            points: _routePaths[id]!,
            color: id == booked
                ? const Color(0xFF087F5B)
                : watched.contains(id)
                    ? const Color(0xFF1769AA)
                    : const Color(0x991769AA),
            strokeWidth: id == booked ? 8 : watched.contains(id) ? 6 : 4,
          ),
      if (_journey != null && _journey!.current.points.length > 1)
        Polyline(
          points: _journey!.current.points.map((p) => LatLng(p.lat, p.lng)).toList(),
          color: navRouteBlue,
          borderColor: navRouteBorder,
          borderStrokeWidth: 2,
          strokeWidth: 7,
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
        padding: EdgeInsets.fromLTRB(64, 120, 64, _sheetExtent.value * _bodyHeight + 32),
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
    return LayoutBuilder(
      builder: (context, constraints) {
        _bodyHeight = constraints.maxHeight;
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
                  onUserGesture: _journey != null && _following
                      ? () => setState(() => _following = false)
                      : null,
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
                      // During a journey the instruction bar sits on top, as
                      // in turn-by-turn navigation.
                      if (_journey != null)
                        _JourneyBanner(stage: _journey!.current, me: _map.myLocation),
                      if (_fleet.selectedCorridor?.isDummy == true) ...[
                        const SizedBox(height: AppSpacing.xs),
                        const _Banner(text: 'Koridor ini belum memiliki koordinat jalan. Rute K1 tetap ditampilkan.'),
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
                // Rides just above the sheet as it is dragged.
                ValueListenableBuilder<double>(
                  valueListenable: _sheetExtent,
                  builder: (context, extent, child) => Positioned(
                    right: AppSpacing.containerMargin,
                    bottom: extent * _bodyHeight + AppSpacing.sm,
                    child: child!,
                  ),
                  child: _journey != null && !_following
                      ? FloatingActionButton.extended(
                          heroTag: null,
                          onPressed: _recenter,
                          icon: const Icon(Icons.navigation),
                          label: const Text(LiveTrackingStrings.recenterOnMe),
                        )
                      : FloatingActionButton.small(
                          heroTag: null,
                          tooltip: LiveTrackingStrings.recenter,
                          onPressed: _recenter,
                          child: const Icon(Icons.center_focus_strong),
                        ),
                ),
                NotificationListener<DraggableScrollableNotification>(
                  onNotification: (notification) {
                    _sheetExtent.value = notification.extent;
                    return false;
                  },
                  child: DraggableScrollableSheet(
                    initialChildSize: _sheetInitial,
                    minChildSize: _sheetMin,
                    maxChildSize: _sheetMax,
                    snap: true,
                    snapSizes: const [_sheetInitial],
                    builder: (context, scroll) => _routeSheet(scroll, selected),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Trip status (when there is one), then every route: tap for its detail
  /// page, or tick several in "Pantau beberapa" mode and watch them.
  Widget _routeSheet(ScrollController scroll, FeederPosition? selected) {
    final routes = _fleet.searchRoutes(_routeQuery.text);
    final watched = _watchedRoutes();
    final Widget? status = selected != null
        ? _FleetFeederCard(feeder: selected, fleet: _fleet)
        : _journey != null
            ? _JourneyCard(journey: _journey!)
            : _map.status != FeederTrackingStatus.none
                ? _TripCard(map: _map, onDuty: _fleet.onDutyCount)
                : null;
    return Material(
      color: AppColors.surfaceContainerLowest,
      elevation: 8,
      shadowColor: const Color(0x33000000),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.containerMargin,
                AppSpacing.sm,
                AppSpacing.containerMargin,
                AppSpacing.md,
              ),
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.outlineVariant,
                      borderRadius: BorderRadius.circular(AppRadius.full),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (status != null) ...[status, const SizedBox(height: AppSpacing.md)],
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        LiveTrackingStrings.routesTitle,
                        style: AppTextStyles.headlineMd.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.inverseSurface,
                        ),
                      ),
                    ),
                    const Text(LiveTrackingStrings.watchMultiple, style: AppTextStyles.bodySm),
                    Switch(
                      value: _multi,
                      onChanged: (on) => setState(() {
                        _multi = on;
                        _picked = {...watched};
                      }),
                    ),
                  ],
                ),
                TextField(
                  controller: _routeQuery,
                  onChanged: (_) => setState(() {}),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: LiveTrackingStrings.searchRouteHint,
                    prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                    suffixIcon: _routeQuery.text.isEmpty
                        ? null
                        : IconButton(
                            tooltip: LiveTrackingStrings.clearRoute,
                            icon: const Icon(Icons.close),
                            onPressed: () => setState(_routeQuery.clear),
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                if (_multi)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Text(LiveTrackingStrings.pickRoutesHint, style: AppTextStyles.bodySm),
                  )
                else if (watched.isNotEmpty)
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          LiveTrackingStrings.watchingRoutes([
                            for (final route in _fleet.routes)
                              if (watched.contains(route.id)) route.name,
                          ]),
                          style: AppTextStyles.bodySm.copyWith(color: AppColors.primary),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _watchRoutes(const {}),
                        child: const Text(LiveTrackingStrings.showAllRoutes),
                      ),
                    ],
                  ),
                if (_fleet.loadFailed && _fleet.corridors.isEmpty)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.refresh),
                    title: const Text(LiveTrackingStrings.fleetLoadFailed),
                    onTap: _fleet.load,
                  )
                else if (routes.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    child: Text(LiveTrackingStrings.noRouteFound, style: AppTextStyles.bodySm),
                  ),
                for (final route in routes)
                  _RouteTile(
                    route: route,
                    onDuty: _fleet.onDutyOnRoute(route),
                    multi: _multi,
                    picked: _picked.contains(route.id),
                    watched: watched.contains(route.id),
                    onTap: _multi
                        ? () => setState(() {
                              if (!_picked.remove(route.id)) _picked.add(route.id);
                            })
                        : () => _openRoute(route),
                  ),
              ],
            ),
          ),
          if (_multi)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.containerMargin,
                AppSpacing.xs,
                AppSpacing.containerMargin,
                AppSpacing.md,
              ),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _picked.isEmpty ? null : () => _watchRoutes(_corridorsOf(_picked)),
                  child: Text(LiveTrackingStrings.watchRoutes(_picked.length)),
                ),
              ),
            ),
        ],
      ),
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

/// A route in the sheet: badge, name and feeders on duty. Checkbox in
/// "Pantau beberapa" mode, else a chevron to its detail page.
class _RouteTile extends StatelessWidget {
  const _RouteTile({
    required this.route,
    required this.onDuty,
    required this.multi,
    required this.picked,
    required this.watched,
    required this.onTap,
  });

  final TransitRoute route;
  final int onDuty;
  final bool multi;
  final bool picked;
  final bool watched;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            RouteBadge(id: route.id, size: 36),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    route.isDummy ? '${route.name} (dummy)' : route.name,
                    style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600, color: AppColors.inverseSurface),
                  ),
                  Text(LiveTrackingStrings.routeFeeders(onDuty), style: AppTextStyles.bodySm),
                ],
              ),
            ),
            if (multi)
              Checkbox(value: picked, onChanged: (_) => onTap())
            else ...[
              if (watched) const Icon(Icons.visibility_outlined, size: 18, color: AppColors.primary),
              const Icon(Icons.chevron_right, color: AppColors.onSurfaceVariant),
            ],
          ],
        ),
      ),
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

String _journeyDistance(double meters) =>
    meters < 1000 ? '${meters.round()} m' : '${(meters / 1000).toStringAsFixed(1)} km';

String _journeyAction(JourneyStage stage) => switch (stage.mode) {
      'walk' => 'Jalan ke ${stage.destinationName}',
      'motorcycle' => 'Naik motor ke ${stage.destinationName}',
      'car' => 'Naik mobil ke ${stage.destinationName}',
      _ => 'Naik feeder ke ${stage.destinationName}',
    };

class _JourneyBanner extends StatelessWidget {
  const _JourneyBanner({required this.stage, required this.me});

  final JourneyStage stage;
  final UserLocation? me;

  @override
  Widget build(BuildContext context) {
    final here = me == null ? null : LatLng(me!.lat, me!.lng);
    // Only walking legs are the passenger's to navigate; on the feeder the
    // bar just says where they are headed.
    final step = stage.mode == 'walk' && here != null
        ? upcomingStep(stage.steps, here)
        : null;
    return NavBanner(
      step: step,
      here: here,
      arrivalName: stage.destinationName,
      fallback: _journeyAction(stage),
      fallbackIcon: stage.mode == 'walk' ? Icons.directions_walk : Icons.directions_bus,
    );
  }
}

class _JourneyCard extends StatelessWidget {
  const _JourneyCard({required this.journey});

  final Journey journey;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surfaceContainerLowest,
        elevation: 3,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            NavEtaRow(durationS: journey.current.durationS, distanceM: journey.current.distanceM),
            Text(_journeyAction(journey.current), style: AppTextStyles.headlineMd),
            const SizedBox(height: AppSpacing.sm),
            const Text('Tahap perjalanan', style: AppTextStyles.bodySm),
            const SizedBox(height: AppSpacing.xs),
            for (final stage in journey.stages) Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(stage.status == 'completed' ? Icons.check_circle :
                    stage.mode == 'walk' ? Icons.directions_walk : Icons.directions_bus,
                    size: 20, color: stage.status == 'active' ? AppColors.primary : AppColors.onSurface),
                const SizedBox(width: AppSpacing.xs),
                Expanded(child: Text(_journeyAction(stage), style: AppTextStyles.bodySm.copyWith(
                  fontWeight: stage.status == 'active' ? FontWeight.w700 : FontWeight.w400,
                ))),
                Text(stage.status == 'active' ? _journeyDistance(stage.distanceM) :
                    stage.status == 'completed' ? 'Selesai' : 'Berikutnya', style: AppTextStyles.bodySm),
              ]),
            ),
          ]),
        ),
      );
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
