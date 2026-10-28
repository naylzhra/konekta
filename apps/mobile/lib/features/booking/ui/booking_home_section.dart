import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/strings/booking_strings.dart';
import '../../../core/theme/konekta_theme.dart';
import '../../live_tracking/domain/service_area.dart';
import '../../live_tracking/ui/service_area_map.dart';
import '../data/trip_locations.dart';
import '../domain/booking_failure.dart';
import '../domain/booking_models.dart';
import '../state/booking_controller.dart';
import 'active_booking_card.dart';
import 'booking_widgets.dart';
import 'home_widgets.dart';

/// Home tab content: greeting, search, map preview, and quick actions.
/// Booking itself (consent -> destination -> plan -> confirm) lives in
/// [_TripPlannerPage]; once a booking exists, its live status replaces the
/// search and quick actions here (DESIGN.md §1).
class BookingHomeSection extends StatelessWidget {
  const BookingHomeSection({
    super.key,
    required this.controller,
    required this.locations,
    this.onOpenMap,
    this.mapPreview,
  });

  final BookingController controller;
  final TripLocations locations;

  /// Switches to the Map tab (Route Info, locate button).
  final VoidCallback? onOpenMap;

  /// Live map for the hero; a stylised placeholder when null.
  final Widget? mapPreview;

  void _openPlanner(BuildContext context) {
    Navigator.of(context)
        .push<void>(
          MaterialPageRoute(builder: (_) => _TripPlannerPage(controller: controller, locations: locations)),
        )
        // Drop unconfirmed plans so reopening starts clean.
        .then((_) => controller.clearPlans());
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final hasBooking = controller.current != null;
        return ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.containerMargin,
            AppSpacing.lg,
            AppSpacing.containerMargin,
            AppSpacing.lg,
          ),
          children: [
            Text(
              BookingStrings.homeTitle,
              style: AppTextStyles.headlineLg.copyWith(
                fontSize: 28,
                height: 36 / 28,
                fontWeight: FontWeight.w700,
                color: AppColors.inverseSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.base),
            const Text(BookingStrings.homeSubtitle, style: AppTextStyles.bodyMd),
            const SizedBox(height: AppSpacing.lg),
            if (!hasBooking) ...[
              HomeSearchBar(onTap: () => _openPlanner(context)),
              const SizedBox(height: AppSpacing.md),
            ],
            HomeMapHero(nearbyFeeders: HomeStats.nearbyFeeders, onLocate: onOpenMap, map: mapPreview),
            const SizedBox(height: AppSpacing.md),
            if (hasBooking)
              ActiveBookingCard(controller: controller)
            else
              // Fixed height: `stretch` needs a bounded height inside a ListView.
              SizedBox(
                height: 148,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: HomeActionCard(
                        icon: Icons.directions_car_filled_outlined,
                        label: BookingStrings.bookFeeder,
                        filled: true,
                        onTap: () => _openPlanner(context),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: HomeActionCard(
                        icon: Icons.route,
                        label: BookingStrings.routeInfo,
                        onTap: onOpenMap,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Full-screen booking flow. Closes itself once a booking exists so Home shows
/// its live status.
class _TripPlannerPage extends StatefulWidget {
  const _TripPlannerPage({required this.controller, required this.locations});

  final BookingController controller;
  final TripLocations locations;

  @override
  State<_TripPlannerPage> createState() => _TripPlannerPageState();
}

class _TripPlannerPageState extends State<_TripPlannerPage> {
  bool _closing = false;

  void _closeOnce() {
    if (_closing) return;
    _closing = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).maybePop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    // Back from the route list returns to destination selection first.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, child) => PopScope(
        canPop: controller.planning == PlanningStatus.idle,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) controller.clearPlans();
        },
        child: child!,
      ),
      child: Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(
            BookingStrings.plannerTitle,
            style: AppTextStyles.headlineMd.copyWith(fontWeight: FontWeight.w700, color: AppColors.inverseSurface),
          ),
        ),
        body: SafeArea(
          bottom: false,
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              if (controller.current != null) _closeOnce();
              if (controller.consent == ConsentState.required) {
                return ListView(
                  padding: const EdgeInsets.all(AppSpacing.containerMargin),
                  children: [
                    _ConsentCard(controller: controller),
                  ],
                );
              }
              return _TripPlanner(controller: controller, locations: widget.locations);
            },
          ),
        ),
      ),
    );
  }
}

class _ConsentCard extends StatefulWidget {
  const _ConsentCard({required this.controller});

