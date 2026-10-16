import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/strings/booking_strings.dart';
import '../../../core/theme/konekta_theme.dart';
import '../data/trip_locations.dart';
import '../domain/booking_failure.dart';
import '../domain/booking_models.dart';
import '../state/booking_controller.dart';
import 'active_booking_card.dart';
import 'booking_widgets.dart';
import 'home_widgets.dart';

/// Home tab content: greeting, search, map preview, quick actions and pooling
/// summary. Booking itself (consent -> destination -> plan -> confirm) lives in
/// [_TripPlannerPage]; once a booking exists, its live status replaces the
/// search and quick actions here (DESIGN.md §1).
class BookingHomeSection extends StatelessWidget {
  const BookingHomeSection({
    super.key,
    required this.controller,
    required this.locations,
    this.onOpenMap,
  });

  final BookingController controller;
  final TripLocations locations;

  /// Switches to the Map tab (Route Info, locate button).
  final VoidCallback? onOpenMap;

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
            if (!controller.isOnline) ...[
              const BookingNotice(icon: Icons.cloud_off, message: BookingStrings.offline),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (!hasBooking) ...[
              HomeSearchBar(onTap: () => _openPlanner(context)),
              const SizedBox(height: AppSpacing.md),
            ],
            HomeMapHero(nearbyFeeders: HomeStats.nearbyFeeders, onLocate: onOpenMap),
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
            const SizedBox(height: AppSpacing.md),
            HomePoolingCard(activeVirtualStops: HomeStats.activeVirtualStops),
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
                    if (!controller.isOnline) ...[
                      const BookingNotice(icon: Icons.cloud_off, message: BookingStrings.offline),
                      const SizedBox(height: AppSpacing.sm),
                    ],
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
  final _query = TextEditingController();
  GeoPoint? _origin;
  bool _loadingOrigin = true;

  /// The searched place. It is the destination, or the origin when [_swapped]
  /// (then the trip ends at the current location).
  TripPlace? _place;
  bool _swapped = false;
  List<TripPlace> _suggestions = const [];
  int _searchRequest = 0;

  @override
  void initState() {
    super.initState();
    _loadOrigin();
    _search('');
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _loadOrigin() async {
    setState(() => _loadingOrigin = true);
    final origin = await widget.locations.currentOrigin();
    if (!mounted) return;
    setState(() {
      _origin = origin;
      _loadingOrigin = false;
    });
  }

  Future<void> _search(String query) async {
    final request = ++_searchRequest;
    final results = await widget.locations.searchDestinations(query);
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

  void _select(TripPlace place) {
    FocusScope.of(context).unfocus();
    widget.controller.clearPlans();
    _query.text = place.name;
    setState(() => _place = place);
  }

  void _swap() {
    widget.controller.clearPlans();
    setState(() => _swapped = !_swapped);
  }

  void _plan() {
    final here = _origin;
    final place = _place;
    if (here == null || place == null) return;
    widget.controller.clearActionError();
    unawaited(
      widget.controller.planTrip(
        origin: _swapped ? place.location : here,
        destination: _swapped ? here : place.location,
      ),
    );
  }

  static final _sheetTitleStyle = AppTextStyles.headlineMd.copyWith(
    fontWeight: FontWeight.w700,
    color: AppColors.inverseSurface,
  );

  Widget _selectionSheet(bool canPlan) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(BookingStrings.suggestedPlaces, style: _sheetTitleStyle),
        const SizedBox(height: AppSpacing.xs),
        Flexible(
          child: _suggestions.isEmpty
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Text(BookingStrings.noDestinationMatch, style: AppTextStyles.bodySm),
                )
              : ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: [
                    for (final place in _suggestions)
                      _PlaceTile(place: place, selected: place.id == _place?.id, onTap: () => _select(place)),
                  ],
                ),
        ),
        if (widget.locations.isPlaceholder) ...[
          const SizedBox(height: AppSpacing.xs),
          const Text(BookingStrings.placeholderLocations, style: AppTextStyles.labelMd),
        ],
        const SizedBox(height: AppSpacing.md),
        ElevatedButton(
          onPressed: canPlan ? _plan : null,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(BookingStrings.confirmDestination),
              SizedBox(width: AppSpacing.xs),
              Icon(Icons.arrow_forward, size: 20),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final canPlan = _origin != null && _place != null && controller.planning != PlanningStatus.loading;

    final currentLocation = _OriginRow(loading: _loadingOrigin, available: _origin != null, onRetry: _loadOrigin);
    final placeField = TextField(
      controller: _query,
      onChanged: _onQueryChanged,
      textInputAction: TextInputAction.search,
      style: _EndpointRow.valueStyle,
      decoration: InputDecoration(
        isCollapsed: true,
        filled: false,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        hintText: _swapped ? BookingStrings.originHint : BookingStrings.destinationHint,
        hintStyle: _EndpointRow.valueStyle.copyWith(color: AppColors.outline, fontWeight: FontWeight.w500),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.containerMargin,
            AppSpacing.xs,
            AppSpacing.containerMargin,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Always one child, so toggling connectivity doesn't shift the
              // endpoints card and reset the text field.
              controller.isOnline
                  ? const SizedBox.shrink()
                  : const Padding(
                      padding: EdgeInsets.only(bottom: AppSpacing.sm),
                      child: BookingNotice(icon: Icons.cloud_off, message: BookingStrings.offline),
                    ),
              _EndpointsCard(
                origin: _swapped ? placeField : currentLocation,
                destination: _swapped ? currentLocation : placeField,
                onSwap: _swap,
              ),
            ],
          ),
        ),
        Expanded(
          child: controller.planning == PlanningStatus.idle
              ? _selectionMap(canPlan)
              : _RouteOptions(
                  controller: controller,
                  onReplan: canPlan ? _plan : null,
                  originLabel: _swapped ? _place?.name ?? BookingStrings.origin : BookingStrings.currentLocation,
                  destinationLabel:
                      _swapped ? BookingStrings.currentLocation : _place?.name ?? BookingStrings.destination,
                ),
        ),
      ],
    );
  }

  Widget _selectionMap(bool canPlan) {
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          const Positioned.fill(child: StylizedMap()),
          if (_place != null) const Align(alignment: Alignment(0, -0.6), child: _PlaceMarker()),
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.md, bottom: AppSpacing.md),
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
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: constraints.maxHeight * 0.75),
                  child: _PlannerSheet(child: _selectionSheet(canPlan)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Origin/destination card with the swap button.
class _EndpointsCard extends StatelessWidget {
  const _EndpointsCard({required this.origin, required this.destination, required this.onSwap});

  final Widget origin;
  final Widget destination;
  final VoidCallback onSwap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.base, AppSpacing.base, AppSpacing.base),
      decoration: BoxDecoration(
        color: AppColors.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.surfaceContainerHighest),
        boxShadow: [
          BoxShadow(
              color: AppColors.inverseSurface.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Stack(
              children: [
                // Connector between the two endpoint icons.
                const Positioned(
                  left: 9,
                  top: 40,
                  bottom: 40,
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
          ),
          IconButton(
            tooltip: BookingStrings.swapEndpoints,
            onPressed: onSwap,
            icon: const Icon(Icons.swap_vert, color: AppColors.onSurfaceVariant),
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.bodySm),
                const SizedBox(height: 2),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OriginRow extends StatelessWidget {
  const _OriginRow({required this.loading, required this.available, required this.onRetry});

  final bool loading;
  final bool available;
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
          TextButton(onPressed: onRetry, child: const Text(BookingStrings.retryOrigin)),
        ],
      );
    }
    return Text(BookingStrings.currentLocation, style: _EndpointRow.valueStyle);
  }
}

/// Pin for the picked place.
class _PlaceMarker extends StatelessWidget {
  const _PlaceMarker();

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.location_on_outlined, size: 44, color: AppColors.secondary);
  }
}

