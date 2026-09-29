import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../../core/theme/konekta_theme.dart';
import '../../shared_widgets/konekta_logo.dart';
import '../auth/login_screen.dart';

/// First screen shown on launch: solid primary-container background with
/// the KONEKTA mark, then auto-advances to LoginScreen after a short
/// delay. See "Splash Screen.png" reference.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.apiClient});

  final ApiClient apiClient;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(milliseconds: 1800), _goToLogin);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _goToLogin() {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => LoginScreen(apiClient: widget.apiClient),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: AppColors.primaryContainer,
      body: Center(
        child: KonektaLogo(width: 180, tintWhite: true),
      ),
    );
  }
}