  final BookingController controller;

  @override
  State<_ConsentCard> createState() => _ConsentCardState();
}

class _ConsentCardState extends State<_ConsentCard> {
  bool _saving = false;

  Future<void> _accept() async {
    setState(() => _saving = true);
    await widget.controller.setConsent(granted: true);
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final error = widget.controller.actionError;
    return BookingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.privacy_tip_outlined, color: AppColors.primary),
              SizedBox(width: AppSpacing.xs),
              Expanded(child: Text(BookingStrings.consentTitle, style: AppTextStyles.headlineMd)),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          const Text(BookingStrings.consentBody, style: AppTextStyles.bodyMd),
          const SizedBox(height: AppSpacing.xs),
          Text(BookingStrings.consentPolicy(consentPolicyVersion), style: AppTextStyles.bodySm),
          if (error != null && error.code != BookingFailureCode.consentRequired) ...[
            const SizedBox(height: AppSpacing.sm),
            BookingErrorNotice(error: error, onDismiss: widget.controller.clearActionError),
          ],
          const SizedBox(height: AppSpacing.md),
          ElevatedButton(
            onPressed: _saving ? null : _accept,
            child: _saving
                ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text(BookingStrings.consentAccept),
          ),
        ],
      ),
    );
  }
}

class _TripPlanner extends StatefulWidget {
  const _TripPlanner({required this.controller, required this.locations});

  final BookingController controller;
  final TripLocations locations;

  @override
  State<_TripPlanner> createState() => _TripPlannerState();
}

class _TripPlannerState extends State<_TripPlanner> {
  final _plannerMapController = MapController();
  bool _plannerMapReady = false;
  final _query = TextEditingController();
  final _queryFocus = FocusNode();
  GeoPoint? _origin;
  bool _loadingOrigin = true;
  String? _locationMessage;

  /// The searched place: the destination. The origin is always [_origin].
  TripPlace? _place;
  List<TripPlace> _suggestions = const [];
  int _searchRequest = 0;

  @override
  void initState() {
    super.initState();
    // The suggestion list is shown while the destination field has focus.
    _queryFocus.addListener(() {
      if (mounted) setState(() {});
    });
    widget.controller.addListener(_showNearestStop);
    _loadOrigin();
    _search('');
  }

  @override
  void dispose() {
    widget.controller.removeListener(_showNearestStop);
    _query.dispose();
    _queryFocus.dispose();
    _plannerMapController.dispose();
    super.dispose();
  }

  Future<void> _loadOrigin() async {
    setState(() => _loadingOrigin = true);
    GeoPoint? origin;
    try {
      origin = await widget.locations.currentOrigin();
    } on Object {
      origin = null;
    }
    if (!mounted) return;
    setState(() {
      _origin = origin;
      _loadingOrigin = false;
      _locationMessage = _originOutsideMessage;
    });
    if (_plannerMapReady && origin != null && ServiceArea.contains(origin.lat, origin.lng)) {
      _plannerMapController.move(LatLng(origin.lat, origin.lng), 15);
    }
    // A destination picked while the location was loading is planned now.
    if (_place != null && widget.controller.planning == PlanningStatus.idle) _plan();
  }

  NearestStopHint? get _nearestStopHint =>
      widget.controller.planning == PlanningStatus.failed ? widget.controller.planError?.nearestStop : null;
  NearestStopHint? _framedHint;

  /// When no route exists, frame the origin and the suggested stop.
  void _showNearestStop() {
    final hint = _nearestStopHint;
    if (identical(hint, _framedHint)) return;
    _framedHint = hint;
    final origin = _origin;
    if (hint == null || origin == null || !_plannerMapReady) return;
    _plannerMapController.fitCamera(CameraFit.coordinates(
      coordinates: [LatLng(origin.lat, origin.lng), LatLng(hint.stop.location.lat, hint.stop.location.lng)],
      // Clear of the endpoints card above and the error sheet below.
      padding: const EdgeInsets.fromLTRB(48, 140, 48, 280),
      maxZoom: 16,
    ));
  }

  /// The origin is always the GPS location; outside Bandung no trip can be planned.
  String? get _originOutsideMessage => _origin != null && !ServiceArea.contains(_origin!.lat, _origin!.lng)
      ? 'Lokasimu di luar area layanan Bandung.'
      : null;

  Future<void> _search(String query) async {
    final request = ++_searchRequest;
    List<TripPlace> results;
    try {
      results = await widget.locations.searchDestinations(query);
    } on Object {
      results = const [];
    }
    if (!mounted || request != _searchRequest) return;
    setState(() => _suggestions = results);
  }

