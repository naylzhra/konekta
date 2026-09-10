import 'package:flutter/material.dart';

import 'features/driver/driver_home.dart';
import 'features/passenger/passenger_home.dart';

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
      home: const RoleSelectScreen(),
    );
  }
}

// TODO: replace with real auth/role routing once accounts are implemented.
class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('KONEKTA')),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PassengerHome()),
              ),
              child: const Text('Passenger'),
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DriverHome()),
              ),
              child: const Text('Driver'),
            ),
          ],
        ),
      ),
    );
  }
}
