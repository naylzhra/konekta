import 'package:flutter/material.dart';

class KonektaLogo extends StatelessWidget {
  const KonektaLogo({super.key, this.width = 240, this.tintWhite = false});

  final double width;
  final bool tintWhite;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      tintWhite ? 'assets/logo_putih.png' : 'assets/logo.png',
      width: width,
      fit: BoxFit.contain,
    );
  }
}