  void _onQueryChanged(String query) {
    // Editing the text drops the previous pick and any plans made for it.
    if (_place != null) {
      widget.controller.clearPlans();
      setState(() => _place = null);
    }
    _search(query);
  }

  /// Picking a destination fills the field and goes straight to route options.
  void _select(TripPlace place) {
    _queryFocus.unfocus();
    widget.controller.clearPlans();
    _query.text = place.name;
    setState(() {
      _place = place;
      _locationMessage = _originOutsideMessage;
    });
    _plan();
  }

  void _selectOnMap(LatLng point) {
    final selected = GeoPoint(lat: point.latitude, lng: point.longitude);
    if (!ServiceArea.contains(selected.lat, selected.lng)) {
      setState(() => _locationMessage = 'Titik berada di luar area layanan Bandung.');
      return;
    }
    _select(TripPlace(id: 'map', name: 'Titik pada peta', location: selected));
  }

  void _plan() {
    final here = _origin;
    final place = _place;
    if (here == null || place == null) return;
    if (!ServiceArea.contains(here.lat, here.lng) ||
        !ServiceArea.contains(place.location.lat, place.location.lng)) {
      setState(() => _locationMessage = 'Asal dan tujuan harus berada di area layanan Bandung.');
      return;
    }
    widget.controller.clearActionError();
    unawaited(
      widget.controller.planTrip(
        origin: here,
        destination: place.location,
      ),
    );
  }

  static final _sheetTitleStyle = AppTextStyles.headlineMd.copyWith(
    fontWeight: FontWeight.w700,
    color: AppColors.inverseSurface,
  );

