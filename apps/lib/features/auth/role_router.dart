import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../driver/driver_home.dart';
import '../government/government_home.dart';
import '../passenger/passenger_main.dart';

/// Shared by both LoginScreen and RegisterScreen: the one place that
/// decides which home screen a given account lands on, and clears the
/// auth stack (splash/login/register) so back-navigation doesn't return
/// to a login/register screen once signed in.
///
///   passenger  -> PassengerMain
///   driver     -> DriverHome
///   government -> GovernmentHome
///   anything else (e.g. admin, which has no mobile screen) -> a dialog
void routeByRole(BuildContext context, AuthResult result) {
  final Widget? home = switch (result.role) {
    'passenger' => PassengerMain(token: result.token),
    'driver' => DriverHome(token: result.token),
    'government' => GovernmentHome(token: result.token),
    _ => null,
  };

  if (home == null) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wrong app for this account'),
        content: Text('Role "${result.role}" is not supported in the mobile app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    return;
  }

  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => home),
    (route) => false,
  );
}
