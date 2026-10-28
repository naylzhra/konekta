import 'package:flutter/material.dart';

import '../../../core/strings/booking_strings.dart';
import '../../../core/theme/konekta_theme.dart';
import '../domain/booking_models.dart';
import '../state/booking_controller.dart';
import '../state/trip_history_controller.dart';
import 'active_booking_card.dart';
import 'booking_widgets.dart';

/// Trips tab content (DESIGN.md §1.7): the active trip, then history.
class TripsView extends StatefulWidget {
  const TripsView({super.key, required this.booking, required this.history});

  final BookingController booking;
  final TripHistoryController history;

  @override
  State<TripsView> createState() => _TripsViewState();
}

class _TripsViewState extends State<TripsView> {
  @override
  void initState() {
    super.initState();
    if (!widget.history.isLoaded && !widget.history.isLoading) widget.history.refresh();
  }

  Future<void> _refresh() => Future.wait([widget.booking.resync(), widget.history.refresh()]);

  @override
  Widget build(BuildContext context) {
    final booking = widget.booking;
    final history = widget.history;
    return ListenableBuilder(
      listenable: Listenable.merge([booking, history]),
      builder: (context, _) {
        final current = booking.current;
        final active = current != null && current.isActive ? current : null;
        // The active booking is shown above; history lists the rest.
        final past = [for (final b in history.items) if (b.id != active?.id) b];
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.containerMargin),
            children: [
              const Text(BookingStrings.tripsTitle, style: AppTextStyles.headlineLg),
              const SizedBox(height: AppSpacing.md),
              const Text(BookingStrings.activeTripTitle, style: AppTextStyles.headlineMd),
              const SizedBox(height: AppSpacing.xs),
              if (active != null)
                ActiveBookingCard(controller: booking)
              else
                const Text(BookingStrings.noActiveTrip, style: AppTextStyles.bodySm),
              const SizedBox(height: AppSpacing.lg),
              const Text(BookingStrings.historyTitle, style: AppTextStyles.headlineMd),
              const SizedBox(height: AppSpacing.xs),
              if (history.error != null && !history.error!.code.isTransient) ...[
                BookingErrorNotice(
                  error: history.error!,
                  onRetry: history.isLoaded && history.hasMore ? history.loadMore : history.refresh,
                ),
                const SizedBox(height: AppSpacing.xs),
              ],
              if (history.isLoading && !history.isLoaded)
                const Padding(
                  padding: EdgeInsets.all(AppSpacing.lg),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (history.isLoaded && past.isEmpty)
                const Text(BookingStrings.historyEmpty, style: AppTextStyles.bodySm)
              else
                for (final item in past) ...[
                  _HistoryTile(booking: item),
                  const SizedBox(height: AppSpacing.xs),
                ],
              if (history.hasMore)
                Center(
                  child: history.isLoadingMore
                      ? const Padding(
                          padding: EdgeInsets.all(AppSpacing.sm),
                          child: CircularProgressIndicator(),
                        )
                      : TextButton(onPressed: history.loadMore, child: const Text(BookingStrings.loadMore)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({required this.booking});

  final Booking booking;

  @override
  Widget build(BuildContext context) {
    final pickup = booking.pickupStop?.name;
    final dropoff = booking.dropoffStop?.name;
    return BookingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(BookingStrings.dateTime(booking.createdAt), style: AppTextStyles.bodySm)),
              BookingStatusChip(status: booking.status),
            ],
          ),
          if (pickup != null || dropoff != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              [pickup, dropoff].whereType<String>().join(' → '),
              style: AppTextStyles.bodyMd.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
          const SizedBox(height: AppSpacing.base),
          Text(BookingStrings.rupiah(booking.fareEstimateIdr), style: AppTextStyles.bodySm),
        ],
      ),
    );
  }
}