  /// Full-height suggestions under the endpoints card, while the field has focus.
  Widget _suggestionList() {
    return ListView(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.containerMargin - AppSpacing.base,
        AppSpacing.xs,
        AppSpacing.containerMargin - AppSpacing.base,
        AppSpacing.md + MediaQuery.paddingOf(context).bottom,
      ),
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: AppSpacing.base, vertical: AppSpacing.xs),
          child: Text(BookingStrings.suggestedPlaces, style: AppTextStyles.labelMd),
        ),
        if (_suggestions.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.base),
            child: Text(BookingStrings.noDestinationMatch, style: AppTextStyles.bodySm),
          ),
        for (final place in _suggestions) _PlaceTile(place: place, onTap: () => _select(place)),
        if (widget.locations.isPlaceholder)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.base),
            child: Text(BookingStrings.placeholderLocations, style: AppTextStyles.labelMd),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final canPlan = _origin != null && _place != null &&
        ServiceArea.contains(_origin!.lat, _origin!.lng) &&
        ServiceArea.contains(_place!.location.lat, _place!.location.lng) &&
        controller.planning != PlanningStatus.loading;

    final currentLocation = _OriginRow(
      loading: _loadingOrigin,
      available: _origin != null,
      label: BookingStrings.currentLocation,
      onRetry: _loadOrigin,
    );
    final placeField = TextField(
      controller: _query,
      focusNode: _queryFocus,
      onChanged: _onQueryChanged,
      textInputAction: TextInputAction.search,
      style: _EndpointRow.valueStyle,
      decoration: InputDecoration(
        isCollapsed: true,
        // Explicit, or the app theme's padding makes this row taller than the origin row.
        contentPadding: EdgeInsets.zero,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        hintText: BookingStrings.destinationHint,
        hintStyle: _EndpointRow.valueStyle.copyWith(color: AppColors.outline, fontWeight: FontWeight.w500),
      ),
    );

    final idle = controller.planning == PlanningStatus.idle;
    final searching = _queryFocus.hasFocus;
    final hint = _nearestStopHint;
    final routeSheet = Material(
      color: AppColors.surfaceContainerLowest,
      elevation: 8,
      shadowColor: const Color(0x33000000),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      clipBehavior: Clip.antiAlias,
      child: _RouteOptions(
        controller: controller,
        onReplan: canPlan ? _plan : null,
        originLabel: BookingStrings.currentLocation,
        destinationLabel: _place?.name ?? BookingStrings.destination,
      ),
    );

    // The map fills the page; the endpoints card and the route sheet float
    // over it. While searching, the suggestion list covers the map.
    return PopScope(
      // Back closes the suggestion list before leaving the page.
      canPop: !searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _queryFocus.unfocus();
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: ServiceAreaMap(
              controller: _plannerMapController,
              onMapReady: () => _plannerMapReady = true,
              initialCenter: _origin != null && ServiceArea.contains(_origin!.lat, _origin!.lng)
                  ? LatLng(_origin!.lat, _origin!.lng)
                  : ServiceArea.center,
              // Picking on the map only applies while choosing the destination.
              onMapTap: idle ? _selectOnMap : null,
              markers: [
                if (_origin != null && ServiceArea.contains(_origin!.lat, _origin!.lng))
                  Marker(point: LatLng(_origin!.lat, _origin!.lng), width: 40, height: 40,
                    child: const Icon(Icons.trip_origin, color: AppColors.primary, size: 32)),
                if (_place != null)
                  Marker(point: LatLng(_place!.location.lat, _place!.location.lng), width: 44, height: 44,
                    child: const Icon(Icons.location_on, color: AppColors.secondary, size: 40)),
                if (hint != null)
                  Marker(point: LatLng(hint.stop.location.lat, hint.stop.location.lng), width: 36, height: 36,
                    child: const _StopMarker()),
              ],
            ),
          ),
          if (searching) const Positioned.fill(child: ColoredBox(color: AppColors.surfaceContainerLowest)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.containerMargin,
                  AppSpacing.xs,
                  AppSpacing.containerMargin,
                  AppSpacing.xs,
                ),
                child: _EndpointsCard(
                  origin: currentLocation,
                  destination: placeField,
                ),
              ),
              Expanded(
                child: searching
                    ? _suggestionList()
                    : idle
                    ? _mapControls()
                    // A failed plan keeps the map (and any suggested stop) in view.
                    : controller.planning == PlanningStatus.failed
                    ? Align(alignment: Alignment.bottomCenter, child: routeSheet)
                    : routeSheet,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Location message and locate button, over the map below the endpoints card.
  Widget _mapControls() {
    return Stack(
      children: [
        if (_locationMessage != null)
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.containerMargin),
              child: Material(
                color: AppColors.surfaceContainerLowest,
                elevation: 2,
                shadowColor: const Color(0x33000000),
                borderRadius: BorderRadius.circular(AppRadius.lg),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                  child: Text(_locationMessage!, style: AppTextStyles.bodySm.copyWith(color: AppColors.error)),
                ),
              ),
            ),
          ),
        Align(
          alignment: Alignment.bottomRight,
          child: Padding(
            padding: EdgeInsets.only(
              right: AppSpacing.md,
              bottom: AppSpacing.md + MediaQuery.paddingOf(context).bottom,
            ),
            child: Material(
              color: Colors.white,
              shape: const CircleBorder(),
              elevation: 3,
              child: IconButton(
                tooltip: BookingStrings.locate,
                onPressed: _loadingOrigin ? null : _loadOrigin,
                icon: const Icon(Icons.my_location, color: AppColors.inverseSurface),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Origin/destination card.
class _EndpointsCard extends StatelessWidget {
  const _EndpointsCard({required this.origin, required this.destination});

  final Widget origin;
  final Widget destination;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.surfaceContainerHighest),
        boxShadow: [
          BoxShadow(
              color: AppColors.inverseSurface.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Stack(
        children: [
          // Connector between the two endpoint icons.
          const Positioned(
            left: 9,
            top: 32,
            bottom: 32,
            child: SizedBox(width: 1.5, child: ColoredBox(color: AppColors.outlineVariant)),
          ),
          Column(
            children: [
              _EndpointRow(
                icon: Icons.my_location,
                iconColor: AppColors.secondary,
                label: BookingStrings.origin,
                child: origin,
              ),
              const Divider(height: 1, indent: 32, color: AppColors.surfaceContainerHighest),
              _EndpointRow(
                icon: Icons.location_on_outlined,
                iconColor: AppColors.error,
                label: BookingStrings.destination,
                child: destination,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EndpointRow extends StatelessWidget {
  const _EndpointRow({required this.icon, required this.iconColor, required this.label, required this.child});

  final IconData icon;
  final Color iconColor;
  final String label;
  final Widget child;

  static final valueStyle = AppTextStyles.bodyMd.copyWith(
    fontWeight: FontWeight.w700,
    color: AppColors.inverseSurface,
  );

  @override
  Widget build(BuildContext context) {
    // No visible label, to keep the card compact: the icon and hint text
    // identify the row; screen readers still get the label.
    return Semantics(
      label: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}

class _OriginRow extends StatelessWidget {
  const _OriginRow({required this.loading, required this.available, required this.label, required this.onRetry});

  final bool loading;
  final bool available;
  final String label;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: LinearProgressIndicator(),
      );
    }
    if (!available) {
      return Row(
        children: [
          const Expanded(child: Text(BookingStrings.originUnavailable, style: AppTextStyles.bodySm)),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 24),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            ),
            child: const Text(BookingStrings.retryOrigin),
          ),
        ],
      );
    }
    return Text(label, style: _EndpointRow.valueStyle);
  }
}

class _PlaceTile extends StatelessWidget {
  const _PlaceTile({required this.place, required this.onTap});

  final TripPlace place;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.base),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: AppColors.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.place_outlined, size: 20, color: AppColors.inverseSurface),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                place.name,
                style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600, color: AppColors.inverseSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Recommended routes for the picked destination: one selectable card per
/// plan, details on demand, and a single book button for the selected plan.
class _RouteOptions extends StatefulWidget {
  const _RouteOptions({
    required this.controller,
    required this.onReplan,
    required this.originLabel,
    required this.destinationLabel,
  });

  final BookingController controller;
  final String originLabel;
  final String destinationLabel;

  /// Plans again for the same endpoints; null while that isn't possible.
  final VoidCallback? onReplan;

  @override
  State<_RouteOptions> createState() => _RouteOptionsState();
}

class _RouteOptionsState extends State<_RouteOptions> {
  String? _selectedId;

  /// Plan whose step-by-step timeline is open; one at a time.
  String? _expandedId;
  String? _expiryPlanId;
  Timer? _expiryTimer;

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  /// Rebuild when the selected plan expires so the book button turns into "re-plan".
  void _watchExpiry(TripPlan plan) {
    if (plan.id == _expiryPlanId) return;
    _expiryPlanId = plan.id;
    _expiryTimer?.cancel();
    final remaining = plan.expiresAt.difference(DateTime.now());
    if (remaining.isNegative) return;
    _expiryTimer = Timer(remaining, () {
      if (mounted) setState(() {});
    });
  }

  /// Opening a plan's details also selects it, so "book" matches what is shown.
  void _toggleDetails(TripPlan plan) {
    setState(() {
      _selectedId = plan.id;
      _expandedId = _expandedId == plan.id ? null : plan.id;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final planError = controller.planError;

    if (controller.planning == PlanningStatus.loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: AppSpacing.sm),
            Text(BookingStrings.planningLoading, style: AppTextStyles.bodySm),
          ],
        ),
      );
    }
    if (controller.planning == PlanningStatus.failed && planError != null) {
      final retryable = planError.code.isTransient || planError.code == BookingFailureCode.planExpired;
      final hint = planError.nearestStop;
      return ListView(
        shrinkWrap: true,
        padding: EdgeInsets.fromLTRB(
          AppSpacing.containerMargin,
          AppSpacing.containerMargin,
          AppSpacing.containerMargin,
          AppSpacing.containerMargin + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          BookingErrorNotice(error: planError, onRetry: retryable ? widget.onReplan : null),
          if (hint != null) ...[
            const SizedBox(height: AppSpacing.md),
            _NearestStopCard(hint: hint),
          ],
        ],
      );
    }
    final plans = controller.plans;
    if (plans.isEmpty) return const SizedBox.shrink();

    final selected = plans.firstWhere((p) => p.id == _selectedId, orElse: () => plans.first);
    _watchExpiry(selected);
    final now = DateTime.now();
    final expired = selected.isExpired(now);
    final error = controller.actionError;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.containerMargin,
              AppSpacing.sm,
              AppSpacing.containerMargin,
              AppSpacing.md,
            ),
            children: [
              Text(BookingStrings.planTitle, style: _TripPlannerState._sheetTitleStyle),
              const SizedBox(height: AppSpacing.sm),
              for (final plan in plans)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: _RouteCard(
                    plan: plan,
                    now: now,
                    selected: plan.id == selected.id,
                    expanded: plan.id == _expandedId,
                    originLabel: widget.originLabel,
                    destinationLabel: widget.destinationLabel,
                    onTap: () => setState(() => _selectedId = plan.id),
                    onToggleDetails: () => _toggleDetails(plan),
                  ),
                ),
              Text(
                expired
                    ? BookingStrings.planExpiredHint
                    : BookingStrings.planValidUntil(BookingStrings.time(selected.expiresAt)),
                style: AppTextStyles.bodySm.copyWith(color: expired ? AppColors.error : null),
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.containerMargin,
            0,
            AppSpacing.containerMargin,
            AppSpacing.md + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (error != null) ...[
                BookingErrorNotice(error: error, onDismiss: controller.clearActionError),
                const SizedBox(height: AppSpacing.sm),
              ],
              if (expired)
                ElevatedButton(onPressed: widget.onReplan, child: const Text(BookingStrings.findRoute))
              else
                ElevatedButton(
                  // A second tap while confirming is ignored here and deduplicated
                  // by the controller (same Future, same Idempotency-Key).
                  onPressed: controller.isConfirming ? null : () => controller.confirm(selected),
                  child: controller.isConfirming
                      ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(BookingStrings.confirmBooking),
                            SizedBox(width: AppSpacing.xs),
                            Icon(Icons.chevron_right, size: 20),
                          ],
                        ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Map pin for a suggested stop.
class _StopMarker extends StatelessWidget {
  const _StopMarker();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: const Icon(Icons.directions_bus, size: 18, color: AppColors.onPrimary),
    );
  }
}

/// Where to board instead, shown when no route serves the trip.
class _NearestStopCard extends StatelessWidget {
  const _NearestStopCard({required this.hint});

  final NearestStopHint hint;

  @override
  Widget build(BuildContext context) {
    final duration = hint.walkDurationS == null ? null : BookingStrings.durationFromSeconds(hint.walkDurationS!);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox.square(dimension: 32, child: _StopMarker()),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(BookingStrings.nearestStopTitle, style: AppTextStyles.bodySm),
              Text(
                hint.stop.name,
                style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w700, color: AppColors.inverseSurface),
              ),
              const SizedBox(height: AppSpacing.base),
              StopTypeBadge(type: hint.stop.type),
              const SizedBox(height: AppSpacing.base),
              Text(
                BookingStrings.nearestStopWalk(duration, BookingStrings.distance(hint.walkDistanceM)),
                style: AppTextStyles.bodySm,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.plan,
    required this.now,
    required this.selected,
    required this.expanded,
    required this.originLabel,
    required this.destinationLabel,
    required this.onTap,
    required this.onToggleDetails,
  });

  final TripPlan plan;

  /// Departure time the arrival estimate is counted from.
  final DateTime now;
  final bool selected;
  final bool expanded;
  final String originLabel;
  final String destinationLabel;
  final VoidCallback onTap;
  final VoidCallback onToggleDetails;

  @override
  Widget build(BuildContext context) {
    final pickup = plan.pickupStop;
    final strongStyle = AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w700, color: AppColors.inverseSurface);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: AppColors.surfaceContainerLowest,
        elevation: selected ? 3 : 1,
        shadowColor: AppColors.inverseSurface.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        clipBehavior: Clip.antiAlias,
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(color: selected ? AppColors.primary : Colors.transparent, width: 4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: onTap,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.sm, AppSpacing.xs),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _LegSummary(plan: plan),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              BookingStrings.timeRange(now, now.add(Duration(minutes: plan.etaMinutes))),
                              style: strongStyle,
                            ),
                            if (pickup != null)
                              Text(
                                BookingStrings.pickupAt(pickup.name),
                                style: AppTextStyles.bodySm,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(BookingStrings.minutes(plan.etaMinutes), style: strongStyle),
                              const Icon(Icons.chevron_right, size: 18, color: AppColors.inverseSurface),
                            ],
                          ),
                          Text(BookingStrings.rupiah(plan.fareEstimateIdr), style: AppTextStyles.bodyMd),
                          TextButton(
                            onPressed: onToggleDetails,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                              minimumSize: const Size(0, 36),
                              foregroundColor: AppColors.primary,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(expanded ? BookingStrings.hideRouteDetails : BookingStrings.routeDetails),
                                Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: expanded
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Divider(height: 1, color: AppColors.surfaceContainerHighest),
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, AppSpacing.md, AppSpacing.md),
                            child: _RouteTimeline(
                              plan: plan,
                              departure: now,
                              originLabel: originLabel,
                              destinationLabel: destinationLabel,
                            ),
                          ),
                        ],
                      )
                    : const SizedBox(width: double.infinity),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `🚶 3 > [Feeder A] > 🚶 2`: walking minutes and feeder legs in order.
