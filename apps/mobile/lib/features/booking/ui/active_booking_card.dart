import 'package:flutter/material.dart';

import '../../../core/strings/booking_strings.dart';
import '../../../core/theme/konekta_theme.dart';
import '../domain/booking_state_machine.dart';
import '../state/booking_controller.dart';
import 'booking_widgets.dart';

/// The booking [BookingController.current] is tracking: live status plus
/// the passenger's actions. Buttons are offered only when the mirrored
/// state machine allows them; the status itself changes only via server
/// snapshots.
class ActiveBookingCard extends StatelessWidget {
  const ActiveBookingCard({super.key, required this.controller});

  final BookingController controller;

  Future<void> _cancel(BuildContext context) async {
    if (!await confirmCancel(context)) return;
    await controller.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final booking = controller.current;
    if (booking == null) return const SizedBox.shrink();
    final status = booking.status;
    final pickup = booking.pickupStop;
    final dropoff = booking.dropoffStop;
    final stopUpdate = controller.pickupStopUpdate;
    final validUntil = stopUpdate?.validUntil;

    return BookingCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(BookingStrings.statusLabel(status), style: AppTextStyles.headlineMd)),
              if (status == BookingStatus.requested || status == BookingStatus.matching)
                const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: AppSpacing.base),
          Text(BookingStrings.statusDescription(status), style: AppTextStyles.bodySm),
          if (stopUpdate != null && booking.isActive) ...[
            const SizedBox(height: AppSpacing.sm),
            BookingNotice(
              icon: Icons.wrong_location_outlined,
              message: validUntil == null
                  ? BookingStrings.stopMoved
                  : '${BookingStrings.stopMoved} ${BookingStrings.stopValidUntil(BookingStrings.time(validUntil))}',
            ),
          ],
          if (pickup != null || dropoff != null) const SizedBox(height: AppSpacing.md),
          if (pickup != null)
            StopRow(
              label: BookingStrings.pickupStop,
              name: pickup.name,
              type: pickup.type,
              icon: Icons.trip_origin,
            ),
          if (pickup != null && dropoff != null) const SizedBox(height: AppSpacing.sm),
          if (dropoff != null)
            StopRow(
              label: BookingStrings.dropoffStop,
              name: dropoff.name,
              type: dropoff.type,
              icon: Icons.flag_outlined,
            ),
          const SizedBox(height: AppSpacing.sm),
          if (booking.feederId != null && booking.isActive)
            InfoRow(label: BookingStrings.feeder, value: booking.feederId!),
          if (booking.etaToPickupS != null &&
              (status == BookingStatus.confirmed || status == BookingStatus.feederArriving))
            InfoRow(
              label: BookingStrings.etaToPickup,
              value: BookingStrings.durationFromSeconds(booking.etaToPickupS!),
            ),
          InfoRow(label: BookingStrings.fare, value: BookingStrings.rupiah(booking.fareEstimateIdr)),
          if (status == BookingStatus.confirmed || status == BookingStatus.feederArriving) ...[
            const SizedBox(height: AppSpacing.base),
            const Text(BookingStrings.seeMap, style: AppTextStyles.bodySm),
          ],
          if (controller.actionError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            BookingErrorNotice(error: controller.actionError!, onDismiss: controller.clearActionError),
          ],
          if (booking.isActive && (booking.canBoard || booking.canCancel)) const SizedBox(height: AppSpacing.md),
          if (booking.canBoard)
            ElevatedButton(
              onPressed: controller.canBoard ? controller.markBoarded : null,
              child: controller.isBoarding ? const _ButtonSpinner() : const Text(BookingStrings.boarded),
            ),
          if (booking.canBoard && booking.canCancel) const SizedBox(height: AppSpacing.xs),
          if (booking.canCancel)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: controller.canCancel ? () => _cancel(context) : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.standard)),
                ),
                child: controller.isCancelling ? const _ButtonSpinner() : const Text(BookingStrings.cancel),
              ),
            ),
          if (!booking.isActive) ...[
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: controller.dismissFinished,
              child: Text(status == BookingStatus.completed ? BookingStrings.dismiss : BookingStrings.bookAgain),
            ),
          ],
        ],
      ),
    );
  }
}

class _ButtonSpinner extends StatelessWidget {
  const _ButtonSpinner();

  @override
  Widget build(BuildContext context) =>
      const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2));
}
