import 'package:flutter/material.dart';

import '../../../core/strings/booking_strings.dart';
import '../../../core/theme/konekta_theme.dart';
import '../data/mock_booking_backend.dart';

/// Counts for the Home dashboard.
///
/// The gateway does not expose nearby-feeder or virtual-stop counts yet, so
/// these are stub values with `--dart-define=BOOKING_MOCK=true` and null
/// otherwise (the widgets then hide the number). Replace with real data when
/// the endpoint exists.
class HomeStats {
  const HomeStats._();

  static int? get nearbyFeeders => MockBookingBackend.enabled ? 3 : null;
  static int? get activeVirtualStops => MockBookingBackend.enabled ? 12 : null;
}

/// Tappable, read-only search field. Real input happens in the planner screen.
class HomeSearchBar extends StatelessWidget {
  const HomeSearchBar({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: BookingStrings.homeSearchHint,
      child: Material(
        color: AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: const BorderSide(color: AppColors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
            child: Row(
              children: [
                const Icon(Icons.search, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  BookingStrings.homeSearchHint,
                  style: AppTextStyles.bodyMd.copyWith(color: AppColors.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Stylised map preview with the nearby-feeder chip and a locate button.
class HomeMapHero extends StatelessWidget {
  const HomeMapHero({super.key, required this.nearbyFeeders, this.onLocate});

  /// Null when unknown: the chip is hidden.
  final int? nearbyFeeders;
  final VoidCallback? onLocate;

  @override
  Widget build(BuildContext context) {
    final feeders = nearbyFeeders;
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: SizedBox(
        height: 216,
        width: double.infinity,
        child: Stack(
          children: [
            const Positioned.fill(child: CustomPaint(painter: _MapPainter())),
            const Align(
              alignment: Alignment(-0.12, -0.3),
              child: _MapPin(color: Color(0xFF2FBF8A), size: 48),
            ),
            const Align(
              alignment: Alignment(0.52, -0.5),
              child: _MapPin(color: AppColors.primaryContainer, size: 44),
            ),
            const Align(
              alignment: Alignment(-0.38, 0.28),
              child: _MapPin(color: Color(0xFF2FBF8A), size: 20, showIcon: false),
            ),
            if (feeders != null)
              Positioned(
                top: AppSpacing.sm,
                left: AppSpacing.sm,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.inverseSurface,
                    borderRadius: BorderRadius.circular(AppRadius.full),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(color: AppColors.secondaryContainer, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        BookingStrings.feedersNearby(feeders),
                        style: AppTextStyles.labelMd.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ),
              ),
            Positioned(
              right: AppSpacing.sm,
              bottom: AppSpacing.sm,
              child: Material(
                color: Colors.white,
                shape: const CircleBorder(),
                elevation: 3,
                child: IconButton(
                  tooltip: BookingStrings.locate,
                  onPressed: onLocate,
                  icon: const Icon(Icons.my_location, color: AppColors.primary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MapPin extends StatelessWidget {
  const _MapPin({required this.color, required this.size, this.showIcon = true});

  final Color color;
  final double size;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    // A rounded square with one sharp corner, rotated so the corner points down.
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.55), blurRadius: size, spreadRadius: size / 8)],
      ),
      child: Transform.rotate(
        angle: -0.785398, // -45°
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: Colors.white.withValues(alpha: 0.85), width: 2),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(size / 2),
              topRight: Radius.circular(size / 2),
              bottomRight: Radius.circular(size / 2),
            ),
          ),
          child: showIcon
              ? Transform.rotate(
                  angle: 0.785398,
                  child: Icon(Icons.shield_outlined, color: Colors.white, size: size * 0.5),
                )
              : null,
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  const _MapPainter();

  // Blocks as (centre x, centre y, width, height, depth), all fractions of the canvas.
  static const _blocks = [
    (0.14, 0.22, 0.20, 0.08, 0.035),
    (0.42, 0.14, 0.16, 0.07, 0.03),
    (0.78, 0.12, 0.22, 0.08, 0.035),
    (0.24, 0.52, 0.24, 0.09, 0.04),
    (0.62, 0.46, 0.2, 0.08, 0.035),
    (0.90, 0.5, 0.18, 0.08, 0.03),
    (0.12, 0.84, 0.2, 0.08, 0.035),
    (0.46, 0.80, 0.26, 0.09, 0.04),
    (0.80, 0.84, 0.22, 0.08, 0.035),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFA9BBB3), Color(0xFF55655F)],
        ).createShader(rect),
    );

    final road = Paint()
      ..color = Colors.white.withValues(alpha: 0.16)
      ..strokeWidth = 1.2;
    for (var i = -4; i < 12; i++) {
      final x = size.width / 7 * i;
      canvas.drawLine(Offset(x, 0), Offset(x + size.height * 0.7, size.height), road);
    }
    for (var i = 0; i < 8; i++) {
      final y = size.height / 6 * i;
      canvas.drawLine(Offset(0, y), Offset(size.width, y - size.width * 0.22), road);
    }

    final top = Paint()..color = Colors.white.withValues(alpha: 0.30);
    final side = Paint()..color = const Color(0xFF2E3B38).withValues(alpha: 0.35);
    for (final (cx, cy, w, h, d) in _blocks) {
      final left = (cx - w / 2) * size.width;
      final right = (cx + w / 2) * size.width;
      final topY = (cy - h / 2) * size.height;
      final botY = (cy + h / 2) * size.height;
      final skew = 0.22 * (botY - topY);
      final depth = d * size.height;

      final topFace = Path()
        ..moveTo(left + skew, topY)
        ..lineTo(right + skew, topY)
        ..lineTo(right, botY)
        ..lineTo(left, botY)
        ..close();
      final front = Path()
        ..moveTo(left, botY)
        ..lineTo(right, botY)
        ..lineTo(right, botY + depth)
        ..lineTo(left, botY + depth)
        ..close();
      canvas
        ..drawPath(front, side)
        ..drawPath(topFace, top);
    }

    // Soft vignette so the chip and pins stay readable.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x33000000), Color(0x00000000), Color(0x33000000)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _MapPainter oldDelegate) => false;
}

/// Large quick-action tile. [filled] is the primary call to action.
class HomeActionCard extends StatelessWidget {
  const HomeActionCard({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final foreground = filled ? Colors.white : AppColors.inverseSurface;
    return Semantics(
      button: true,
      label: label.replaceAll('\n', ' '),
      child: Material(
        color: filled ? AppColors.primary : AppColors.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          side: BorderSide(color: filled ? AppColors.primary : AppColors.surfaceContainerHighest),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: filled ? Colors.white.withValues(alpha: 0.22) : AppColors.surfaceContainerHigh,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: filled ? Colors.white : AppColors.primary),
                ),
                Text(
                  label,
                  style: AppTextStyles.headlineMd.copyWith(
                    color: foreground,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "Current pooling" summary with a call to join a pool.
class HomePoolingCard extends StatelessWidget {
  const HomePoolingCard({super.key, required this.activeVirtualStops, this.onJoin});

  /// Null when unknown: a generic summary is shown instead of a count.
  final int? activeVirtualStops;
  final VoidCallback? onJoin;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: ColoredBox(
        color: AppColors.surfaceContainerLowest,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(width: 3, child: ColoredBox(color: AppColors.inverseSurface)),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              BookingStrings.poolingTitle,
                              style: AppTextStyles.headlineMd.copyWith(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: AppColors.inverseSurface,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.inverseSurface,
                              borderRadius: BorderRadius.circular(AppRadius.full),
                            ),
                            child: Text(
                              BookingStrings.poolingActive,
                              style: AppTextStyles.labelMd.copyWith(color: Colors.white, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.base),
                      Text(
                        switch (activeVirtualStops) {
                          final count? => BookingStrings.poolingSummary(count),
                          null => BookingStrings.poolingSummaryGeneric,
                        },
                        style: AppTextStyles.bodySm,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Material(
                        color: AppColors.surfaceContainer,
                        borderRadius: BorderRadius.circular(AppRadius.standard),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: onJoin,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
                            child: Row(
                              children: [
                                const _AvatarStack(),
                                const SizedBox(width: AppSpacing.sm),
                                Expanded(
                                  child: Text(
                                    BookingStrings.poolingJoin,
                                    style: AppTextStyles.bodySm.copyWith(
                                      color: AppColors.inverseSurface,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AvatarStack extends StatelessWidget {
  const _AvatarStack();

  static const _colors = [Color(0xFF5B5B9E), AppColors.secondaryContainer, AppColors.primaryContainer];
  static const _size = 32.0;
  static const _overlap = 20.0;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _size + _overlap * (_colors.length - 1),
      height: _size,
      child: Stack(
        children: [
          for (var i = 0; i < _colors.length; i++)
            Positioned(
              left: i * _overlap,
              child: Container(
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  color: _colors[i],
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.surfaceContainer, width: 2),
                ),
                child: Icon(
                  Icons.person_outline,
                  size: 16,
                  color: i == 1 ? AppColors.onSecondaryContainer : Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