class _LegSummary extends StatelessWidget {
  const _LegSummary({required this.plan});

  final TripPlan plan;

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (final leg in plan.legs) {
      if (items.isNotEmpty) {
        items.add(const Icon(Icons.chevron_right, size: 16, color: AppColors.outline));
      }
      items.add(switch (leg.mode) {
        LegMode.walk => Semantics(
            label: '${BookingStrings.walk} ${BookingStrings.durationFromSeconds(leg.durationS)}',
            excludeSemantics: true,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.directions_walk, size: 16, color: AppColors.inverseSurface),
                Text(
                  '${(leg.durationS / 60).ceil()}',
                  style: AppTextStyles.labelMd.copyWith(color: AppColors.inverseSurface, letterSpacing: 0),
                ),
              ],
            ),
          ),
        LegMode.feeder || LegMode.motorcycle || LegMode.car => Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              switch (leg.mode) {
                LegMode.motorcycle => 'Motor',
                LegMode.car => 'Mobil',
                _ => BookingStrings.feederLine(plan.corridorId),
              },
              style: AppTextStyles.labelMd.copyWith(color: AppColors.onPrimary, letterSpacing: 0),
            ),
          ),
      });
    }
    return Wrap(
      spacing: AppSpacing.base,
      runSpacing: AppSpacing.base,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: items,
    );
  }
}

