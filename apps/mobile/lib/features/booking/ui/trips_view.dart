import 'package:flutter/material.dart';

import '../../../core/strings/booking_strings.dart';
import '../../../core/theme/konekta_theme.dart';
import '../data/trip_locations.dart';
import '../state/booking_controller.dart';
import 'active_booking_card.dart';
import 'booking_home_section.dart';

/// Trips tab content: the entry point for planning a trip. While a booking is
/// active it shows that booking instead; no history or past trips.
class TripsView extends StatelessWidget {
  const TripsView({super.key, required this.booking, required this.locations, this.active = true});

  final BookingController booking;
  final TripLocations locations;

  /// False while another tab is showing.
  final bool active;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: booking,
      builder: (context, _) {
        final current = booking.current;
        final hasActive = current != null && current.isActive;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: kToolbarHeight,
              child: Center(
                child: Text(
                  hasActive ? BookingStrings.activeTripTitle : BookingStrings.plannerTitle,
                  style: AppTextStyles.headlineMd.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.inverseSurface,
                  ),
                ),
              ),
            ),
            Expanded(
              child: hasActive
                  ? RefreshIndicator(
                      onRefresh: booking.resync,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.all(AppSpacing.containerMargin),
                        children: [ActiveBookingCard(controller: booking)],
                      ),
                    )
                  : TripPlannerView(controller: booking, locations: locations, active: active),
            ),
          ],
        );
      },
    );
  }
}
