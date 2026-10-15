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

/// Home tab content (DESIGN.md §1): consent → destination → plan → confirm,
/// then the active booking's live status.
class BookingHomeSection extends StatelessWidget {
  const BookingHomeSection({super.key, required this.controller, required this.locations});

  final BookingController controller;
  final TripLocations locations;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final current = controller.current;
        return ListView(
          padding: const EdgeInsets.all(AppSpacing.containerMargin),
          children: [
            const Text(BookingStrings.homeTitle, style: AppTextStyles.headlineLg),
            const SizedBox(height: AppSpacing.base),
            const Text(BookingStrings.homeSubtitle, style: AppTextStyles.bodySm),
            const SizedBox(height: AppSpacing.lg),
            // Always one child, so toggling connectivity doesn't shift the
            // planner's position and reset its state (query, destination).
            controller.isOnline
                ? const SizedBox.shrink()
                : const Padding(
                    padding: EdgeInsets.only(bottom: AppSpacing.sm),
                    child: BookingNotice(icon: Icons.cloud_off, message: BookingStrings.offline),
                  ),
            if (current != null)
              ActiveBookingCard(controller: controller)
            else if (controller.consent == ConsentState.required)
              _ConsentCard(controller: controller)
            else
              _TripPlanner(controller: controller, locations: locations),
          ],
        );
      },
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
  TripPlace? _destination;
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

  void _select(TripPlace place) {
    setState(() => _destination = place);
    _plan();
  }

  void _changeDestination() {
    widget.controller.clearPlans();
    setState(() => _destination = null);
  }

  void _plan() {
    final origin = _origin;
    final destination = _destination;
    if (origin == null || destination == null) return;
    widget.controller.clearActionError();
    unawaited(widget.controller.planTrip(origin: origin, destination: destination.location));
  }

  Widget _planSection(BookingController controller, bool canPlan) {
    final planError = controller.planError;
    if (controller.planning == PlanningStatus.loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Column(
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
      return BookingErrorNotice(error: planError, onRetry: canPlan && retryable ? _plan : null);
    }
    if (controller.planning == PlanningStatus.ready) {
      return Column(
        children: [
          for (final plan in controller.plans) _PlanCard(controller: controller, plan: plan, onReplan: _plan),
        ],
      );
    }
    return ElevatedButton(onPressed: canPlan ? _plan : null, child: const Text(BookingStrings.findRoute));
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final destination = _destination;
    final canPlan = _origin != null && destination != null && controller.planning != PlanningStatus.loading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BookingCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(BookingStrings.origin, style: AppTextStyles.labelMd),
              const SizedBox(height: AppSpacing.base),
              _OriginRow(loading: _loadingOrigin, available: _origin != null, onRetry: _loadOrigin),
              const Divider(height: AppSpacing.lg),
              const Text(BookingStrings.destination, style: AppTextStyles.labelMd),
              const SizedBox(height: AppSpacing.base),
              if (destination != null)
                Row(
                  children: [
                    const Icon(Icons.flag_outlined, size: 20, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(destination.name, style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    TextButton(onPressed: _changeDestination, child: const Text(BookingStrings.changeDestination)),
                  ],
                )
              else ...[
                TextField(
                  controller: _query,
                  onChanged: _search,
                  textInputAction: TextInputAction.search,
                  decoration: const InputDecoration(
                    hintText: BookingStrings.destinationHint,
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                if (_suggestions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Text(BookingStrings.noDestinationMatch, style: AppTextStyles.bodySm),
                  )
                else
                  for (final place in _suggestions)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      leading: const Icon(Icons.place_outlined),
                      title: Text(place.name, style: AppTextStyles.bodyMd),
                      onTap: () => _select(place),
                    ),
              ],
              if (widget.locations.isPlaceholder) ...[
                const SizedBox(height: AppSpacing.xs),
                const Text(BookingStrings.placeholderLocations, style: AppTextStyles.labelMd),
              ],
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _planSection(controller, canPlan),
      ],
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
    if (loading) return const LinearProgressIndicator();
    if (!available) {
      return BookingNotice(
        icon: Icons.location_disabled,
        message: BookingStrings.originUnavailable,
        action: TextButton(onPressed: onRetry, child: const Text(BookingStrings.retryOrigin)),
      );
    }
    return Row(
      children: [
        const Icon(Icons.my_location, size: 20, color: AppColors.primary),
        const SizedBox(width: AppSpacing.xs),
        Text(BookingStrings.currentLocation, style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _PlanCard extends StatefulWidget {
  const _PlanCard({required this.controller, required this.plan, required this.onReplan});

  final BookingController controller;
  final TripPlan plan;
  final VoidCallback onReplan;

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  Timer? _expiryTimer;

  @override
  void initState() {
    super.initState();
    _scheduleExpiry();
  }

  @override
  void didUpdateWidget(_PlanCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plan.id != widget.plan.id) _scheduleExpiry();
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  /// Rebuild when the plan expires so the confirm button turns into "re-plan".
  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final remaining = widget.plan.expiresAt.difference(DateTime.now());
    if (remaining.isNegative) return;
    _expiryTimer = Timer(remaining, () {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final plan = widget.plan;
    final expired = plan.isExpired(DateTime.now());
    final pickup = plan.pickupStop;
    final dropoff = plan.dropoffStop;
    final walkM = plan.legs.where((l) => l.mode == LegMode.walk).fold<double>(0, (sum, l) => sum + l.distanceM);
    final pickupValidUntil = pickup?.validUntil;
    final error = controller.actionError;

    return BookingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(BookingStrings.planTitle, style: AppTextStyles.headlineMd),
          const SizedBox(height: AppSpacing.sm),
          if (pickup != null)
            StopRow(
              label: BookingStrings.pickupStop,
              name: pickup.name,
              type: pickup.type,
              icon: Icons.trip_origin,
              footnote: pickup.type == StopType.virtualStop && pickupValidUntil != null
                  ? BookingStrings.stopValidUntil(BookingStrings.time(pickupValidUntil))
                  : null,
            ),
          if (pickup != null && dropoff != null) const SizedBox(height: AppSpacing.sm),
          if (dropoff != null)
            StopRow(label: BookingStrings.dropoffStop, name: dropoff.name, type: dropoff.type, icon: Icons.flag_outlined),
          const SizedBox(height: AppSpacing.sm),
          InfoRow(label: BookingStrings.fare, value: BookingStrings.rupiah(plan.fareEstimateIdr)),
          InfoRow(label: BookingStrings.travelTime, value: BookingStrings.minutes(plan.etaMinutes)),
          if (walkM > 0) InfoRow(label: BookingStrings.walkToStop, value: BookingStrings.distance(walkM)),
          if (plan.nearestFeederEtaS != null)
            InfoRow(
              label: BookingStrings.nearestFeeder,
              value: BookingStrings.durationFromSeconds(plan.nearestFeederEtaS!),
            ),
          const SizedBox(height: AppSpacing.base),
          Text(
            expired ? BookingStrings.planExpiredHint : BookingStrings.planValidUntil(BookingStrings.time(plan.expiresAt)),
            style: AppTextStyles.bodySm.copyWith(color: expired ? AppColors.error : null),
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            BookingErrorNotice(error: error, onDismiss: controller.clearActionError),
          ],
          const SizedBox(height: AppSpacing.md),
          if (expired)
            ElevatedButton(onPressed: widget.onReplan, child: const Text(BookingStrings.findRoute))
          else
            ElevatedButton(
              // A second tap while confirming is ignored here and deduplicated
              // by the controller (same Future, same Idempotency-Key).
              onPressed: controller.isConfirming ? null : () => controller.confirm(plan),
              child: controller.isConfirming
                  ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text(BookingStrings.confirmBooking),
            ),
        ],
      ),
    );
  }
}
