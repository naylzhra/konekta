import 'package:flutter/material.dart';

import '../../../core/theme/konekta_theme.dart';

class FeederMarker extends StatelessWidget {
  const FeederMarker({super.key, this.stale = false});

  /// Greyed out when the position is no longer being updated.
  final bool stale;

  static const size = 44.0;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: stale ? AppColors.outline : AppColors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.onPrimary, width: 3),
      ),
      child: const Icon(Icons.directions_bus, color: AppColors.onPrimary, size: 22),
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
