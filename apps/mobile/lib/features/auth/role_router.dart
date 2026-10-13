import 'package:flutter/material.dart';

import '../../core/api/api_client.dart';
import '../driver/driver_home.dart';
import '../passenger/passenger_home.dart';

/// Shared by both LoginScreen and RegisterScreen: the one place that
/// decides which home screen a given account lands on, and clears the
/// auth stack (splash/login/register) so back-navigation doesn't return
/// to a login/register screen once signed in.
///
///   passenger  -> PassengerHome
///   driver     -> DriverHome
///   anything else -> a dialog. Shouldn't happen in practice: ApiClient
///   already rejects non-mobile roles (government uses the web dashboard,
///   admin has no client) before a result gets here.
void routeByRole(BuildContext context, AuthResult result) {
  final Widget? home = switch (result.role) {
    'passenger' => PassengerHome(token: result.token),
    'driver' => DriverHome(token: result.token),
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
