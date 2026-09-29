import 'package:flutter/material.dart';

import 'core/api/api_client.dart';
import 'core/theme/konekta_theme.dart';
import 'features/splash/splash_screen.dart';

void main() {
  runApp(const KonektaApp());
}

class KonektaApp extends StatelessWidget {
  const KonektaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KONEKTA',
      debugShowCheckedModeBanner: false,
      theme: KonektaTheme.light(),
      home: SplashScreen(apiClient: ApiClient()),
    );
  }
}
