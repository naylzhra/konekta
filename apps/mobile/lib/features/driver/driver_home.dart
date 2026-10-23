import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../core/api/api_client.dart';
import '../../core/location/user_location_provider.dart';
import '../../core/navigation/nav_instructions.dart';
import '../../core/strings/account_strings.dart';
import '../../core/strings/driver_strings.dart';
import '../../core/strings/live_tracking_strings.dart';
import '../../core/theme/konekta_theme.dart';
import '../../shared_widgets/konekta_navbar.dart';
import '../../shared_widgets/konekta_tab_scaffold.dart';
import '../../shared_widgets/loading_indicator.dart';
import '../../shared_widgets/nav_banner.dart';
import '../account/account_page.dart';
import '../live_tracking/data/feeder_api.dart';
import '../live_tracking/domain/feeder_models.dart';
import '../live_tracking/state/driver_duty_controller.dart';
import '../live_tracking/ui/map_markers.dart';
import '../live_tracking/ui/service_area_map.dart';
import 'data/driver_trip_api.dart';
import 'driver_sheet.dart';

class DriverHome extends StatefulWidget {
  const DriverHome({super.key, required this.token});

  final String token;

  @override
  State<DriverHome> createState() => _DriverHomeState();
}

class _DriverHomeState extends State<DriverHome> {
  static const _taskPollInterval = Duration(seconds: 20);
  static const _navRefreshInterval = Duration(seconds: 10);
  static const _offRouteM = 40.0;
  static const _nearStopM = 50.0;
  static const _navZoom = 17.5;

  final _mapController = MapController();
  late final GeolocatorUserLocationProvider _location;
  late final DriverDutyController _duty;
  late final FeederApi _feederApi = FeederApi(ApiClient());
  late final DriverTripApi _trip = DriverTripApi(ApiClient(), widget.token);
  bool _mapReady = false;
  String? _routeCorridorId;
  String? _loadingCorridorId;
  List<LatLng> _routePath = const [];
  List<CorridorRouteStop> _routeStops = const [];

  List<DriverTaskStop>? _tasks;
  bool _tasksFailed = false;
  Timer? _taskPoll;
  bool _wasOnDuty = false;

  /// Stop the driver picked from the sheet; null means "closest".
  String? _chosenStopId;
  DriverNavigation? _nav;
  bool _navLoading = false;
  bool _navFailed = false;
  DateTime? _navFetchedAt;
  bool _following = true;
  String? _actingStopId;

  @override
  void initState() {
    super.initState();
    _location =
        GeolocatorUserLocationProvider(settings: _dutyLocationSettings())
          ..rationale = _showRationale;
    _duty = DriverDutyController(
        api: FeederApi(ApiClient()), token: widget.token, location: _location)
      ..addListener(_onDutyChanged)
      ..load();
  }

  @override
  void dispose() {
    _taskPoll?.cancel();
    _duty
      ..removeListener(_onDutyChanged)
      ..dispose();
    _mapController.dispose();
    super.dispose();
  }