enum _Rail { none, walk, ride }

/// Step-by-step route, Google-Maps style: dotted walking segments, a solid
/// feeder line between pickup and drop-off, and the time at each point.
/// Intermediate times add up leg durations from [departure]; arrival uses the
/// plan's ETA so it matches the card header.
class _RouteTimeline extends StatelessWidget {
  const _RouteTimeline({
    required this.plan,
    required this.departure,
    required this.originLabel,
    required this.destinationLabel,
  });

  final TripPlan plan;
  final DateTime departure;
  final String originLabel;
  final String destinationLabel;

  @override
  Widget build(BuildContext context) {
    final steps = <_TimelineStep>[_TimelineStep.node(_NodeKind.origin, title: originLabel, time: departure)];
    var at = departure;
    for (final leg in plan.legs) {
      final duration = BookingStrings.durationFromSeconds(leg.durationS);
      final distance = BookingStrings.distance(leg.distanceM);
      switch (leg.mode) {
        case LegMode.walk:
          steps.add(_TimelineStep.segment(_Rail.walk, BookingStrings.walkLeg(duration, distance)));
        case LegMode.feeder:
        case LegMode.motorcycle:
        case LegMode.car:
          final pickup = plan.pickupStop;
          final dropoff = plan.dropoffStop;
          steps
            ..add(_TimelineStep.node(
              _NodeKind.pickup,
              title: pickup?.name ?? BookingStrings.pickupStop,
              time: at,
              stop: pickup,
            ))
            ..add(_TimelineStep.segment(_Rail.ride, switch (leg.mode) {
              LegMode.motorcycle => 'Naik motor $duration ($distance)',
              LegMode.car => 'Naik mobil $duration ($distance)',
              _ => BookingStrings.rideLeg(duration, distance),
            }));
          at = at.add(Duration(seconds: leg.durationS.round()));
          steps.add(_TimelineStep.node(
            _NodeKind.dropoff,
            title: dropoff?.name ?? BookingStrings.dropoffStop,
            time: at,
            stop: dropoff,
          ));
          continue;
      }
      at = at.add(Duration(seconds: leg.durationS.round()));
    }
    steps.add(_TimelineStep.node(
      _NodeKind.destination,
      title: destinationLabel,
      time: departure.add(Duration(minutes: plan.etaMinutes)),
    ));

    _Rail railAt(int index) => index < 0 || index >= steps.length ? _Rail.none : steps[index].rail;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < steps.length; i++)
          steps[i].kind == null
              ? _TimelineSegment(rail: steps[i].rail, text: steps[i].title)
              : _TimelineNode(
                  step: steps[i],
                  above: railAt(i - 1),
                  below: railAt(i + 1),
                  corridorId: plan.corridorId,
                  nearestFeederEtaS: plan.nearestFeederEtaS,
                ),
      ],
    );
  }
}

