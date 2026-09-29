import 'package:flutter/material.dart';

import '../core/theme/konekta_theme.dart';

/// KONEKTA brand mark (assets/logo.png: icon + "KONEKTA" wordmark in one
/// image). Used on the splash screen (white, over the purple background)
/// and the login screen (natural purple-on-white, as drawn).
///
/// The asset itself is purple-on-transparent; `tintWhite` re-colors every
/// opaque pixel white via a color filter instead of needing a second
/// white-only asset for the splash background.
class KonektaLogo extends StatelessWidget {
  const KonektaLogo({super.key, this.width = 160, this.tintWhite = false});

  final double width;
  final bool tintWhite;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/logo.png',
      width: width,
      fit: BoxFit.contain,
    );

    if (!tintWhite) return image;

    return ColorFiltered(
      colorFilter: const ColorFilter.mode(AppColors.onPrimary, BlendMode.srcIn),
      child: image,
    );
  }
}
