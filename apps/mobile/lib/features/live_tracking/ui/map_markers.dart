import 'package:flutter/material.dart';

import '../../../core/theme/konekta_theme.dart';

/// The passenger's booked feeder: larger and in the secondary (teal) colour so
/// it stands out from the rest of the fleet ([FleetFeederMarker]).
class FeederMarker extends StatelessWidget {
  const FeederMarker({super.key, this.stale = false});

  /// Greyed out when the position is no longer being updated.
  final bool stale;

  static const size = 48.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: stale ? AppColors.outline : AppColors.secondary,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.onSecondary, width: 3),
        boxShadow: [
          if (!stale) BoxShadow(color: AppColors.secondary.withValues(alpha: 0.45), blurRadius: 12, spreadRadius: 2),
        ],
      ),
      child: const Icon(Icons.directions_bus, color: AppColors.onSecondary, size: 24),
    );
  }
}

/// Any other on-duty feeder.
class FleetFeederMarker extends StatelessWidget {
  const FleetFeederMarker({super.key, this.full = false, this.selected = false});

  /// Faded when no seats are left.
  final bool full;

  /// Ringed while its info card is open.
  final bool selected;

  static const size = 36.0;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: full ? 0.5 : 1,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? AppColors.secondaryContainer : AppColors.onPrimary, width: 3),
        ),
        child: const Icon(Icons.directions_bus, color: AppColors.onPrimary, size: 18),
      ),
    );
  }
}

class UserLocationMarker extends StatelessWidget {
  const UserLocationMarker({super.key});

  static const size = 22.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.secondary,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.onSecondary, width: 3),
      ),
    );
  }
}

class PickupStopMarker extends StatelessWidget {
  const PickupStopMarker({super.key});

  static const size = 40.0;

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.location_on, color: AppColors.tertiary, size: size);
  }
}