/// Rounded bottom sheet over the map.
class _PlannerSheet extends StatelessWidget {
  const _PlannerSheet({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surfaceContainerLowest,
      elevation: 8,
      shadowColor: const Color(0x33000000),
      borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.containerMargin,
          AppSpacing.sm,
          AppSpacing.containerMargin,
          AppSpacing.md + MediaQuery.paddingOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
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
            const SizedBox(height: AppSpacing.md),
            Flexible(child: child),
          ],
        ),
      ),
    );
  }
}

class _PlaceTile extends StatelessWidget {
  const _PlaceTile({required this.place, required this.selected, required this.onTap});

  final TripPlace place;
  final bool selected;
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
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.surfaceContainerHigh,
                shape: BoxShape.circle,
              ),
              child: Icon(
                selected ? Icons.check : Icons.place_outlined,
                size: 20,
                color: selected ? Colors.white : AppColors.inverseSurface,
              ),
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
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.containerMargin),
        children: [BookingErrorNotice(error: planError, onRetry: retryable ? widget.onReplan : null)],
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
        LegMode.feeder => Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              BookingStrings.feederLine(plan.corridorId),
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
          final pickup = plan.pickupStop;
          final dropoff = plan.dropoffStop;
          steps
            ..add(_TimelineStep.node(
              _NodeKind.pickup,
              title: pickup?.name ?? BookingStrings.pickupStop,
              time: at,
              stop: pickup,
            ))
            ..add(_TimelineStep.segment(_Rail.ride, BookingStrings.rideLeg(duration, distance)));
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
