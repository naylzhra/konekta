import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../core/navigation/nav_instructions.dart';
import '../core/theme/konekta_theme.dart';

/// Turn-by-turn green, shared by the driver and passenger navigation views.
const navGreen = Color(0xFF0F7B4A);

/// Blue of the line being navigated on the map.
const navRouteBlue = Color(0xFF1A73E8);
const navRouteBorder = Color(0xFF0B4FB3);

/// Google-Maps-style instruction bar: maneuver arrow, distance to it, and
/// the instruction. Without a [step] it shows [fallback] with [fallbackIcon].
class NavBanner extends StatelessWidget {
  const NavBanner({
    super.key,
    this.step,
    this.here,
    this.arrivalName,
    required this.fallback,
    this.fallbackIcon = Icons.route,
  });

  final NavStep? step;
  final LatLng? here;
  final String? arrivalName;
  final String fallback;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final step = this.step;
    final here = this.here;
    return Container(
      margin: const EdgeInsets.all(AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: navGreen,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
      ),
      child: step == null || here == null
          ? Row(children: [
              Icon(fallbackIcon, color: Colors.white, size: 32),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(fallback,
                    style: AppTextStyles.bodyLg.copyWith(color: Colors.white)),
              ),
            ])
          : Row(children: [
              Icon(iconFor(step), color: Colors.white, size: 44),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(formatDistance(metresTo(here, step.location)),
                        style: AppTextStyles.headlineLgMobile
                            .copyWith(color: Colors.white)),
                    Text(instructionFor(step, arrivalName: arrivalName),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style:
                            AppTextStyles.bodyLg.copyWith(color: Colors.white)),
                  ],
                ),
              ),
            ]),
    );
  }
}

/// ETA in green with the remaining distance, as in the sheet under a
/// navigation banner.
class NavEtaRow extends StatelessWidget {
  const NavEtaRow({super.key, required this.durationS, required this.distanceM});

  final double durationS;
  final double distanceM;

  @override
  Widget build(BuildContext context) => Row(children: [
        Expanded(
          child: Text(formatEta(durationS),
              style: AppTextStyles.headlineLgMobile.copyWith(color: navGreen)),
        ),
        Text(formatDistance(distanceM), style: AppTextStyles.bodyMd),
      ]);
}