  static LocationSettings _dutyLocationSettings() {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return const LocationSettings(accuracy: LocationAccuracy.high);
    }
    return AndroidSettings(
      accuracy: LocationAccuracy.high,
      intervalDuration: const Duration(seconds: 5),
      foregroundNotificationConfig: const ForegroundNotificationConfig(
        notificationTitle: LiveTrackingStrings.notificationTitle,
        notificationText: LiveTrackingStrings.notificationText,
        notificationChannelName: LiveTrackingStrings.notificationChannel,
        enableWakeLock: true,
        setOngoing: true,
      ),
    );
  }

  Future<bool> _showRationale() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(LiveTrackingStrings.rationaleTitle),
        content: const Text(LiveTrackingStrings.rationaleBody),
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

  LatLng? get _here {
    final fix = _duty.lastLocation;
    return fix == null ? null : LatLng(fix.lat, fix.lng);
  }

  void _onDutyChanged() {
    final corridorId = _duty.feeder?.corridorId;
    if (corridorId != null &&
        corridorId != _routeCorridorId &&
        corridorId != _loadingCorridorId) {
      unawaited(_loadAssignedRoute(corridorId));
    }
    if (_duty.feeder != null && _tasks == null && !_tasksFailed) {
      unawaited(_loadTasks());
    }
    if (_duty.isOnDuty != _wasOnDuty) {
      _wasOnDuty = _duty.isOnDuty;
      _duty.isOnDuty ? _enterNavigation() : _leaveNavigation();
    }
    if (!_duty.isOnDuty) return;
    final here = _here;
    if (here == null) return;
    if (_following) _moveCamera(here);
    _maybeRefreshNav(here);
  }

  void _enterNavigation() {
    _taskPoll?.cancel();
    _taskPoll = Timer.periodic(_taskPollInterval, (_) => _loadTasks());
    setState(() => _following = true);
    unawaited(_loadTasks());
  }

  void _leaveNavigation() {
    _taskPoll?.cancel();
    setState(() {
      _nav = null;
      _navFetchedAt = null;
      _chosenStopId = null;
    });
    if (_mapReady) {
      _mapController.rotate(0);
      _fitAssignedRoute();
    }
  }

  void _moveCamera(LatLng here) {
    if (!_mapReady) return;
    final heading = _duty.lastLocation?.headingDeg;
    // Heading-up like turn-by-turn apps; north-up until the GPS knows it.
    _mapController.moveAndRotate(here, _navZoom, heading == null ? 0 : -heading);
  }

  void _recenter() {
    setState(() => _following = true);
    final here = _here;
    if (here != null) _moveCamera(here);
  }

  Future<void> _loadAssignedRoute(String corridorId) async {
    _loadingCorridorId = corridorId;
    try {
      final results = await Future.wait<Object>([
        _feederApi.routePath(corridorId),
        _feederApi.routeStops(corridorId),
      ]);
      if (!mounted || _duty.feeder?.corridorId != corridorId) return;
      setState(() {
        _routeCorridorId = corridorId;
        _routePath = results[0] as List<LatLng>;
        _routeStops = (results[1] as CorridorRoute).stops;
      });
      if (_mapReady && !_duty.isOnDuty) _fitAssignedRoute();
    } catch (_) {
      // Duty and live position remain usable even if route details are down.
    } finally {
      if (_loadingCorridorId == corridorId) _loadingCorridorId = null;
    }
  }

  void _fitAssignedRoute() {
    final points = [
      ..._routePath,
      for (final stop in _routeStops)
        if (stop.lat != null && stop.lng != null) LatLng(stop.lat!, stop.lng!),
    ];
    if (!_mapReady || points.isEmpty) return;
    _mapController.fitCamera(CameraFit.coordinates(
      coordinates: points,
      padding: const EdgeInsets.fromLTRB(48, 80, 48, 320),
      maxZoom: 16,
    ));
  }

  Future<void> _loadTasks() async {
    if (_duty.feeder == null) return;
    try {
      final tasks = await _trip.stops();
      if (!mounted) return;
      final changed = _taskKey(tasks) != _taskKey(_tasks ?? const []);
      setState(() {
        _tasks = tasks;
        _tasksFailed = false;
      });
      // Passenger counts on the target and upcoming stops come with the
      // route, so refresh it when bookings change.
      final here = _here;
      if (changed && _duty.isOnDuty && here != null) {
        _navFetchedAt = null;
        _maybeRefreshNav(here);
      }
    } catch (_) {
      if (mounted) setState(() => _tasksFailed = true);
    }
  }

  static String _taskKey(List<DriverTaskStop> tasks) =>
      [for (final t in tasks) '${t.stopId}:${t.phase.name}:${t.seats}'].join(',');

  void _maybeRefreshNav(LatLng here) {
    if (_navLoading) return;
    final fetchedAt = _navFetchedAt;
    final stale = fetchedAt == null ||
        DateTime.now().difference(fetchedAt) > _navRefreshInterval;
    if (!stale && !_offRoute(here)) return;
    unawaited(_fetchNav(here));
  }

  bool _offRoute(LatLng here) {
    final points = _nav?.points;
    if (points == null || points.isEmpty) return false;
    return points.every((p) => metresTo(here, p) > _offRouteM);
  }

  Future<void> _fetchNav(LatLng here) async {
    setState(() => _navLoading = true);
    _navFetchedAt = DateTime.now();
    try {
      final nav = await _trip.navigation(here, stopId: _chosenStopId);
      if (!mounted) return;
      setState(() {
        _nav = nav;
        _navFailed = false;
        // Once reached, a hand-picked stop gives way to the route order again.
        if (nav != null && _chosenStopId != null &&
            metresTo(here, nav.target.location) < _nearStopM &&
            !nav.target.hasPassengers) {
          _chosenStopId = null;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _navFailed = true);
    } finally {
      if (mounted) setState(() => _navLoading = false);
    }
  }

  void _chooseStop(String stopId) {
    setState(() {
      _chosenStopId = stopId;
      _following = true;
    });
    final here = _here;
    if (here == null) return;
    _moveCamera(here);
    unawaited(_fetchNav(here));
  }

  Future<void> _markArrived(NavStop stop) =>
      _stopEvent(stop, arrived: true);

  Future<void> _markDeparted(NavStop stop) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(DriverStrings.departTitle),
        content: const Text(DriverStrings.departBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text(DriverStrings.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(DriverStrings.departed)),
        ],
      ),
    );
    if (confirmed == true && mounted) await _stopEvent(stop, arrived: false);
  }

  Future<void> _stopEvent(NavStop stop, {required bool arrived}) async {
    final feederId = _duty.feeder?.id;
    if (feederId == null) return;
    setState(() => _actingStopId = stop.stopId);
    final messenger = ScaffoldMessenger.of(context);
    try {
      arrived
          ? await _trip.markArrived(stop.stopId, feederId)
          : await _trip.markDeparted(stop.stopId, feederId);
      messenger.showSnackBar(SnackBar(
          content: Text(arrived
              ? DriverStrings.arrivedLogged
              : DriverStrings.departedLogged)));
      if (!arrived && _chosenStopId == stop.stopId) _chosenStopId = null;
      _navFetchedAt = null;
      await _loadTasks();
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text(DriverStrings.eventFailed)));
    } finally {
      if (mounted) setState(() => _actingStopId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return KonektaTabScaffold(
      items: const [
        KonektaNavItem(
            icon: Icons.map_outlined,
            selectedIcon: Icons.map,
            label: DriverStrings.tabDuty),
        KonektaNavItem(
            icon: Icons.person_outline,
            selectedIcon: Icons.person,
            label: AccountStrings.profile),
      ],
      tabs: [
        _dutyHome(),
        ListenableBuilder(
          listenable: _duty,
          builder: (context, _) => AccountPage(
              token: widget.token,
              role: 'driver',
              feederLabel: _duty.feeder == null
                  ? null
                  : LiveTrackingStrings.feederLabel(
                      _duty.feeder!.number, _duty.feeder!.corridorName),
              beforeLogout: () => _duty.stopDuty()),
        ),
      ],
    );
  }

  Widget _dutyHome() {
    return Scaffold(
      body: ListenableBuilder(
        listenable: _duty,
        builder: (context, _) => switch (_duty.status) {
          DutyStatus.loading => const LoadingIndicator(),
          DutyStatus.loadFailed => _Message(
              text: _duty.issue == DutyIssue.sessionExpired
                  ? LiveTrackingStrings.sessionExpired
                  : LiveTrackingStrings.loadFailed,
              action: TextButton(
                  onPressed: _duty.load,
                  child: const Text(LiveTrackingStrings.retry)),
            ),
          DutyStatus.noFeeder =>
            const _Message(text: LiveTrackingStrings.noFeeder),
          _ => _mapWithSheet(),
        },
      ),
    );
  }

  Widget _mapWithSheet() {
    final navigating = _duty.isOnDuty;
    final here = _here;
    final nav = _nav;
    final target = nav?.target;
    final nearTarget = here != null &&
        target != null &&
        metresTo(here, target.location) < _nearStopM;
    return Stack(
      children: [
        Positioned.fill(
          child: ServiceAreaMap(
            controller: _mapController,
            onMapReady: () {
              _mapReady = true;
              final at = _here;
              _duty.isOnDuty && at != null
                  ? _moveCamera(at)
                  : _fitAssignedRoute();
            },
            onUserGesture: navigating && _following
                ? () => setState(() => _following = false)
                : null,
            routePolylines: [
              if (_routePath.length > 1)
                Polyline(
                  points: _routePath,
                  color: navigating
                      ? AppColors.primary.withValues(alpha: 0.35)
                      : AppColors.primary,
                  strokeWidth: navigating ? 4 : 5,
                ),
              if (navigating && nav != null && nav.points.length > 1)
                Polyline(
                  points: nav.points,
                  color: navRouteBlue,
                  borderColor: navRouteBorder,
                  borderStrokeWidth: 2,
                  strokeWidth: 7,
                ),
            ],
            markers: [
              for (final stop in _routeStops)
                if (stop.lat != null && stop.lng != null)
                  Marker(
                    point: LatLng(stop.lat!, stop.lng!),
                    width: 30,
                    height: 30,
                    child: _RouteStopMarker(
                        position: stop.position,
                        isTarget: navigating &&
                            target?.position == stop.position),
                  ),
              for (final task in _tasks ?? const <DriverTaskStop>[])
                if (task.location != null)
                  Marker(
                    point: task.location!,
                    width: 44,
                    height: 52,
                    alignment: Alignment.topCenter,
                    child: TaskStopMarker(
                        stop: task,
                        isTarget: task.stopId == target?.stopId),
                  ),
              if (here != null)
                Marker(
                  point: here,
                  width: FeederMarker.size,
                  height: FeederMarker.size,
                  child: const FeederMarker(),
                ),
            ],
          ),
        ),
        if (navigating)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: NavBanner(
                step: here == null || nav == null
                    ? null
                    : upcomingStep(nav.steps, here),
                here: here,
                arrivalName: target?.name,
                fallback: _navFailed
                    ? DriverStrings.routeUnavailable
                    : DriverStrings.routing,
              ),
            ),
          ),
        if (navigating && !_following)
          Positioned(
            right: AppSpacing.md,
            bottom: MediaQuery.sizeOf(context).height * 0.36,
            child: FloatingActionButton.extended(
              heroTag: 'recenter',
              onPressed: _recenter,
              icon: const Icon(Icons.navigation),
              label: const Text(DriverStrings.recenter),
            ),
          ),
        DriverSheet(
          duty: _duty,
          tasks: _tasks,
          tasksFailed: _tasksFailed,
          onRetryTasks: _loadTasks,
          corridorId: _duty.feeder?.corridorId,
          navigation: nav,
          nearTarget: nearTarget,
          actingStopId: _actingStopId,
          onChoose: _chooseStop,
          onArrived: _markArrived,
          onDeparted: _markDeparted,
        ),
      ],
    );
  }
}

class _RouteStopMarker extends StatelessWidget {
  const _RouteStopMarker({required this.position, this.isTarget = false});

  final int position;
  final bool isTarget;

  @override
  Widget build(BuildContext context) => Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isTarget ? navGreen : AppColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: isTarget ? 3 : 2),
          boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
        ),
        child: Text('$position',
            style: AppTextStyles.labelMd
                .copyWith(color: Colors.white, fontSize: 11)),
      );
}

class _Message extends StatelessWidget {
  const _Message({required this.text, this.action});

  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.containerMargin),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text,
                style: AppTextStyles.bodyMd, textAlign: TextAlign.center),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.md),
              action!
            ],
          ],
        ),
      ),
    );
  }
}
