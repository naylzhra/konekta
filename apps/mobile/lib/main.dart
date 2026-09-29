import 'package:flutter/material.dart';

import 'core/api/api_client.dart';
import 'features/auth/login_screen.dart';

void main() {
  runApp(const KonektaApp());
}

class KonektaApp extends StatelessWidget {
  const KonektaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KONEKTA',
      theme: ThemeData(colorSchemeSeed: Colors.blue, useMaterial3: true),
      home: LoginScreen(apiClient: ApiClient()),
    );
  }
}