enum _NodeKind { origin, pickup, dropoff, destination }

class _TimelineStep {
  const _TimelineStep.node(_NodeKind this.kind, {required this.title, required DateTime this.time, this.stop})
      : rail = _Rail.none;

  const _TimelineStep.segment(this.rail, this.title)
      : kind = null,
        time = null,
        stop = null;

  /// Null for a segment (walk or ride) between two points.
  final _NodeKind? kind;
  final _Rail rail;
  final String title;
  final DateTime? time;
  final Stop? stop;
}

const _railWidth = 32.0;

/// Vertical center of a node's marker, aligned with its title's first line.
const _markerCenterY = 12.0;

class _TimelineNode extends StatelessWidget {
  const _TimelineNode({
    required this.step,
    required this.above,
    required this.below,
    required this.corridorId,
    required this.nearestFeederEtaS,
  });

  final _TimelineStep step;
  final _Rail above;
  final _Rail below;
  final String? corridorId;
  final int? nearestFeederEtaS;

  Widget _marker() => switch (step.kind!) {
        _NodeKind.origin => Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: AppColors.secondary,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.secondaryContainer, width: 3),
            ),
          ),
        _NodeKind.pickup => Container(
            width: 24,
            height: 24,
            decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle),
            child: const Icon(Icons.directions_bus, size: 14, color: AppColors.onPrimary),
          ),
        _NodeKind.dropoff => Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.surfaceContainerLowest,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 3),
            ),
          ),
        _NodeKind.destination => const DecoratedBox(
            decoration: BoxDecoration(color: AppColors.surfaceContainerLowest, shape: BoxShape.circle),
            child: Icon(Icons.location_on, size: 22, color: AppColors.error),
          ),
      };

  @override
  Widget build(BuildContext context) {
    final stop = step.stop;
    final validUntil = stop?.validUntil;
    final isPickup = step.kind == _NodeKind.pickup;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _railWidth,
            child: CustomPaint(
              painter: _RailPainter(above: above, below: below, split: _markerCenterY),
              child: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(height: _markerCenterY * 2, child: Center(child: _marker())),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          step.title,
                          style: AppTextStyles.bodyMd.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.inverseSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        BookingStrings.time(step.time!),
                        style: AppTextStyles.bodyMd.copyWith(color: AppColors.inverseSurface),
                      ),
                    ],
                  ),
                  if (stop != null) ...[
                    const SizedBox(height: AppSpacing.base),
                    StopTypeBadge(type: stop.type),
                  ],
                  if (isPickup && stop?.type == StopType.virtualStop && validUntil != null) ...[
                    const SizedBox(height: AppSpacing.base),
                    Text(
                      BookingStrings.stopValidUntil(BookingStrings.time(validUntil)),
                      style: AppTextStyles.bodySm,
                    ),
                  ],
                  if (isPickup) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Wrap(
                      spacing: AppSpacing.xs,
                      runSpacing: AppSpacing.base,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primaryContainer,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Text(
                            BookingStrings.feederLine(corridorId),
                            style: AppTextStyles.labelMd.copyWith(color: AppColors.onPrimary, letterSpacing: 0),
                          ),
                        ),
                        if (nearestFeederEtaS != null)
                          Text(
                            BookingStrings.feederArrivesIn(BookingStrings.durationFromSeconds(nearestFeederEtaS!)),
                            style: AppTextStyles.bodySm,
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineSegment extends StatelessWidget {
  const _TimelineSegment({required this.rail, required this.text});

  final _Rail rail;
  final String text;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: _railWidth,
            child: CustomPaint(
              painter: _RailPainter(above: rail, below: rail),
              child: rail == _Rail.walk
                  ? const Center(
                      child: ColoredBox(
                        color: AppColors.surfaceContainerLowest,
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 2),
                          child: Icon(Icons.directions_walk, size: 18, color: AppColors.inverseSurface),
                        ),
                      ),
                    )
                  : null,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Text(
                text,
                style: AppTextStyles.bodyMd.copyWith(color: AppColors.inverseSurface),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Rail through a timeline row: [above] the split point, [below] after it.
class _RailPainter extends CustomPainter {
  const _RailPainter({required this.above, required this.below, this.split});

  final _Rail above;
  final _Rail below;

  /// Defaults to the middle of the row.
  final double? split;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    final y = split ?? size.height / 2;
    _draw(canvas, x, 0, y, above);
    _draw(canvas, x, y, size.height, below);
  }

  void _draw(Canvas canvas, double x, double from, double to, _Rail rail) {
    switch (rail) {
      case _Rail.none:
        return;
      case _Rail.ride:
        canvas.drawLine(
          Offset(x, from),
          Offset(x, to),
          Paint()
            ..color = AppColors.primary
            ..strokeWidth = 6,
        );
      case _Rail.walk:
        final dot = Paint()..color = AppColors.outline;
        for (var y = from + 5; y < to - 2; y += 9) {
          canvas.drawCircle(Offset(x, y), 2.5, dot);
        }
    }
  }

  @override
  bool shouldRepaint(_RailPainter oldDelegate) =>
      oldDelegate.above != above || oldDelegate.below != below || oldDelegate.split != split;
}
